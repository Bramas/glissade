"""Versioned boundary between Typst discovery, exporters and the browser."""

import math
import time
from pathlib import Path

from .frames import _decode_shared_svg

SCHEMA_VERSION = 1


def new_manifest(args):
    return {
        "schemaVersion": SCHEMA_VERSION,
        "version": str(time.time_ns()),
        "title": getattr(args, "title", None) or Path(args.input).stem,
        "fps": args.fps,
        "progress": getattr(args, "progress", False),
        "scenes": [],
    }


def _valid_patch_content(patch):
    """A patch replaces one element (`svg`) or rebuilds a child list (`children`)."""
    if "children" not in patch:
        return isinstance(patch.get("svg"), str)
    children = patch["children"]
    return "svg" not in patch and isinstance(children, list) and all(
        isinstance(child, str) or (type(child) is int and child >= 0)
        for child in children
    )


def validate_manifest(manifest):
    """Reject incomplete frames and invalid boundaries before publishing a build."""
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError("Unsupported Glissade manifest schema")
    if not manifest.get("scenes"):
        raise ValueError("No Glissade or Touying slides found")
    ids = set()
    for scene in manifest["scenes"]:
        if not isinstance(scene.get("id"), str):
            raise ValueError("Slide ID must be a string")
        if scene["id"] in ids:
            raise ValueError(f"Duplicate slide id: {scene['id']!r}")
        ids.add(scene["id"])
        count = scene["frameCount"]
        if not isinstance(count, int) or count < 1 or len(scene["frames"]) != count:
            raise ValueError(f"Slide {scene['id']!r} has missing frames")
        if not math.isfinite(scene["fps"]) or scene["fps"] <= 0:
            raise ValueError("FPS must be greater than zero")
        if not math.isfinite(scene["duration"]) or scene["duration"] < 0:
            raise ValueError("Duration must be nonnegative")
        shared = {"glyphs": [], "patches": []}
        if "sharedSvg" in scene:
            try:
                shared = _decode_shared_svg(scene["sharedSvg"])
                if (
                    not isinstance(shared, dict)
                    or not isinstance(shared.get("glyphs"), list)
                    or any(not isinstance(glyph, str) for glyph in shared["glyphs"])
                    or not isinstance(shared.get("patches"), list)
                    or any(not isinstance(patches, list) for patches in shared["patches"])
                ):
                    raise ValueError("Invalid shared SVG payload")
            except Exception as error:
                raise ValueError("Invalid shared SVG payload") from error
        for index, source in enumerate(scene["frames"]):
            if isinstance(source, str):
                continue
            if (
                not isinstance(source, dict)
                or source.get("kind") != "svg-delta-v1"
                or not isinstance(source.get("base"), int)
                or not 0 <= source["base"] < index
            ):
                raise ValueError(
                    "SVG deltas must reference an earlier frame of the same slide"
                )
            patches = source.get("patches")
            if type(patches) is int and 0 <= patches < len(shared["patches"]):
                patches = shared["patches"][patches]
            if not isinstance(patches, list):
                raise ValueError("Invalid SVG delta patches or shared patch reference")
            for patch in patches:
                if (
                    not isinstance(patch, dict)
                    or not isinstance(patch.get("path"), list)
                    or not patch["path"]
                    or not _valid_patch_content(patch)
                    or any(
                        not isinstance(item, int) or item < 0 for item in patch["path"]
                    )
                ):
                    raise ValueError("Invalid SVG delta patch")
        for cut in scene["cuts"]:
            start = cut.get("loopStart")
            if start is not None and (
                not isinstance(start, int) or not 0 <= start < cut["frame"]
            ):
                raise ValueError("A loop must start before its cut")
        for boundaries in (scene["keyframes"], [cut["frame"] for cut in scene["cuts"]]):
            if boundaries != sorted(set(boundaries)):
                raise ValueError("Frame boundaries must be ordered and unique")
            if any(
                not isinstance(frame, int) or not 0 <= frame < count
                for frame in boundaries
            ):
                raise ValueError("Frame boundary outside slide")
    return manifest
