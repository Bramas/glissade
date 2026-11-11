"""Portable SVG storage round trips and manifest validation."""

import copy
import gzip
import json
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from glissade.frames import (
    GLYPH_REFERENCE,
    SVG_NS,
    XLINK_NS,
    SceneEncoder,
    _decode_shared_svg,
    _encode_shared_svg,
    _optimize_scene_frames,
    _pack_scene_svg,
    _share_scene_glyphs,
    encode_scene,
)
from glissade.manifest import validate_manifest
from glissade.svg_tagger import needs_tagging


def fragment(markup):
    """Parse patch markup the way the browser does: inside an SVG wrapper."""
    wrapper = f'<svg xmlns="{SVG_NS}" xmlns:xlink="{XLINK_NS}">{markup}</svg>'
    return ET.fromstring(wrapper)[0]


def rebuild(sources, glyphs=()):
    """Reference decoder: the frames a browser would draw, as canonical XML."""
    texts = []
    for source in sources:
        if isinstance(source, str):
            root = ET.fromstring(source)
        else:
            root = ET.fromstring(texts[source["base"]])
            for patch in source["patches"]:
                element = root
                for index in patch["path"][:-1]:
                    element = element[index]
                if "children" in patch:
                    element = element[patch["path"][-1]]
                    originals = list(element)
                    for child in originals:
                        element.remove(child)
                    for child in patch["children"]:
                        element.append(
                            copy.deepcopy(originals[child])
                            if isinstance(child, int)
                            else fragment(child)
                        )
                else:
                    element[patch["path"][-1]] = fragment(patch["svg"])
        texts.append(ET.tostring(root, encoding="unicode"))
    frames = []
    for text in texts:
        root = ET.fromstring(text)
        for parent in root.iter():
            for index, child in enumerate(list(parent)):
                reference = child.get(GLYPH_REFERENCE)
                if reference is not None:
                    parent[index] = ET.fromstring(glyphs[int(reference)])
        frames.append(ET.canonicalize(ET.tostring(root, encoding="unicode")))
    return frames


