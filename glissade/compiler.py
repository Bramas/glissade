"""Typst compilation and scene discovery shared by every exporter."""

import copy
import json
import math
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

from . import svg_tagger
from .manifest import new_manifest, validate_manifest


def assert_installed(program: str):
    if shutil.which(program) is None:
        raise RuntimeError(f"Failed to run {program}. Is {program} installed?")


def run_typst(args, command, *, capture_output=False):
    """Run Typst with the CLI's timeout and project root settings."""
    if args.root is not None:
        command += ["--root", os.path.abspath(args.root)]
    return subprocess.run(
        command,
        timeout=args.timeout,
        check=True,
        capture_output=capture_output,
        text=capture_output,
    )


def frame_number(path):
    match = re.search(r"frame-(\d+)\.(?:svg|png)$", str(path))
    return int(match.group(1)) if match else -1


def _sanitize_formula_part_token(value):
    token = re.sub(r"[^a-zA-Z0-9_-]+", "-", str(value)).strip("-_")
    return token or "part"


def _dedupe_formula_parts(parts):
    counts = {}
    deduped = []
    for part in parts:
        part = dict(part)
        part_id = part["id"]
        count = counts.get(part_id, 0)
        counts[part_id] = count + 1
        if count > 0:
            part["id"] = f"{part_id}-{count + 1}"
        deduped.append(part)
    return deduped


def _transition_function(name):
    if name == "quad":
        return lambda t: t**2
    if name == "cubic":
        return lambda t: t**3
    if name == "quart":
        return lambda t: t**4
    if name == "sin":
        return lambda t: 1 - math.cos(t * math.pi / 2)
    if name == "circ":
        return math.sqrt
    return lambda t: t


def _visible_formula_value(value):
    if not isinstance(value, dict):
        return None
    kind = value.get("glissade-type")
    if kind == "formula-transition":
        return value.get("from") if value.get("progress", 0) < 1 else value.get("to")
    if kind == "formula":
        return value
    return None


def _collect_formula_parts_from_content(content):
    if not isinstance(content, dict):
        return []
    if (
        content.get("func") == "metadata"
        and isinstance(content.get("value"), dict)
        and content["value"].get("glissade-formula-part")
    ):
        key = content["value"].get("key", "part")
        body = content["value"].get("body")
        return [{"key": key, "body": body}]

    parts = []
    for field in (
        "children",
        "child",
        "body",
        "base",
        "num",
        "denom",
        "t",
        "b",
        "tl",
        "tr",
        "bl",
        "br",
        "sub",
        "sup",
    ):
        value = content.get(field)
        if isinstance(value, list):
            for item in value:
                parts.extend(_collect_formula_parts_from_content(item))
        elif isinstance(value, dict):
            parts.extend(_collect_formula_parts_from_content(value))
    return parts


def _formula_parts_for_value(value):
    formula = _visible_formula_value(value)
    if formula is not None:
        return formula.get("parts", [])
    return _collect_formula_parts_from_content(value)


def _resolve_timeline_value(name_dict, block, time_value):
    start = block - 1
    while str(start) not in name_dict:
        start -= 1
    start_value = name_dict[str(start)][-1][0]

    if str(block) not in name_dict:
        return start_value

    current_start = start_value
    for entry in name_dict[str(block)]:
        end_value, hold, duration, dwell, transition = entry[:5]
        if hold > time_value:
            break
        if time_value < hold + duration + dwell:
            if (
                isinstance(current_start, dict)
                and isinstance(end_value, dict)
                and current_start.get("glissade-type") == "formula"
                and end_value.get("glissade-type") == "formula"
            ):
                if duration == 0:
                    progress = 1
                else:
                    progress = min(1, max(0, (time_value - hold) / duration))
                return {
                    "glissade-type": "formula-transition",
                    "from": current_start,
                    "to": end_value,
                    "progress": _transition_function(transition)(progress),
                }
            if duration == 0 or time_value >= hold + duration:
                return end_value
            return current_start
        current_start = end_value
    return current_start


