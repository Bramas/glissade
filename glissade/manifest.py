"""Versioned boundary between Typst discovery, exporters and the browser."""

import math
import time
from pathlib import Path

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
        for index, source in enumerate(scene["frames"]):
            if isinstance(source, str):
                continue
            if (
                not isinstance(source, dict)
                or source.get("kind") != "svg-delta-v1"
                or not isinstance(source.get("base"), int)
                or not 0 <= source["base"] < index
                or not isinstance(source.get("patches"), list)
            ):
                raise ValueError(
                    "SVG deltas must reference an earlier frame of the same slide"
                )
            for patch in source.get("patches", []):
                if (
                    not patch.get("path")
                    or not isinstance(patch.get("svg"), str)
                    or any(
                        not isinstance(item, int) or item < 0 for item in patch["path"]
                    )
                ):
                    raise ValueError("Invalid SVG delta patch")
        for boundaries in (scene["keyframes"], [cut["frame"] for cut in scene["cuts"]]):
            if boundaries != sorted(set(boundaries)):
                raise ValueError("Frame boundaries must be ordered and unique")
            if any(
                not isinstance(frame, int) or not 0 <= frame < count
                for frame in boundaries
            ):
                raise ValueError("Frame boundary outside slide")
    return manifest
