"""Command-line exports for Glissade presentations."""

import argparse
import base64
import gzip
import html
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from string import Template
from urllib.parse import quote

from . import svg_tagger
from .compiler import assert_installed, compile_project, compile_svg_project
from .frames import _is_frame_delta, _optimize_scene_frames, _source_frame_name
from .live import handle_dev
from .manifest import validate_manifest


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def create_parser():
    parser = argparse.ArgumentParser(
        description="Create and export animated Typst presentations with Glissade",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  glissade.py animation.typ video --cut none --fps 24 --ppi 150
  glissade.py --root ./project presentation.typ html --fps 24
  glissade.py --root ./project presentation.typ dev
""",
    )
    parser.add_argument("--root", help="Typst root directory")

    parser.add_argument(
        "--timeout", type=positive_int, default=30, help="timeout (default: 30s)"
    )

    parser.add_argument(
        "input",
        help="input Typst file",
    )

    # Create subparsers for different commands
    subparsers = parser.add_subparsers(
        dest="output format", help="output format", metavar="output", required=True
    )

    # create subparent parser
    subparent_parser = argparse.ArgumentParser(add_help=False)

    subparent_parser.add_argument(
        "--cut",
        choices=["all", "none", "scene"],
        default="all",
        help="cuts to consider (default: all)",
    )

    subparent_parser.add_argument(
        "--fps", type=positive_int, default=30, help="frames per second (default: 30)"
    )

    subparent_parser.add_argument(
        "--ppi", type=positive_int, default=144, help="pixels per inch (default: 144)"
    )

    # =====================
    # video subcommand
    # =====================
    video_parser = subparsers.add_parser(
        "video", help="video output", parents=[subparent_parser]
    )

    video_parser.add_argument(
        "--format", type=str, default="mp4", help="output video format (default: mp4)"
    )

    video_parser.set_defaults(func=handle_video_export)

    # =====================
    # html subcommand
    # =====================
    html_parser = subparsers.add_parser(
        "html", help="dependency-free HTML presentation", parents=[subparent_parser]
    )

    html_parser.add_argument("--title", type=str, help="title of the presentation")

    html_parser.add_argument(
        "--progress",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="display a progress bar",
    )

    html_parser.add_argument(
        "--embed-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="embed SVG frames as base64 in HTML (default: True, set to False for external files)",
    )

    html_parser.add_argument(
        "--minify-svg",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="remove insignificant whitespace from exported SVG frames (default: enabled)",
    )

    html_parser.add_argument(
        "--compress-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="gzip SVG frames and decompress them lazily in the browser (default: enabled)",
    )

    html_parser.add_argument(
        "--optimize-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="store unchanged SVG subtrees once and encode smaller frame deltas when possible (default: enabled)",
    )

    html_parser.add_argument(
        "--template",
        type=str,
        default=str(Path(__file__).parent / "assets" / "present.min.html"),
        help="HTML presentation template",
    )

    html_parser.set_defaults(func=handle_html)

    # =====================
    # dev subcommand
    # =====================
    dev_parser = subparsers.add_parser(
        "dev", help="live SVG presentation editor", parents=[subparent_parser]
    )

    dev_parser.add_argument("--host", default="127.0.0.1", help="server host")
    dev_parser.add_argument("--port", type=int, default=8765, help="server port")
    dev_parser.add_argument(
        "--template",
        type=str,
        default=str(Path(__file__).parent / "assets" / "editor.min.html"),
        help="editor HTML template",
    )
    dev_parser.set_defaults(func=handle_dev)

    return parser


def _video_segments(timeline):
    """Return inclusive frame ranges split at each presentation cut."""
    frame_count = int(timeline.get("frames", 0))
    if frame_count <= 0:
        return []
    boundaries = [
        min(int(block["end_frame"]), frame_count - 1)
        for block in timeline.get("blocks", [])
        if block.get("cut")
    ]
    if not boundaries or boundaries[-1] != frame_count - 1:
        boundaries.append(frame_count - 1)
    segments = []
    start = 0
    for end in boundaries:
        if end >= start:
            segments.append((start, end - start + 1))
        start = end
    return segments


def _encode_video(args, pattern, output, *, start=0, frame_count=None):
    filters = []
    if start > 0 or frame_count is not None:
        end = start + frame_count - 1
        filters.extend(
            [
                f"select=between(n\\,{start}\\,{end})",
                f"setpts=N/({args.fps}*TB)",
            ]
        )
    if args.format.lower() == "mp4":
        filters.append("pad=ceil(iw/2)*2:ceil(ih/2)*2")

    command = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-framerate",
        str(args.fps),
        "-pattern_type",
        "glob",
        "-i",
        pattern,
    ]
    if filters:
        command += ["-vf", ",".join(filters)]
    if frame_count is not None:
        command += ["-frames:v", str(frame_count)]
    command += ["-r", str(args.fps)]
    if args.format.lower() == "mp4":
        command += [
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
        ]
    command.append(str(output))
    subprocess.run(command, timeout=args.timeout, check=True)


def handle_video_export(args):
    """Render a deck to one video, one video per slide, or one per cut."""
    assert_installed("typst")
    assert_installed("ffmpeg")
    root_path = Path(args.input).with_suffix("")

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            temporary = Path(tmpdir)
            manifest = compile_project(args, temporary / "rendered", extension="png")
            rendered = []
            sequence = temporary / "sequence"
            sequence.mkdir()
            offset = 0
            for scene in manifest["scenes"]:
                for source in scene["frames"]:
                    name = _source_frame_name(source)
                    shutil.copyfile(
                        temporary / "rendered" / name, sequence / f"{offset:08d}.png"
                    )
                    offset += 1
                rendered.append((scene, offset - scene["frameCount"]))
            pattern = str(sequence / "*.png")
            if args.cut == "none":
                _encode_video(args, pattern, f"{root_path}.{args.format}")
            elif args.cut == "scene":
                for position, (scene, start) in enumerate(rendered, 1):
                    output = (
                        f"{root_path}.{args.format}"
                        if len(rendered) == 1
                        else f"{root_path}-{position}.{args.format}"
                    )
                    _encode_video(
                        args,
                        pattern,
                        output,
                        start=start,
                        frame_count=scene["frameCount"],
                    )
            else:
                jobs = []
                for position, (scene, offset) in enumerate(rendered, 1):
                    timeline = {
                        "frames": scene["frameCount"],
                        "blocks": [
                            {"end_frame": cut["frame"], "cut": True}
                            for cut in scene["cuts"]
                        ],
                    }
                    for segment, (start, count) in enumerate(
                        _video_segments(timeline), 1
                    ):
                        jobs.append((position, segment, offset + start, count))
                for position, segment, start, count in jobs:
                    output = (
                        f"{root_path}.{args.format}"
                        if len(jobs) == 1
                        else f"{root_path}-{position}-{segment}.{args.format}"
                    )
                    _encode_video(args, pattern, output, start=start, frame_count=count)
    except subprocess.TimeoutExpired:
        print(
            f"Timeout after {args.timeout} seconds.\n"
            "hint: timeout can be increased using the --timeout option."
        )
        return 124
    except subprocess.CalledProcessError as error:
        print(f"Video conversion failed with exit code {error.returncode}.")
        return error.returncode or 1
    except Exception as error:
        print(f"Unexpected error: {error}")
        return 1
    return 0


def _read_morph_runtime_source():
    return (Path(__file__).parent / "assets" / "runtime.js").read_text(encoding="utf-8")


def render_editor_template(template_path, title, manifest_source, live_reload):
    with open(template_path, "r", encoding="utf-8") as template_file:
        template_source = template_file.read()
    runtime_source = (
        _read_morph_runtime_source()
        if "${morph_runtime_source}" in template_source
        else ""
    )
    template = Template(template_source)
    return template.substitute(
        {
            "title": html.escape(title),
            "manifest_source": manifest_source,
            "live_reload": "true" if live_reload else "false",
            "morph_runtime_source": runtime_source,
        }
    )


def handle_html(args):
    """Generate a standalone, dependency-free SVG presentation."""
    root_path, _ = os.path.splitext(args.input)
    output_dir = Path(root_path).parent
    frames_dir = output_dir / f"{Path(root_path).name}.frames"

    try:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest = compile_svg_project(args, temporary_directory)

            if args.minify_svg:
                for frame_path in Path(temporary_directory).glob("slide-*-frame-*.svg"):
                    frame_path.write_text(
                        svg_tagger.minify_svg(frame_path.read_text(encoding="utf-8")),
                        encoding="utf-8",
                    )

            if args.optimize_frames:
                for scene in manifest["scenes"]:
                    _optimize_scene_frames(scene, temporary_directory)

            if args.embed_frames:
                # Embed frames as base64
                for scene in manifest["scenes"]:
                    embedded_frames = []
                    for frame_url in scene["frames"]:
                        if _is_frame_delta(frame_url):
                            embedded_frames.append(frame_url)
                            continue
                        frame_name = _source_frame_name(frame_url)
                        frame_path = Path(temporary_directory) / frame_name
                        frame_bytes = frame_path.read_bytes()
                        if args.compress_frames:
                            frame_bytes = gzip.compress(
                                frame_bytes, compresslevel=9, mtime=0
                            )
                            media_type = "application/gzip"
                        else:
                            media_type = "image/svg+xml"
                        encoded = base64.b64encode(frame_bytes).decode("ascii")
                        embedded_frames.append(f"data:{media_type};base64," + encoded)
                    scene["frames"] = embedded_frames
            else:
                # Copy SVG files to frames directory
                frames_dir.mkdir(parents=True, exist_ok=True)
                for stale_frame in frames_dir.glob("slide-*-frame-*.svg"):
                    stale_frame.unlink()
                for stale_frame in frames_dir.glob("slide-*-frame-*.svg.gz"):
                    stale_frame.unlink()

                for scene in manifest["scenes"]:
                    external_frames = []
                    for frame_url in scene["frames"]:
                        if _is_frame_delta(frame_url):
                            external_frames.append(frame_url)
                            continue
                        frame_name = _source_frame_name(frame_url)
                        frame_path = Path(temporary_directory) / frame_name
                        if args.compress_frames:
                            frame_name += ".gz"
                        dest_path = frames_dir / frame_name
                        # Copy SVG file
                        frame_bytes = frame_path.read_bytes()
                        if args.compress_frames:
                            frame_bytes = gzip.compress(
                                frame_bytes, compresslevel=9, mtime=0
                            )
                        dest_path.write_bytes(frame_bytes)
                        # Use relative path from HTML file location
                        external_frames.append(f"{quote(frames_dir.name)}/{frame_name}")
                    scene["frames"] = external_frames

            validate_manifest(manifest)
            manifest_source = (
                "Promise.resolve("
                + json.dumps(manifest, separators=(",", ":")).replace("<", "\\u003c")
                + ")"
            )
            result = render_editor_template(
                args.template,
                manifest["title"],
                manifest_source,
                False,
            )
            output_html = f"{root_path}.html"
            with open(output_html, "w", encoding="utf-8") as output_file:
                output_file.write(result)

            if not args.embed_frames:
                print(f"HTML: {output_html}")
                print(f"SVGs: {frames_dir}/")
    except subprocess.TimeoutExpired:
        print(
            f"Timeout after {args.timeout} seconds.\nhint: timeout can be increased using the --timeout option."
        )
        return 124
    except subprocess.CalledProcessError:
        print("The above exception was raised during SVG compilation.")
        return 1
    except Exception as error:
        print(f"Unexpected error: {error}")
        return 1
    return 0


def main():
    parser = create_parser()
    pargs = parser.parse_args()
    return pargs.func(pargs)