def _frame_block_and_time(blocks, frame_index):
    for block in blocks:
        start_frame = int(block.get("start_frame", 0))
        end_frame = int(block.get("end_frame", start_frame))
        if start_frame <= frame_index and (
            frame_index < end_frame or block is blocks[-1]
        ):
            block_frame_count = end_frame - start_frame
            if block_frame_count <= 0:
                return int(block["index"]), float(block.get("duration", 0))
            offset = frame_index - start_frame
            duration = float(block.get("duration", 0))
            return int(block["index"]), duration * offset / block_frame_count
    if blocks:
        last = blocks[-1]
        return int(last["index"]), float(last.get("duration", 0))
    return 1, 0.0


def _transition_effect_for_frame(name_dict, block, time_value):
    active = None
    for entry in name_dict.get(str(block), []):
        if len(entry) < 6:
            continue
        _, hold, duration, dwell, _, effect = entry
        if hold <= time_value:
            active = effect
            if time_value <= hold + duration + dwell:
                break
    return active


def _morph_animations(morph_specs, variables, blocks, fps):
    block_by_index = {int(block["index"]): block for block in blocks}
    animations = []
    for morph in morph_specs:
        state = morph.get("state")
        morph_id = morph.get("id")
        if state is None or morph_id is None:
            continue
        for block_key, entries in variables.get(str(state), {}).items():
            if not str(block_key).isdigit() or int(block_key) == 0:
                continue
            block = block_by_index.get(int(block_key))
            if block is None:
                continue
            for entry in entries:
                if len(entry) < 6 or entry[5] is None:
                    continue
                _, hold, duration, _, _, effect = entry
                span = int(block["end_frame"]) - int(block["start_frame"])

                def at(time_value):
                    progress = (
                        time_value / block["duration"] if block["duration"] else 0
                    )
                    return int(block["start_frame"]) + math.floor(span * progress + 0.5)

                start_frame = at(hold)
                end_frame = at(hold + duration)
                animations.append(
                    {
                        "id": str(morph_id).removeprefix(svg_tagger.MORPH_ID_PREFIX),
                        "state": str(state),
                        "effect": str(effect),
                        "start_frame": start_frame,
                        "end_frame": end_frame,
                    }
                )
    return animations


def _extract_slide_variables(metadata):
    variables = {}
    pending_slide_id = None
    for item in metadata:
        if "glissade_slide_scope" in item:
            pending_slide_id = str(item["glissade_slide_scope"])
            continue
        if pending_slide_id is None:
            continue
        if "glissade_animation_scope" in item and pending_slide_id not in variables:
            variables[pending_slide_id] = item["glissade_animation_scope"].get(
                "variables", {}
            )
            pending_slide_id = None
    return variables


def _extract_slide_morph_specs(metadata):
    morph_specs = {}
    pending_slide_id = None
    for item in metadata:
        if "glissade_slide_scope" in item:
            pending_slide_id = str(item["glissade_slide_scope"])
            morph_specs.setdefault(pending_slide_id, [])
            continue
        if pending_slide_id is None:
            continue
        if item.get("glissade-morph-root"):
            morph_id = item.get("id")
            morph_effect = item.get("effect")
            spec = {
                "id": None if morph_id is None else str(morph_id),
                "state": item.get("state"),
                "effect": None if morph_effect is None else str(morph_effect),
            }
            if spec not in morph_specs[pending_slide_id]:
                morph_specs[pending_slide_id].append(spec)
    return morph_specs


def _frame_formula_parts(variables, blocks, frame_index):
    block, time_value = _frame_block_and_time(blocks, frame_index)
    parts_for_frame = []
    for name, name_dict in variables.items():
        if name == "builtin_pause_counter":
            continue
        value = _resolve_timeline_value(name_dict, block, time_value)
        parts = _formula_parts_for_value(value)
        if not parts:
            continue
        for part in parts:
            key = part.get("key", "part")
            parts_for_frame.append(
                {
                    "id": f"{svg_tagger.PART_ID_PREFIX}{_sanitize_formula_part_token(name)}-{_sanitize_formula_part_token(key)}",
                    "state": str(name),
                    "key": str(key),
                }
            )
    return _dedupe_formula_parts(parts_for_frame)


