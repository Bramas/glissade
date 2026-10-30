import copy
import gzip
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from glissade.cli import create_parser, handle_html, handle_video_export
from glissade.compiler import compile_project
from glissade.live import LiveBuildState, make_editor_handler, watched_files
from glissade.manifest import validate_manifest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("typst"), "Typst is required for integration tests")
class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="glissade-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def source(self, name="slides", body=None):
        path = self.directory / f"{name}.typ"
        path.write_text(
            f'#import "{ROOT / "lib.typ"}": *\n'
            "#set page(width: 80mm, height: 60mm)\n#show: deck\n"
            + (
                body
                or '#slide(id: "demo")[#init(x: 0pt)#animate(x: 10pt)#context rect(width: 20pt + a("x"))]'
            ),
            encoding="utf-8",
        )
        return path

    def args(self, path, command="html", *extra):
        return create_parser().parse_args(
            ["--root", "/", str(path), command, "--fps", "2", *extra]
        )

    def test_zero_and_subframe_durations(self):
        for duration, dwell, count in [(0, 0, 1), (0.01, 0, 2), (0, 1, 3)]:
            with self.subTest(duration=duration, dwell=dwell):
                path = self.source(
                    body=f'#slide[#init(x: 0)#animate(duration: {duration}, dwell: {dwell}, x: 1)#context [#a("x")]]'
                )
                manifest = compile_project(
                    self.args(path), self.directory / f"frames-{duration}-{dwell}"
                )
                self.assertEqual(manifest["scenes"][0]["frameCount"], count)
                final = Path(manifest["scenes"][0]["frames"][-1].split("?")[0]).name
                self.assertTrue(
                    (self.directory / f"frames-{duration}-{dwell}" / final).is_file()
                )

    def test_title_is_used_and_escaped(self):
        path = self.source()
        self.assertEqual(
            handle_html(self.args(path, "html", "--title", "A < B & C")), 0
        )
        result = path.with_suffix(".html").read_text()
        self.assertIn("<title>A &lt; B &amp; C</title>", result)
        self.assertIn('"title":"A \\u003c B & C"', result)

    def test_external_exports_are_isolated(self):
        first = self.source("first")
        self.assertEqual(handle_html(self.args(first, "html", "--no-embed-frames")), 0)
        original = {
            path.name: path.read_bytes()
            for path in (self.directory / "first.frames").iterdir()
        }
        second = self.source(
            "second",
            first.read_text().split("#show: deck\n", 1)[1].replace("10pt", "30pt"),
        )
        self.assertEqual(handle_html(self.args(second, "html", "--no-embed-frames")), 0)
        self.assertEqual(
            original,
            {
                path.name: path.read_bytes()
                for path in (self.directory / "first.frames").iterdir()
            },
        )
        self.assertTrue((self.directory / "second.frames").is_dir())
        self.assertIn("first.frames/", first.with_suffix(".html").read_text())
        for value in original.values():
            self.assertIn(b"<svg", gzip.decompress(value))

    def test_all_examples_compile(self):
        sources = [
            *sorted((ROOT / "site/examples").glob("*.typ")),
            ROOT / "examples/slides.typ",
            ROOT / "examples/touying.typ",
            ROOT / "examples/standup-gathering/talk.typ",
        ]
        for source in sources:
            with self.subTest(source=source.name):
                manifest = compile_project(
                    self.args(source), self.directory / source.stem
                )
                validate_manifest(manifest)

    def test_manifest_rejects_missing_frames_and_invalid_boundaries(self):
        manifest = compile_project(self.args(self.source()), self.directory / "frames")
        for corrupt in [
            lambda scene: scene["frames"].pop(),
            lambda scene: scene["cuts"].append({"frame": 999}),
        ]:
            bad = copy.deepcopy(manifest)
            corrupt(bad["scenes"][0])
            with self.assertRaises(ValueError):
                validate_manifest(bad)

    def test_watcher_detects_assets_and_ignores_outputs(self):
        path = self.source()
        args = self.args(path, "dev")
        args.root = str(self.directory)
        for extension in ["svg", "png", "csv", "json", "bib"]:
            asset = self.directory / f"asset.{extension}"
            before = watched_files(args)
            asset.write_bytes(b"new asset")
            self.assertNotEqual(before, watched_files(args))
        before = watched_files(args)
        output = self.directory / "slides.frames"
        output.mkdir()
        (output / "frame.svg").write_text("<svg/>")
        self.assertEqual(before, watched_files(args))

    def test_live_build_keeps_last_success_and_cleans_up(self):
        path = self.source(body='#slide(id: "a")[A]#slide(id: "b")[B]')
        state = LiveBuildState(self.args(path, "dev"))
        self.addCleanup(state.close)
        with patch.object(state, "log"):
            self.assertTrue(state.build())
            previous = state.build_directory
            original = {p.name: p.read_bytes() for p in previous.glob("*.svg")}
            path.write_text("#this-is-invalid(")
            self.assertFalse(state.build())
            self.assertEqual(state.build_directory, previous)
            self.assertEqual(
                original, {p.name: p.read_bytes() for p in previous.glob("*.svg")}
            )
            self.source(body='#slide(id: "a")[A revised]#slide(id: "b")[B revised]')
            state.invalidate_all()
            self.assertTrue(state.build())
            self.assertIn("b", state.dirty_ids)
            self.assertTrue(state.select("b"))
            self.assertTrue(state.build())
            self.assertFalse(
                state.select("a"), "Compiling b must not invalidate a again"
            )
            self.assertLessEqual(len(state._directories), 2)
        temporary = Path(state._temporary.name)
        state.close()
        self.assertFalse(temporary.exists())

    def test_live_dirty_slides_keep_matching_frames_and_metadata(self):
        path = self.source(
            body='#slide(id: "a")[A]#slide(id: "b")[#init(x: 0)#animate(x: 1)#context [#a("x")]]'
        )
        state = LiveBuildState(self.args(path, "dev"))
        self.addCleanup(state.close)
        with patch.object(state, "log"):
            self.assertTrue(state.build())
            self.assertEqual(state.manifest["scenes"][1]["frameCount"], 3)
            path.write_text(
                path.read_text().replace(
                    "#animate(x: 1)", "#animate(duration: 4, x: 1)"
                )
            )
            state.invalidate_all()
            self.assertTrue(state.build())
            self.assertEqual(state.manifest["scenes"][1]["frameCount"], 3)
            self.assertEqual(state.manifest["scenes"][1]["duration"], 1)
            self.assertTrue(state.select("b"))
            self.assertTrue(state.build())
            self.assertEqual(state.manifest["scenes"][1]["frameCount"], 9)
            self.assertEqual(state.manifest["scenes"][1]["duration"], 4)
            self.assertFalse(state.select("a"))

    def test_live_frame_requests_read_the_requested_build(self):
        path = self.source(body='#slide(id: "a")[First]')
        state = LiveBuildState(self.args(path, "dev"))
        self.addCleanup(state.close)

        class Request:
            def __init__(self, url):
                self.input = io.BytesIO(f"GET {url} HTTP/1.0\r\n\r\n".encode())
                self.output = bytearray()

            def makefile(self, *args):
                return self.input

            def sendall(self, data):
                self.output.extend(data)

        with patch.object(state, "log"):
            self.assertTrue(state.build())
            old_url = state.manifest["scenes"][0]["frames"][0]
            filename = old_url.split("?")[0].rsplit("/", 1)[-1]
            old_content = (state.build_directory / filename).read_bytes()
            path.write_text(path.read_text().replace("First", "Second"))
            self.assertTrue(state.build())
            request = Request(old_url)
            make_editor_handler(state, b"editor")(request, ("127.0.0.1", 0), None)
            self.assertTrue(bytes(request.output).endswith(old_content))
            self.assertTrue(state.build())
            request = Request(old_url)
            make_editor_handler(state, b"editor")(request, ("127.0.0.1", 0), None)
            self.assertIn(b"404", bytes(request.output).split(b"\r\n", 1)[0])

    @unittest.skipUnless(
        shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required"
    )
    def test_native_and_touying_video_exports(self):
        native = self.source(
            body='#slide[#init(x: 0)#animate(x: 1)#cut()#animate(x: 2)#context [#a("x")]]'
        )
        touying = self.directory / "touying.typ"
        touying.write_text(
            (ROOT / "examples/touying.typ")
            .read_text()
            .replace('"../lib.typ"', f'"{ROOT / "lib.typ"}"')
        )
        for source in [native, touying]:
            for cut in ["none", "scene", "all"]:
                with self.subTest(source=source.name, cut=cut):
                    for old in self.directory.glob("*.mp4"):
                        old.unlink()
                    self.assertEqual(
                        handle_video_export(
                            self.args(source, "video", "--ppi", "30", "--cut", cut)
                        ),
                        0,
                    )
                    videos = list(self.directory.glob("*.mp4"))
                    self.assertTrue(videos)
                    for video in videos:
                        report = json.loads(
                            subprocess.check_output(
                                [
                                    "ffprobe",
                                    "-v",
                                    "error",
                                    "-show_streams",
                                    "-of",
                                    "json",
                                    str(video),
                                ]
                            )
                        )
                        self.assertGreater(int(report["streams"][0]["nb_frames"]), 0)
                        self.assertEqual(report["streams"][0]["avg_frame_rate"], "2/1")


class ParserTests(unittest.TestCase):
    def test_fps_must_be_positive(self):
        for value in ["0", "-1"]:
            with self.assertRaises(SystemExit):
                create_parser().parse_args(["slides.typ", "html", "--fps", value])


if __name__ == "__main__":
    unittest.main()
