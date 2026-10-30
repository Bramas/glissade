#!/usr/bin/env python3
"""Measure a reproducible deck without writing generated files to the project."""

import argparse
import contextlib
import io
import json
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from glissade.cli import create_parser, handle_html  # noqa: E402
from glissade.compiler import compile_project  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slides", type=int, default=20)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument(
        "--browser",
        action="store_true",
        help="also sample Chromium heap and runtime caches (requires playwright)",
    )
    parser.add_argument(
        "--output", type=Path, help="write the JSON report to this file"
    )
    options = parser.parse_args()
    if options.slides < 1 or options.fps < 1:
        parser.error("slides and FPS must be positive")
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="glissade-benchmark-") as directory:
        temporary = Path(directory)
        source = temporary / "benchmark.typ"
        source.write_text(
            f'''#import "{root / "lib.typ"}": *
#set page(width: 128mm, height: 96mm, margin: 8mm)
#show: deck
'''
            + "\n".join(
                f"""#slide(id: "scene-{index}")[
  = Benchmark {index + 1}
  #init(x: 0pt)
  #animate(x: 100pt, duration: 3)
  #context {{
    for row in range(8) {{
      move(dx: a("x") + row * 2pt, circle(radius: 3pt, fill: blue))
    }}
  }}
]"""
                for index in range(options.slides)
            ),
            encoding="utf-8",
        )
        args = create_parser().parse_args(
            [
                "--root",
                "/",
                "--timeout",
                "120",
                str(source),
                "html",
                "--fps",
                str(options.fps),
            ]
        )
        started = time.perf_counter()
        manifest = compile_project(args, temporary / "frames")
        compile_seconds = time.perf_counter() - started
        started = time.perf_counter()
        with contextlib.redirect_stdout(io.StringIO()):
            status = handle_html(args)
        if status:
            raise RuntimeError(f"HTML export failed ({status})")
        report = {
            "slides": options.slides,
            "fps": options.fps,
            "frames": sum(scene["frameCount"] for scene in manifest["scenes"]),
            "svgCompileSeconds": round(compile_seconds, 3),
            "htmlExportSeconds": round(time.perf_counter() - started, 3),
            "svgBytes": sum(
                path.stat().st_size for path in (temporary / "frames").glob("*.svg")
            ),
            "htmlBytes": source.with_suffix(".html").stat().st_size,
        }
        if options.browser:
            from playwright.sync_api import sync_playwright

            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(
                    args=["--enable-precise-memory-info"]
                )
                page = browser.new_page()
                page.goto(source.with_suffix(".html").as_uri() + "?glissade-debug=1")
                page.evaluate("GlissadeDebug.ready")
                peak = 0
                for index, scene in enumerate(manifest["scenes"]):
                    for frame in range(scene["frameCount"]):
                        page.evaluate(
                            "([scene, frame]) => GlissadeDebug.renderFrame(scene, frame)",
                            [index, frame],
                        )
                    peak = max(
                        peak, page.evaluate("performance.memory?.usedJSHeapSize || 0")
                    )
                report["browser"] = {
                    "peakSampledHeapBytes": peak,
                    "cache": page.evaluate("GlissadeDebug.cacheStats()"),
                }
                browser.close()
    encoded = json.dumps(report, indent=2) + "\n"
    if options.output:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")


if __name__ == "__main__":
    main()