def _scene_keyframes(blocks, frame_count):
    last_frame = max(0, int(frame_count) - 1)
    anchors = {0, last_frame}
    for block in blocks:
        anchors.add(max(0, min(last_frame, int(block.get("start_frame", 0)))))
        anchors.add(max(0, min(last_frame, int(block.get("end_frame", last_frame)))))
    return sorted(anchors)


def _tag_svg_frame(
    frame_path,
    *,
    variables,
    blocks,
    frame_index,
    morph_specs,
    log,
):
    """Attach formula-part and morph identifiers to one rendered SVG frame."""
    try:
        content = frame_path.read_text(encoding="utf-8")
        part_specs = _frame_formula_parts(variables, blocks, frame_index)
        active_morph_specs = []
        frame_block, frame_time = _frame_block_and_time(blocks, frame_index)
        for item in morph_specs:
            morph_id = item.get("id")
            if morph_id is None:
                continue
            state = item.get("state")
            effect = item.get("effect")
            if state is not None:
                effect = _transition_effect_for_frame(
                    variables.get(str(state), {}),
                    frame_block,
                    frame_time,
                )
            active_morph_specs.append(
                {
                    "id": morph_id
                    if morph_id.startswith(svg_tagger.MORPH_ID_PREFIX)
                    else f"{svg_tagger.MORPH_ID_PREFIX}{_sanitize_formula_part_token(morph_id)}",
                    "name": morph_id.removeprefix(svg_tagger.MORPH_ID_PREFIX)
                    if morph_id.startswith(svg_tagger.MORPH_ID_PREFIX)
                    else str(morph_id),
                    "effect": effect,
                }
            )
        if active_morph_specs:
            expanded_parts = []
            for morph in active_morph_specs:
                morph_suffix = morph["id"].removeprefix(svg_tagger.MORPH_ID_PREFIX)
                for part in part_specs:
                    expanded_parts.append(
                        {
                            "id": (
                                f"{svg_tagger.PART_ID_PREFIX}{morph_suffix}-"
                                f"{part['id'].removeprefix(svg_tagger.PART_ID_PREFIX)}"
                            ),
                            "state": part["state"],
                            "key": part["key"],
                            "morph": morph["name"],
                        }
                    )
            part_specs = expanded_parts
        tagged = svg_tagger.tag_svg_groups(
            content,
            part_specs=part_specs,
            morph_specs=active_morph_specs,
        )
        frame_path.write_text(tagged, encoding="utf-8")
    except Exception as error:
        log(f"Warning: Could not tag {frame_path.name}: {error}")


def _touying_page_records(metadata):
    """Collect laid-out Touying page, slide, and Glissade-frame markers."""
    pages = []
    current = None
    for item in metadata:
        if item.get("kind") == "touying-new-page":
            current = {
                "new_slide": False,
                "new_subslide": False,
                "logical_slide": None,
                "overlay": None,
                "glissade_frame": None,
            }
            pages.append(current)
        elif current is not None:
            if item.get("kind") == "touying-new-slide":
                current["new_slide"] = True
            elif item.get("kind") == "touying-new-subslide":
                current["new_subslide"] = True
            elif item.get("t") == "LogicalSlide":
                current["logical_slide"] = int(item["v"])
            elif item.get("t") == "Overlay":
                current["overlay"] = int(item["v"])
            elif "glissade_touying_frame" in item:
                current["glissade_frame"] = item["glissade_touying_frame"]
    return pages


