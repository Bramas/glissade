"""Portable SVG storage round trips and manifest validation."""

import copy
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from glissade.frames import (
    GLYPH_REFERENCE,
    SVG_NS,
    _decode_shared_svg,
    _encode_shared_svg,
    _optimize_scene_frames,
    _pack_scene_svg,
    _share_scene_glyphs,
)
from glissade.manifest import validate_manifest


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
