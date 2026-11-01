"""SVG delta encoding and portable frame sources."""

import base64
import gzip
import json
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

SVG_NS = "http://www.w3.org/2000/svg"
GLYPH_REFERENCE = "data-glissade-glyph"


def _encode_shared_svg(data, compress=True):
    raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
    media_type = "application/json"
    if compress:
        raw = gzip.compress(raw, compresslevel=9, mtime=0)
        media_type = "application/gzip"
    return f"data:{media_type};base64," + base64.b64encode(raw).decode("ascii")


def _decode_shared_svg(source):
    prefix, encoded = source.split(",", 1)
    raw = base64.b64decode(encoded, validate=True)
    if prefix == "data:application/gzip;base64":
        raw = gzip.decompress(raw)
    elif prefix != "data:application/json;base64":
        raise ValueError("Invalid shared SVG data source")
    return json.loads(raw)


def _share_scene_glyphs(scene, frame_directory):
    """Replace repeated glyph symbols with references, preserving SVG tree paths."""
    if len(scene["frames"]) < 2:
        return []
    roots = []
    counts = Counter()
    for source in scene["frames"]:
        path = Path(frame_directory) / _source_frame_name(source)
        root = ET.fromstring(path.read_text(encoding="utf-8"))
        symbols = [
            symbol
            for defs in root.iter(f"{{{SVG_NS}}}defs")
            if defs.get("id") == "glyph"
            for symbol in defs
            if symbol.tag == f"{{{SVG_NS}}}symbol"
        ]
        counts.update(_svg_element_text(symbol) for symbol in symbols)
        roots.append((path, root, symbols))

    glyphs = [markup for markup, count in counts.items() if count > 1]
    if not glyphs:
        return []
    indices = {markup: index for index, markup in enumerate(glyphs)}
    for path, root, symbols in roots:
        changed = False
        for symbol in symbols:
            index = indices.get(_svg_element_text(symbol))
            if index is None:
                continue
            # A single placeholder replaces a single symbol. Delta paths stay
            # valid both before and after restoring the original glyph.
            tail = symbol.tail
            symbol.clear()
            symbol.set(GLYPH_REFERENCE, str(index))
            symbol.tail = tail
            changed = True
        if changed:
            path.write_text(_svg_element_text(root), encoding="utf-8")
    return glyphs


def _pack_scene_svg(scene, glyphs, compress=True):
    """Share one lazily decoded payload for a scene's glyphs and delta patches."""
    patches = []
    if compress:
        for source in scene["frames"]:
            if _is_frame_delta(source) and source["patches"]:
                patches.append(source["patches"])
                source["patches"] = len(patches) - 1
    if glyphs or patches:
        scene["sharedSvg"] = _encode_shared_svg(
            {"glyphs": glyphs, "patches": patches}, compress
        )


def _svg_element_text(element):
    return ET.tostring(element, encoding="unicode", short_empty_elements=True)


def _svg_replace_patch(path, element):
    return {
        "path": path,
        "svg": _svg_element_text(element),
    }


def _svg_delta_patches(base, target, path=None):
    path = path or []
    if _svg_element_text(base) == _svg_element_text(target):
        return []
    if (
        base.tag != target.tag
        or base.attrib != target.attrib
        or (base.text or "") != (target.text or "")
        or (base.tail or "") != (target.tail or "")
    ):
        return [_svg_replace_patch(path, target)]

    base_children = list(base)
    target_children = list(target)
    if len(base_children) != len(target_children):
        return [_svg_replace_patch(path, target)]

    patches = []
    for index, (base_child, target_child) in enumerate(
        zip(base_children, target_children)
    ):
        patches.extend(_svg_delta_patches(base_child, target_child, path + [index]))

    patch_size = len(json.dumps(patches, separators=(",", ":")))
    replacement_size = len(
        json.dumps([_svg_replace_patch(path, target)], separators=(",", ":"))
    )
    if path and replacement_size < patch_size:
        return [_svg_replace_patch(path, target)]
    return patches


def _source_frame_name(frame_source):
    return urlparse(frame_source).path.removeprefix("/frames/")


def _optimize_scene_frames(scene, frame_directory):
    frames = scene.get("frames", [])
    if len(frames) < 3:
        return

    keyframes = set(scene.get("keyframes") or [0, len(frames) - 1])
    if not keyframes:
        return

    base_index = 0
    base_root = None
    base_source = None
    optimized = []

    for index, frame_source in enumerate(frames):
        frame_path = Path(frame_directory) / _source_frame_name(frame_source)
        try:
            frame_text = frame_path.read_text(encoding="utf-8")
            frame_root = ET.fromstring(frame_text)
        except Exception:
            optimized.append(frame_source)
            base_root = None
            continue

        if index in keyframes or base_root is None:
            optimized.append(frame_source)
            base_index = index
            base_root = frame_root
            base_source = frame_source
            continue

        patches = _svg_delta_patches(base_root, frame_root)
        if any(not patch.get("path") for patch in patches):
            optimized.append(frame_source)
            continue
        if not patches:
            optimized.append(
                {
                    "kind": "svg-delta-v1",
                    "base": base_index,
                    "patches": [],
                }
            )
            continue

        delta = {
            "kind": "svg-delta-v1",
            "base": base_index,
            "patches": patches,
        }
        delta_size = len(json.dumps(delta, separators=(",", ":")))
        full_size = len(frame_text)
        if base_source is not None and delta_size < full_size:
            optimized.append(delta)
        else:
            optimized.append(frame_source)

    scene["frames"] = optimized


def _is_frame_delta(frame_source):
    return isinstance(frame_source, dict) and frame_source.get("kind") == "svg-delta-v1"