def _touying_scene_groups(pages):
    groups = []
    current = []
    current_logical_slide = None
    for page in pages:
        logical_slide = page.get("logical_slide")
        starts_slide = page.get("new_slide")
        if current and (
            starts_slide
            or (
                logical_slide is not None
                and current_logical_slide is not None
                and logical_slide != current_logical_slide
            )
        ):
            groups.append(current)
            current = []
        if not current:
            current_logical_slide = logical_slide
        current.append(page)
    if current:
        groups.append(current)
    return groups


def _compile_touying_project(
    args,
    output_directory,
    metadata,
    manifest,
    *,
    slide_variables,
    slide_morph_specs,
    log,
    extension="svg",
):
    """Compile a Touying-owned deck and map its subslides to Glissade scenes."""
    page_records = _touying_page_records(metadata)
    if not page_records:
        raise ValueError("No Glissade or Touying slides found")

    compile_started = time.perf_counter()
    source_pattern = str(output_directory / f"touying-frame-{{0p}}.{extension}")
    for old_frame in output_directory.glob(f"touying-frame-*.{extension}"):
        old_frame.unlink()
    run_typst(
        args,
        [
            "typst",
            "compile",
            args.input,
            source_pattern,
            "--input",
            f"fps={args.fps}",
            "--input",
            f"glissade-force-fps={args.fps}",
            *(["--ppi", str(args.ppi)] if extension == "png" else []),
        ],
    )
    source_paths = sorted(
        output_directory.glob(f"touying-frame-*.{extension}"),
        key=frame_number,
    )
    if len(source_paths) != len(page_records):
        raise RuntimeError(
            "Touying metadata described "
            f"{len(page_records)} pages, but Typst rendered {len(source_paths)} SVGs"
        )
    log(
        f"Compiled {len(source_paths)} Touying subslide(s) in "
        f"{time.perf_counter() - compile_started:.2f}s"
    )

    source_index = 0
    groups = _touying_scene_groups(page_records)
    for scene_position, pages in enumerate(groups, start=1):
        scene_id = f"touying-slide-{scene_position}"
        frames = []
        blocks = []
        cuts = []
        morph_animations = []
        keyframes = {0, max(0, len(pages) - 1)}

        for local_index, page in enumerate(pages):
            source_path = source_paths[source_index]
            source_index += 1
            marker = page.get("glissade_frame")
            if marker is not None and extension == "svg":
                animation_id = str(marker.get("id", "animation"))
                _tag_svg_frame(
                    source_path,
                    variables=slide_variables.get(animation_id, {}),
                    blocks=marker.get("blocks", []),
                    frame_index=int(marker.get("frame", 0)),
                    morph_specs=slide_morph_specs.get(animation_id, []),
                    log=log,
                )
            frame_name = (
                f"slide-{scene_position:03d}-{scene_id}"
                f"-frame-{local_index + 1}.{extension}"
            )
            frame_path = output_directory / frame_name
            frame_path.write_bytes(source_path.read_bytes())
            frames.append(f"/frames/{frame_name}?v={manifest['version']}")

            if marker is None:
                cuts.append(
                    {
                        "frame": local_index,
                        "time": local_index / args.fps,
                        "loop": False,
                    }
                )
                keyframes.add(local_index)
                continue

            marker_frame = int(marker.get("frame", 0))
            if marker_frame == 0:
                animation_id = str(marker.get("id", "animation"))
                for morph in _morph_animations(
                    slide_morph_specs.get(animation_id, []),
                    slide_variables.get(animation_id, {}),
                    marker.get("blocks", []),
                    int(marker.get("fps", args.fps)),
                ):
                    shifted = dict(morph)
                    shifted["start_frame"] += local_index
                    shifted["end_frame"] += local_index
                    morph_animations.append(shifted)
                for source_block in marker.get("blocks", []):
                    block = dict(source_block)
                    block["animation"] = str(marker.get("id", "animation"))
                    block["start_frame"] = local_index + int(
                        source_block.get("start_frame", 0)
                    )
                    block["end_frame"] = local_index + int(
                        source_block.get("end_frame", 0)
                    )
                    block["start"] = block["start_frame"] / args.fps
                    block["end"] = block["end_frame"] / args.fps
                    blocks.append(block)
                    keyframes.update((block["start_frame"], block["end_frame"]))

            for source_block in marker.get("blocks", []):
                if source_block.get("cut") and marker_frame == int(
                    source_block.get("end_frame", -1)
                ):
                    cuts.append(
                        {
                            "frame": local_index,
                            "time": local_index / args.fps,
                            "loop": bool(source_block.get("loop", False)),
                        }
                    )
                    keyframes.add(local_index)
            if marker_frame == int(marker.get("frames", 1)) - 1 and (
                not cuts or cuts[-1]["frame"] != local_index
            ):
                cuts.append(
                    {
                        "frame": local_index,
                        "time": local_index / args.fps,
                        "loop": False,
                    }
                )
                keyframes.add(local_index)

        final_frame = max(0, len(frames) - 1)
        if not cuts or cuts[-1]["frame"] != final_frame:
            cuts.append(
                {
                    "frame": final_frame,
                    "time": final_frame / args.fps,
                    "loop": False,
                }
            )
            keyframes.add(final_frame)

        manifest["scenes"].append(
            {
                "id": scene_id,
                "index": scene_position - 1,
                "name": f"Slide {scene_position}",
                "source": os.path.basename(args.input),
                "autoplay": False,
                "fps": args.fps,
                "duration": final_frame / args.fps,
                "frameCount": len(frames),
                "frames": frames,
                "blocks": blocks,
                "cuts": cuts,
                "keyframes": sorted(keyframes),
                "morphAnimations": morph_animations,
            }
        )

    for source_path in source_paths:
        source_path.unlink()
    log(f"Discovered {len(groups)} Touying slide(s)")
    return validate_manifest(manifest)


