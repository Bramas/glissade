"""SVG delta encoding and portable frame sources."""

import json
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse


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
