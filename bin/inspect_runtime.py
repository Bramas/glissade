# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright"]
# ///

import argparse
import functools
import json
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description="Render one Kino runtime frame to a standalone SVG")
    parser.add_argument("html", type=Path, help="generated Kino HTML presentation")
    parser.add_argument("--scene", required=True, help="scene ID or zero-based scene index")
    parser.add_argument("--frame", required=True, type=int, help="zero-based logical frame index")
    parser.add_argument("--output", required=True, type=Path, help="output SVG path")
    args = parser.parse_args()

    html = args.html.resolve()
    if not html.is_file():
        parser.error(f"HTML presentation does not exist: {html}")
    scene = int(args.scene) if args.scene.isdecimal() else args.scene

    handler = functools.partial(QuietHandler, directory=str(html.parent))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    errors = []
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            page = browser.new_page()
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(
                f"http://127.0.0.1:{server.server_port}/{html.name}?kino-debug=1",
                wait_until="domcontentloaded",
                timeout=10_000,
            )
            page.evaluate("KinoDebug.ready")
            report = page.evaluate(
                "([scene, frame]) => KinoDebug.renderFrame(scene, frame)",
                [scene, args.frame],
            )
            svg = page.evaluate("KinoDebug.serializeFrame()")
            browser.close()
    finally:
        server.shutdown()
        server.server_close()

    if errors:
        raise RuntimeError("Browser errors: " + "; ".join(errors))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(svg, encoding="utf-8")
    report["output"] = str(args.output)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
