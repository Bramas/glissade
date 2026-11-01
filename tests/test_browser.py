"""Real-browser regression tests. Enable with GLISSADE_BROWSER_TESTS=1."""

import os
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote, urlparse
from unittest.mock import patch

from glissade.cli import create_parser, handle_html

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(
    os.environ.get("GLISSADE_BROWSER_TESTS") == "1", "Browser tests are opt-in"
)
class BrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from playwright.sync_api import sync_playwright

        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch(headless=True)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="glissade-browser-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.page = self.browser.new_page(ignore_https_errors=True)
        self.addCleanup(self.page.close)
        self.errors = []
        self.page.on("pageerror", lambda error: self.errors.append(str(error)))

        def route(request):
            path = unquote(urlparse(request.request.url).path)
            file = (
                ROOT / "site" / path.removeprefix("/site/")
                if path.startswith("/site/")
                else self.directory / path.lstrip("/")
            )
            if file.is_file():
                request.fulfill(path=str(file))
            else:
                request.fulfill(status=404, body="Not found")

        self.page.route("https://glissade.test/**", route)

    def export(self, name, *options):
        original = ROOT / "site/examples" / f"{name}.typ"
        source = self.directory / f"{name}.typ"
        source.write_text(
            original.read_text().replace('"../../lib.typ"', f'"{ROOT / "lib.typ"}"')
        )
        args = create_parser().parse_args(
            ["--root", "/", str(source), "html", "--fps", "12", *options]
        )
        self.assertEqual(handle_html(args), 0)
        self.page.goto(
            f"https://glissade.test/{name}.html?glissade-debug=1",
            wait_until="domcontentloaded",
        )
        self.page.evaluate("GlissadeDebug.ready")

    def test_morph_draw_and_external_frames(self):
        for name, options, attribute in [
            ("formula-morph", [], "data-glissade-generated-morph"),
            ("create-reveal", [], "data-glissade-generated-draw"),
            ("formula-morph", ["--no-embed-frames"], "data-glissade-generated-morph"),
            (
                "formula-morph",
                ["--no-compress-frames"],
                "data-glissade-generated-morph",
            ),
        ]:
            with self.subTest(name=name, options=options):
                self.export(name, *options)
                self.page.evaluate("GlissadeDebug.renderFrame(0, 5)")
                self.assertGreater(self.page.locator(f"[{attribute}]").count(), 0)
                self.assertTrue(
                    self.page.evaluate(
                        "!new DOMParser().parseFromString(GlissadeDebug.serializeFrame(), 'image/svg+xml').querySelector('parsererror')"
                    )
                )
                self.assertLessEqual(
                    self.page.evaluate("GlissadeDebug.cacheStats().textEntries"), 120
                )
                self.assertFalse(self.errors)

    def test_playground_formula_morph_and_draw(self):
        self.page.goto(
            "https://glissade.test/site/playground.html", wait_until="domcontentloaded"
        )
        self.page.wait_for_function(
            'document.querySelector("[data-status]").textContent === "Rendered"',
            timeout=90_000,
        )
        self.page.locator('[data-action="morph-example"]').click()
        self.page.wait_for_function(
            'document.querySelector("[data-status]").textContent === "Rendered" && document.querySelector("#typst-source").value.includes("Formula morph")',
            timeout=90_000,
        )
        for index in range(1, 7):
            self.page.locator('[data-frame-action="next"]').click()
            self.page.wait_for_function(
                '(frame) => document.querySelector("[data-frame-status]").textContent.includes("Frame " + frame + " / ")',
                arg=index + 1,
            )
        self.assertGreater(
            self.page.locator("#typst-preview [data-glissade-generated-morph]").count(),
            0,
        )
        self.page.locator("#typst-source").fill("""#import "glissade.typ": *
#set page(width: 128mm, height: 96mm)
#show: deck.with(fps: 12)
#slide[#create(card: rect(width: 45pt, height: 25pt, fill: blue))#context glissade-morph("card")]
""")
        self.page.locator('[data-action="compile"]').click()
        self.page.wait_for_function(
            'document.querySelector("[data-status]").textContent === "Rendered" && document.querySelector("[data-frame-status]").textContent.includes("Frame 1 / ")',
            timeout=90_000,
        )
        for index in range(1, 7):
            self.page.locator('[data-frame-action="next"]').click()
            self.page.wait_for_function(
                '(frame) => document.querySelector("[data-frame-status]").textContent.includes("Frame " + frame + " / ")',
                arg=index + 1,
            )
        self.assertGreater(
            self.page.locator("#typst-preview [data-glissade-generated-draw]").count(),
            0,
        )
        self.assertFalse(self.errors)

    def test_shared_glyphs_and_compressed_deltas_match_original_pixels(self):
        import json

        def compile_fixture(args, directory):
            scenes = []
            for index, color in enumerate(["red", "blue"]):
                frames = []
                for frame in range(4):
                    name = f"slide-{index}-frame-{frame}.svg"
                    glyph_color = color if frame % 2 == 0 else "green"
                    # Identical symbol IDs and placeholders in different scenes
                    # must retain their own outlines and colors in the caches.
                    svg = (
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">'
                        f'<g transform="translate({frame * 10} 0)"><use href="#g1"/></g>'
                        f'<defs id="glyph"><symbol id="g1" overflow="visible"><path fill="{glyph_color}" '
                        'd="M10 10H40V50H10Z"/></symbol></defs></svg>'
                    )
                    (Path(directory) / name).write_text(svg)
                    frames.append(f"/frames/{name}")
                scenes.append({"id": str(index), "index": index, "name": color, "fps": 3,
                               "duration": 1, "frameCount": 4, "frames": frames,
                               "keyframes": [0, 3], "cuts": [], "blocks": [], "morphAnimations": []})
            return {"schemaVersion": 1, "version": "fixture", "title": "Fixture", "fps": 3, "scenes": scenes}

        def export(name, *options):
            source = self.directory / f"{name}.typ"
            source.write_text("")
            args = create_parser().parse_args([str(source), "html", *options])
            with patch("glissade.cli.compile_svg_project", side_effect=compile_fixture):
                self.assertEqual(handle_html(args), 0)

        def capture(name):
            self.page.goto(f"https://glissade.test/{name}.html?glissade-debug=1")
            self.page.evaluate("GlissadeDebug.ready")
            screenshots = []
            for scene in range(2):
                for frame in range(4):
                    self.page.evaluate("([s, f]) => GlissadeDebug.renderFrame(s, f)", [scene, frame])
                    self.assertEqual(self.page.locator("[data-glissade-glyph]").count(), 0)
                    screenshots.append(self.page.locator(".glissade-stage-stack").screenshot())
            self.assertFalse(self.errors)
            return screenshots

        export("original", "--no-share-glyphs", "--no-optimize-frames")
        reference = capture("original")
        self.assertNotEqual(reference[0], reference[4])
        for options in [[], ["--no-embed-frames"], ["--no-compress-frames"],
                        ["--no-optimize-frames"], ["--no-share-glyphs"]]:
            with self.subTest(options=options):
                export("packed", *options)
                self.assertEqual(capture("packed"), reference)
                text = (self.directory / "packed.html").read_text()
                # Inspect the actual wire format, not just an equivalent SVG.
                start = text.index('Promise.resolve({') + len('Promise.resolve(')
                manifest, _ = json.JSONDecoder().raw_decode(text[start:])
                if not options:
                    self.assertTrue(all("sharedSvg" in scene for scene in manifest["scenes"]))
                    self.assertTrue(any(type(frame.get("patches")) is int
                                        for scene in manifest["scenes"] for frame in scene["frames"]
                                        if isinstance(frame, dict)))


if __name__ == "__main__":
    unittest.main()
