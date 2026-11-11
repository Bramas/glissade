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

    def manifest(self, name):
        import json

        text = (self.directory / f"{name}.html").read_text()
        start = text.index("Promise.resolve({") + len("Promise.resolve(")
        return json.JSONDecoder().raw_decode(text[start:])[0]

    def render(self, frame, scene=0):
        self.page.evaluate("([s, f]) => GlissadeDebug.renderFrame(s, f)", [scene, frame])

    def box(self, selector):
        return self.page.evaluate(
            """(selector) => {
                // Relative to the stage, so the comparison does not depend on
                // when the player refits the stage to the window.
                const element = document.querySelector(selector);
                const stage = element?.closest(".glissade-stage-stack");
                if (!element || !stage) return null;
                const rect = element.getBoundingClientRect();
                const frame = stage.getBoundingClientRect();
                return [
                    (rect.x - frame.x) / frame.width,
                    (rect.y - frame.y) / frame.height,
                    rect.width / frame.width,
                    rect.height / frame.height,
                ];
            }""",
            selector,
        )

    def assertBoxesClose(self, actual, expected, tolerance=0.004):
        self.assertIsNotNone(actual)
        self.assertIsNotNone(expected)
        for got, want in zip(actual, expected):
            self.assertAlmostEqual(got, want, delta=tolerance, msg=f"{actual} != {expected}")

    def test_formula_overlays_stay_aligned_at_any_viewport(self):
        # Regression: unmatched formula pieces (exponents, operators) are drawn
        # in overlay layers that must coincide with the formula they fade from,
        # whatever the stage size and the SVG's own units (Typst uses pt).
        self.export("showcase")
        blocks = self.manifest("showcase")["scenes"][0]["blocks"]
        swap = next(block for block in blocks if block["index"] == 3)  # c^2 = a^2 + b^2
        start = swap["start_frame"]
        middle = (swap["start_frame"] + swap["end_frame"]) // 2
        base_root = '.glissade-stage-base [data-glissade-morph-id="eq"]:not([data-glissade-composite-root] *)'
        layer_root = '[data-glissade-composite-root="eq"] svg [data-glissade-morph-id="eq"]'
        for width, height in [(480, 360), (1600, 1200)]:
            with self.subTest(viewport=(width, height)):
                self.page.set_viewport_size({"width": width, "height": height})
                self.render(start)
                expected = self.box(base_root)
                self.render(middle)
                self.assertGreater(self.page.locator(layer_root).count(), 0)
                self.assertBoxesClose(self.box(layer_root), expected)
        self.assertFalse(self.errors)

    def test_deltas_draw_the_same_frames_when_elements_come_and_go(self):
        # Elements that appear or leave between two frames are encoded as a
        # rebuilt child list. The browser must draw what Typst rendered.
        body = (
            f'#import "{ROOT / "lib.typ"}": *\n'
            "#set page(width: 80mm, height: 60mm)\n#show: deck\n"
            '#slide(id: "demo")[#init(t: 0.0)#animate(t: 4.0, duration: 1, transition: "ease-in-out")'
            '#context { let t = a("t")\n'
            "  for k in range(4) { if t > k + 0.3 and t < k + 2.2 { place(dx: k * 12pt, circle(radius: 4pt, fill: blue)) } }\n"
            "  place(dy: 20pt, dx: t * 9pt, rect(width: 6pt, height: 6pt, fill: red))\n"
            "  place(dy: 34pt)[frame #calc.round(t, digits: 2)] }]"
        )
        drawn = {}
        for name, options in [("deltas", ["--no-compress-frames"]), ("plain", ["--no-optimize-frames"])]:
            source = self.directory / f"{name}.typ"
            source.write_text(body)
            args = create_parser().parse_args(
                ["--root", "/", str(source), "html", "--fps", "12", *options]
            )
            self.assertEqual(handle_html(args), 0)
            self.page.goto(
                f"https://glissade.test/{name}.html?glissade-debug=1",
                wait_until="domcontentloaded",
            )
            self.page.evaluate("GlissadeDebug.ready")
            drawn[name] = []
            for frame in range(self.manifest(name)["scenes"][0]["frameCount"]):
                self.render(frame)
                drawn[name].append(self.page.evaluate(
                    """() => {
                        const describe = element => [
                            element.localName,
                            [...element.attributes]
                                .filter(attribute => !attribute.name.startsWith("xmlns") && attribute.name !== "class")
                                .map(attribute => attribute.localName + "=" + attribute.value).sort(),
                            element.children.length ? [...element.children].map(describe) : element.textContent,
                        ];
                        return JSON.stringify(describe(document.querySelector(".glissade-stage-base")));
                    }"""
                ))
        frames = self.manifest("deltas")["scenes"][0]["frames"]
        self.assertTrue(any(
            "children" in patch
            for frame in frames if isinstance(frame, dict)
            for patch in frame["patches"]
        ))
        self.assertEqual(len(drawn["deltas"]), 13)
        self.assertEqual(drawn["deltas"], drawn["plain"])
        self.assertFalse(self.errors)

    def test_unchanged_formula_is_not_crossfaded(self):
        # While the triangle draws in, the formula does not change and must be
        # drawn as-is rather than through the morph composite.
        self.export("showcase")
        create = self.manifest("showcase")["scenes"][0]["blocks"][0]
        self.render((create["start_frame"] + create["end_frame"]) // 2)
        self.assertGreater(self.page.locator("[data-glissade-generated-draw]").count(), 0)
        self.assertEqual(self.page.locator('[data-glissade-composite-root="eq"]').count(), 0)
        self.assertEqual(
            self.page.locator('.glissade-stage-base [data-glissade-morph-id="eq"][visibility="hidden"]').count(), 0
        )
        self.assertFalse(self.errors)

    def test_compound_parts_move_with_their_exponents(self):
        # `part(a^2)` must track the exponent with its letter instead of only
        # the last glyph, so the `2` glides rather than fades.
        self.export("showcase")
        blocks = self.manifest("showcase")["scenes"][0]["blocks"]
        swap = next(block for block in blocks if block["index"] == 3)
        self.render(swap["start_frame"])
        exponents = self.page.locator('.glissade-stage-base [data-glissade-part-key$="/t"]')
        self.assertEqual(exponents.count(), 3)
        self.render((swap["start_frame"] + swap["end_frame"]) // 2)
        generated = self.page.evaluate(
            "[...document.querySelectorAll('[data-glissade-generated-morph]')].map(e => e.getAttribute('data-glissade-generated-morph'))"
        )
        self.assertTrue(any(item.endswith("/t") for item in generated), generated)
        self.assertTrue(any(item.endswith("/base") for item in generated), generated)
        self.assertFalse(self.errors)

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

    def edit(self, source):
        # Mark the current build stale so wait_compiled() sees the new one.
        self.page.evaluate("document.querySelector('[data-status]').dataset.mode = 'stale'")
        self.page.locator("#typst-source").fill(source)

    def wait_compiled(self):
        self.page.wait_for_function(
            'document.querySelector("[data-status]").dataset.mode === "ok"',
            timeout=90_000,
        )

    def scrub(self, frame):
        self.page.evaluate(
            """(frame) => {
                const button = document.querySelector('[data-frame-action="play"]');
                if (button.classList.contains("is-playing")) button.click();
                const scrubber = document.querySelector("[data-frame-scrubber]");
                scrubber.value = String(frame);
                scrubber.dispatchEvent(new Event("input"));
            }""",
            frame,
        )
        self.page.wait_for_function(
            '(frame) => document.querySelector("[data-frame-status]").textContent.includes("Frame " + (frame + 1) + "/")',
            arg=frame,
        )
        self.page.wait_for_timeout(300)

    def test_playground_formula_morph_and_draw(self):
        self.page.goto(
            "https://glissade.test/site/playground.html", wait_until="domcontentloaded"
        )
        self.wait_compiled()
        self.page.locator("[data-example-select]").select_option("formula-morph")
        self.page.wait_for_function(
            'document.querySelector("#typst-source").value.includes("Move a term across")'
        )
        self.wait_compiled()
        root = '#typst-preview .glissade-stage-base [data-glissade-morph-id="eq"]:not([data-glissade-composite-root] *)'
        layer_root = '#typst-preview [data-glissade-composite-root="eq"] svg [data-glissade-morph-id="eq"]'
        self.scrub(0)
        expected = self.box(root)
        self.scrub(6)
        self.assertGreater(
            self.page.locator("#typst-preview [data-glissade-generated-morph]").count(), 0
        )
        self.assertBoxesClose(self.box(layer_root), expected)

        self.page.locator("[data-example-select]").select_option("create")
        self.page.wait_for_function(
            'document.querySelector("#typst-source").value.includes("Introduce content")'
        )
        self.wait_compiled()
        self.scrub(6)
        self.assertGreater(
            self.page.locator("#typst-preview [data-glissade-generated-draw]").count(), 0
        )

        # Compound parts keep their exponent in the playground renderer too.
        self.edit(
            '#import "glissade.typ": *\n#show: deck.with(fps: 12)\n#slide[\n'
            '#init(eq: formula($part(a^2) part(+) part(b)$))\n'
            '#animate(eq: formula($part(b) part(+) part(a^2)$))\n'
            '#context glissade-morph("eq")\n]\n'
        )
        self.wait_compiled()
        self.scrub(6)
        generated = self.page.evaluate(
            "[...document.querySelectorAll('#typst-preview [data-glissade-generated-morph]')].map(e => e.getAttribute('data-glissade-generated-morph'))"
        )
        self.assertTrue(any("/t::" in item for item in generated), generated)

        # Compile errors point at the author's own line, not the bundled library.
        self.edit('#import "glissade.typ": *\n#show: deck\n#slide[#nope]\n')
        self.page.wait_for_function(
            'document.querySelector("[data-status]").dataset.mode === "error"', timeout=30_000
        )
        self.assertIn("main.typ:3:", self.page.locator("[data-diagnostics-list]").inner_text())
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