def compile_project(
    args,
    output_directory,
    selected_ids=None,
    log=None,
    extension="svg",
    previous_scenes=None,
):
    if extension not in {"svg", "png"}:
        raise ValueError("Unsupported frame format")
    """Compile slide definitions from one Typst document to SVG frames."""
    log = log or (lambda message: None)
    assert_installed("typst")
    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    manifest = new_manifest(args)

    query_started = time.perf_counter()
    query = run_typst(
        args,
        [
            "typst",
            "query",
            args.input,
            "--input",
            f"fps={args.fps}",
            "--input",
            f"glissade-force-fps={args.fps}",
            "--input",
            "query=1",
            "metadata",
            "--field",
            "value",
        ],
        capture_output=True,
    )
    metadata = [item for item in json.loads(query.stdout) if isinstance(item, dict)]
    timelines = [
        item["glissade_timeline"] for item in metadata if "glissade_timeline" in item
    ]
    slide_variables = _extract_slide_variables(metadata)
    slide_morph_specs = _extract_slide_morph_specs(metadata)
    if not timelines and any(
        item.get("kind") in ("touying-new-slide", "touying-new-subslide")
        for item in metadata
    ):
        return _compile_touying_project(
            args,
            output_directory,
            metadata,
            manifest,
            slide_variables=slide_variables,
            slide_morph_specs=slide_morph_specs,
            log=log,
            extension=extension,
        )
    log(
        f"Discovered {len(timelines)} slide(s) in {time.perf_counter() - query_started:.2f}s"
    )
    slide_ids = [str(timeline["id"]) for timeline in timelines]
    duplicate_ids = sorted(
        {slide_id for slide_id in slide_ids if slide_ids.count(slide_id) > 1}
    )
    if duplicate_ids:
        quoted = ", ".join(repr(slide_id) for slide_id in duplicate_ids)
        raise ValueError(
            f"Duplicate slide id: {quoted}. Every #slide id must be unique."
        )

    for position, timeline in enumerate(timelines):
        slide_id = str(timeline["id"])
        index = int(timeline.get("index", position + 1))
        prefix = f"slide-{index:03d}-{re.sub(r'[^a-zA-Z0-9_-]', '-', slide_id)}"
        output_pattern = str(output_directory / f"{prefix}-frame-{{0p}}.{extension}")
        should_compile = (
            selected_ids is None
            or slide_id in selected_ids
            or not any(output_directory.glob(f"{prefix}-frame-*.{extension}"))
        )
        if should_compile:
            compile_started = time.perf_counter()
            log(
                f"Compiling slide {index}/{len(timelines)} {slide_id!r} at {args.fps} FPS"
            )
            for old_frame in output_directory.glob(f"{prefix}-frame-*.{extension}"):
                old_frame.unlink()
            run_typst(
                args,
                [
                    "typst",
                    "compile",
                    args.input,
                    output_pattern,
                    "--input",
                    f"fps={args.fps}",
                    "--input",
                    f"glissade-force-fps={args.fps}",
                    "--input",
                    f"glissade-slide={slide_id}",
                    "--input",
                    f"glissade-slide-index={index}",
                    "--input",
                    "glissade-frozen-values="
                    + json.dumps(timeline.get("frozen_values", [])),
                    *(["--ppi", str(args.ppi)] if extension == "png" else []),
                ],
            )
            log(
                f"Compiled slide {slide_id!r} in {time.perf_counter() - compile_started:.2f}s"
            )

        paths = sorted(
            output_directory.glob(f"{prefix}-frame-*.{extension}"), key=frame_number
        )

        expected_frames = int(timeline.get("frames", len(paths)))
        if should_compile and len(paths) > expected_frames:
            extra_paths = paths[:-expected_frames]
            paths = paths[-expected_frames:]
            for extra_path in extra_paths:
                extra_path.unlink()
        if should_compile and len(paths) != expected_frames:
            raise RuntimeError(
                f"Slide {slide_id!r} produced {len(paths)} frames; expected {expected_frames}"
            )
        if should_compile and extension == "svg":
            for frame_index, frame_path in enumerate(paths):
                _tag_svg_frame(
                    frame_path,
                    variables=slide_variables.get(slide_id, {}),
                    blocks=timeline.get("blocks", []),
                    frame_index=frame_index,
                    morph_specs=slide_morph_specs.get(slide_id, []),
                    log=log,
                )
        frames = [f"/frames/{path.name}?v={manifest['version']}" for path in paths]
        if not should_compile and previous_scenes and slide_id in previous_scenes:
            scene = copy.deepcopy(previous_scenes[slide_id])
            scene.update(frames=frames, index=index - 1)
            manifest["scenes"].append(scene)
            continue
        blocks = timeline.get("blocks", [])
        cuts = []
        for block in blocks:
            if block.get("cut"):
                cuts.append(
                    {
                        "frame": min(block["end_frame"], max(0, len(frames) - 1)),
                        "time": block["end"],
                        "loop": block.get("loop", False),
                    }
                )

        # Several instantaneous cuts can share a boundary. Keep one presenter
        # stop at that frame, using the final operation's loop preference.
        cuts = list({cut["frame"]: cut for cut in cuts}.values())
        manifest["scenes"].append(
            {
                "id": slide_id,
                "index": index - 1,
                "name": timeline.get("title") or slide_id,
                "source": os.path.basename(args.input),
                "autoplay": bool(timeline.get("autoplay", False)),
                "fps": timeline.get("fps", args.fps),
                "duration": timeline.get("duration", 0),
                "frameCount": len(frames),
                "frames": frames,
                "blocks": blocks,
                "cuts": cuts,
                "keyframes": _scene_keyframes(
                    blocks,
                    len(frames),
                ),
                "morphAnimations": _morph_animations(
                    slide_morph_specs.get(slide_id, []),
                    slide_variables.get(slide_id, {}),
                    blocks,
                    timeline.get("fps", args.fps),
                ),
            }
        )
    return validate_manifest(manifest)


def compile_svg_project(
    args, output_directory, selected_ids=None, log=None, previous_scenes=None
):
    return compile_project(
        args,
        output_directory,
        selected_ids,
        log,
        extension="svg",
        previous_scenes=previous_scenes,
    )
