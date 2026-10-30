"""Real-browser regression tests. Enable with GLISSADE_BROWSER_TESTS=1."""

import os
import tempfile
import unittest
from pathlib import Path
from urllib.parse import unquote, urlparse

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


if __name__ == "__main__":
    unittest.main()