class FrameStorageTests(unittest.TestCase):
    def test_shared_glyphs_preserve_ids_content_and_delta_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            scene = {"frames": [], "keyframes": [0, 3]}
            originals = []
            for index, color in enumerate(["red", "blue", "red", "blue"]):
                # The same ID can name different outlines in different frames.
                svg = (
                    f'<svg xmlns="{SVG_NS}"><g transform="translate({index})">'
                    '<use href="#g1"/></g><defs id="glyph">'
                    f'<symbol id="g1"><path fill="{color}" d="M0 0h10v10Z"/>'
                    '</symbol></defs><defs id="other"><symbol id="local"/>'
                    '</defs></svg>'
                )
                name = f"frame-{index}.svg"
                (Path(directory) / name).write_text(svg)
                scene["frames"].append(name)
                originals.append(ET.fromstring(svg))

            glyphs = _share_scene_glyphs(scene, directory)
            self.assertEqual(len(glyphs), 2)
            for name, original in zip(scene["frames"], originals):
                root = ET.parse(Path(directory) / name).getroot()
                placeholder = root.find(f".//{{{SVG_NS}}}symbol[@{GLYPH_REFERENCE}]")
                self.assertIsNotNone(placeholder)
                defs = root.find(f"{{{SVG_NS}}}defs")
                defs[0] = ET.fromstring(glyphs[int(placeholder.get(GLYPH_REFERENCE))])
                self.assertEqual(ET.tostring(root), ET.tostring(original))
                self.assertIsNotNone(root.find(f'.//{{{SVG_NS}}}symbol[@id="local"]'))

            _optimize_scene_frames(scene, directory)
            self.assertTrue(any(isinstance(frame, dict) for frame in scene["frames"]))
            _pack_scene_svg(scene, glyphs)
            shared = _decode_shared_svg(scene["sharedSvg"])
            self.assertEqual(shared["glyphs"], glyphs)
            self.assertTrue(shared["patches"])
            for frame in scene["frames"]:
                if isinstance(frame, dict) and type(frame["patches"]) is int:
                    self.assertIsInstance(shared["patches"][frame["patches"]], list)

    def test_deltas_rebuild_every_frame(self):
        def frame(children, move=0):
            body = "".join(children)
            return (
                f'<svg xmlns="{SVG_NS}" xmlns:xlink="{XLINK_NS}">\n'
                f'  <g transform="translate({move} 0)">{body}</g>\n'
                '  <defs id="glyph"><symbol id="a"><path d="M0 0h1"/></symbol></defs>\n'
                "</svg>"
            )

        label = '<g class="label"><use xlink:href="#a" x="1"/><use xlink:href="#a" x="2"/></g>'
        circle = '<path d="M0 0h9v9Z" fill="blue"/>'
        note = '<g class="note"><path d="M1 1h2&lt;" fill="a&amp;b"/></g>'
        frames = [
            frame([label, circle]),
            frame([label, circle], move=4),
            # An element appears between two unchanged ones, then one leaves.
            frame([label, note, circle]),
            frame([note, circle, circle]),
            frame([circle, label]),
            frame([label, circle]),
        ]
        encoder = SceneEncoder([0, len(frames) - 1])
        sources = [encoder.encode(index, text)[0] for index, text in enumerate(frames)]
        self.assertTrue(all(isinstance(source, dict) for source in sources[1:-1]))
        self.assertTrue(
            any("children" in patch for patch in sources[2]["patches"]),
            "an inserted element must not resend its siblings",
        )
        self.assertNotIn(label, json.dumps(sources[2]))
        self.assertNotIn("xmlns", json.dumps(sources[1:-1]))
        expected = [
            ET.canonicalize(text, strip_text=True) for text in frames
        ]
        self.assertEqual(rebuild(sources, encoder.glyphs), expected)
        scene = {"id": "demo", "fps": 12, "duration": 1, "frameCount": len(frames),
                 "frames": [source if isinstance(source, dict) else "full.svg" for source in sources],
                 "keyframes": [0, len(frames) - 1], "cuts": []}
        manifest = {"schemaVersion": 1, "scenes": [scene]}
        validate_manifest(manifest)
        for corrupt in [{"children": [0, -1]}, {"children": [0.5]}, {"children": "0"},
                        {"children": [0], "svg": "<g/>"}, {}]:
            bad = copy.deepcopy(manifest)
            bad["scenes"][0]["frames"][2]["patches"] = [{"path": [0], **corrupt}]
            with self.subTest(patch=corrupt), self.assertRaises(ValueError):
                validate_manifest(bad)

    def test_encode_scene_reads_each_frame_once(self):
        with tempfile.TemporaryDirectory() as directory:
            names = []
            for index in range(5):
                name = f"slide-001-demo-frame-{index + 1}.svg"
                (Path(directory) / name).write_text(
                    f'<svg xmlns="{SVG_NS}">\n <g><path d="M{index} 0h5"/></g>\n'
                    ' <g><path d="M0 9h9"/><path d="M0 8h9"/><path d="M0 7h9"/></g>\n'
                    ' <defs id="glyph"><symbol id="a"><path d="M0 0h1"/></symbol></defs>\n</svg>'
                )
                names.append(f"/frames/{name}?v=1")
            for compress in (True, False):
                scene = {"frames": list(names), "keyframes": [0, 4]}
                scene, sources = encode_scene(scene, directory, compress=compress)
                self.assertEqual([isinstance(source, dict) for source in sources],
                                 [False, True, True, True, False])
                name, data = sources[0]
                self.assertEqual(name, "slide-001-demo-frame-1.svg")
                text = (gzip.decompress(data) if compress else data).decode()
                self.assertNotIn("\n", text)
                self.assertIn(GLYPH_REFERENCE, text)
                shared = _decode_shared_svg(scene["sharedSvg"])
                self.assertEqual(len(shared["glyphs"]), 1)
                self.assertEqual(len(shared["patches"]), 3 if compress else 0)

    def test_untagged_frames_are_recognized_without_parsing(self):
        self.assertFalse(needs_tagging(f'<svg xmlns="{SVG_NS}"><path fill="#2c5cc5"/></svg>'))
        self.assertTrue(needs_tagging('<svg><path fill="#FF4FD8"/></svg>'))
        self.assertTrue(needs_tagging('<svg><g id="glissade-morph-x"/></svg>'))
        self.assertTrue(needs_tagging('<svg><g data-glissade-part="true"/></svg>'))

    def test_uncompressed_shared_data_and_legacy_deltas_remain_readable(self):
        delta = {"kind": "svg-delta-v1", "base": 0,
                 "patches": [{"path": [0], "svg": "<g/>"}]}
        scene = {"frames": ["first.svg", copy.deepcopy(delta)]}
        _pack_scene_svg(scene, ["<symbol id='été'/>"], compress=False)
        self.assertTrue(scene["sharedSvg"].startswith("data:application/json;base64,"))
        self.assertEqual(scene["frames"][1], delta)
        self.assertEqual(_decode_shared_svg(scene["sharedSvg"])["glyphs"], ["<symbol id='été'/>"])

    def test_manifest_validates_shared_patch_indices_and_contents(self):
        scene = {"id": "demo", "fps": 12, "duration": 1, "frameCount": 2,
                 "frames": ["first.svg", {"kind": "svg-delta-v1", "base": 0, "patches": 0}],
                 "keyframes": [0, 1], "cuts": []}
        shared = {"glyphs": [], "patches": [[{"path": [0], "svg": "<g/>"}]]}
        scene["sharedSvg"] = _encode_shared_svg(shared)
        manifest = {"schemaVersion": 1, "scenes": [scene]}
        validate_manifest(manifest)
        looping = copy.deepcopy(manifest)
        looping["scenes"][0]["cuts"] = [{"frame": 1, "loop": True, "loopStart": 0}]
        validate_manifest(looping)
        for start in [1, 2, -1, 0.5]:
            looping["scenes"][0]["cuts"][0]["loopStart"] = start
            with self.subTest(loopStart=start), self.assertRaises(ValueError):
                validate_manifest(looping)
        for patches in [-1, 1, True, None]:
            bad = copy.deepcopy(manifest)
            bad["scenes"][0]["frames"][1]["patches"] = patches
            with self.subTest(patches=patches), self.assertRaises(ValueError):
                validate_manifest(bad)
        for corrupt in [None, "not a data URI", _encode_shared_svg({"glyphs": 1, "patches": []})]:
            bad = copy.deepcopy(manifest)
            bad["scenes"][0]["sharedSvg"] = corrupt
            with self.subTest(sharedSvg=corrupt), self.assertRaises(ValueError):
                validate_manifest(bad)
        shared["patches"][0][0]["path"] = [-1]
        scene["sharedSvg"] = _encode_shared_svg(shared)
        with self.assertRaises(ValueError):
            validate_manifest(manifest)
