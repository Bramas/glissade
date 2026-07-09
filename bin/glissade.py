# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pypdf"
# ]
# ///

from string import Template
import argparse
import base64
import gzip
import importlib.util
import json
import math
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

_SVG_TAGGER_SPEC = importlib.util.spec_from_file_location("svg_tagger", Path(__file__).parent / "svg_tagger.py")
if _SVG_TAGGER_SPEC and _SVG_TAGGER_SPEC.loader:
    svg_tagger = importlib.util.module_from_spec(_SVG_TAGGER_SPEC)
    _SVG_TAGGER_SPEC.loader.exec_module(svg_tagger)
else:
    raise ImportError("Could not load svg_tagger.py")

def assert_installed(program: str):
    if shutil.which(program) is None:
        raise RuntimeError(f"Failed to run {program}. Is {program} installed?")

def create_parser():
    parser = argparse.ArgumentParser(
        description="Create and export animated Typst presentations with Glissade",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  glissade.py presentation.typ slides
  glissade.py animation.typ video --cut none --fps 24 --ppi 150
  glissade.py --root ./project presentation.typ html --fps 24
  glissade.py --root ./project presentation.typ dev
"""
    )
    parser.add_argument(
        "--root",
        help="Typst root directory"
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="timeout (default: 30s)"
    )

    parser.add_argument(
        "input",
        help="input Typst file",
    )
    
    # Create subparsers for different commands
    subparsers = parser.add_subparsers(
        dest="output format",
        help="output format",
        metavar="output",
        required=True
    )

    # create parent parser
    parent_parser = argparse.ArgumentParser(add_help=False)
    
    # =====================
    # slides subcommand
    # =====================
    slides_parser = subparsers.add_parser(
        "slides",
        help="pdf output",
        parents=[parent_parser]
    )

    # create subparent parser
    subparent_parser = argparse.ArgumentParser(add_help=False)

    subparent_parser.add_argument(
        "--cut",
        choices=["all", "none", "scene"],
        default="all",
        help="cuts to consider (default: all)"
    )
    
    subparent_parser.add_argument(
        "--fps",
        type=int,
        default=30,
        help="frames per second (default: 30)"
    )
    
    subparent_parser.add_argument(
        "--ppi",
        type=int,
        default=144,
        help="pixels per inch (default: 144)"
    )
    
    slides_parser.set_defaults(func=handle_slides)
    
    # =====================
    # video subcommand
    # =====================
    video_parser = subparsers.add_parser(
        "video",
        help="video output",
        parents=[subparent_parser]
    )
    
    video_parser.add_argument(
        "--format",
        type=str,
        default="mp4",
        help="ouput video format (default: mp4)"
    )
    
    video_parser.set_defaults(func=handle_video)
    
    # =====================
    # revealjs subcommand
    # =====================
    revealjs_parser = subparsers.add_parser(
        "revealjs",
        help="reveal.js output",
        parents=[subparent_parser]
    )

    revealjs_parser.add_argument(
        "--title",
        type=str,
        help="title of the presentation"
    )

    revealjs_parser.add_argument(
        "--progress",
        action=argparse.BooleanOptionalAction,
        default =  False,
        help="display a progress bar"
    )

    revealjs_parser.add_argument(
        "--template",
        type=str,
        default="bin/revealjs.html",
        help="revealjs template"
    )

    revealjs_parser.set_defaults(func=handle_revealjs)

    # =====================
    # html subcommand
    # =====================
    html_parser = subparsers.add_parser(
        "html",
        help="dependency-free HTML presentation",
        parents=[subparent_parser]
    )

    html_parser.add_argument(
        "--title",
        type=str,
        help="title of the presentation"
    )

    html_parser.add_argument(
        "--progress",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="display a progress bar"
    )

    html_parser.add_argument(
        "--embed-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="embed SVG frames as base64 in HTML (default: True, set to False for external files)"
    )

    html_parser.add_argument(
        "--minify-svg",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="remove insignificant whitespace from exported SVG frames (default: enabled)"
    )

    html_parser.add_argument(
        "--compress-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="gzip SVG frames and decompress them lazily in the browser (default: enabled)"
    )

    html_parser.add_argument(
        "--optimize-frames",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="store unchanged SVG subtrees once and encode smaller frame deltas when possible (default: enabled)"
    )

    html_parser.add_argument(
        "--template",
        type=str,
        default=str(Path(__file__).parent / "assets" / "present.min.html"),
        help="HTML presentation template"
    )

    html_parser.set_defaults(func=handle_html)

    # =====================
    # dev subcommand
    # =====================
    dev_parser = subparsers.add_parser(
        "dev",
        help="live SVG presentation editor",
        parents=[subparent_parser]
    )

    dev_parser.add_argument("--host", default="127.0.0.1", help="server host")
    dev_parser.add_argument("--port", type=int, default=8765, help="server port")
    dev_parser.add_argument(
        "--template",
        type=str,
        default=str(Path(__file__).parent / "assets" / "editor.min.html"),
        help="editor HTML template"
    )
    dev_parser.set_defaults(func=handle_dev)
    
    return parser

def handle_slides(args):
    """Handle slides subcommand"""
    from pypdf import PdfWriter
    
    assert_installed("typst")
    
    scenes = []

    dir_path = os.path.dirname(args.input)
    root_path, ext = os.path.splitext(args.input)

    scenes.append(os.path.basename(args.input))

    total_scenes = len(scenes)

    try:
        with tempfile.TemporaryDirectory() as tmpdir:

            merger = PdfWriter()

            for index, input in enumerate(scenes):
                output = os.path.join(tmpdir, f"output{index}.pdf")
                cmd = [
                    "typst",
                    "compile",
                    os.path.join(dir_path, input),
                    "--input", "fps=0",
                    "--input", f"scene={index+1}",
                    "--input", f"total_scenes={total_scenes}",
                    output
                ]
                if args.root is not None:
                    cmd += ["--root", os.path.abspath(args.root)]
    
                subprocess.run(cmd, timeout = args.timeout)

                merger.append(output)
            merger.write(f"{root_path}.pdf")
        
    except subprocess.TimeoutExpired:
        print(f"Timeout after {args.timeout} seconds.\nhint: timeout can be increased using the --timeout option.")
        return 124
        
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1
    
    return 0

def handle_video(args):
    """Handle video subcommand"""

    assert_installed("typst")
    assert_installed("ffmpeg")

    scenes = []

    dir_path = os.path.dirname(args.input)
    root_path, ext = os.path.splitext(args.input)
    output = f"{root_path}.{args.format}"

    scenes.append(os.path.basename(args.input))

    total_scenes = len(scenes)

    try:    
        with tempfile.TemporaryDirectory() as tmpdir:

            for index, input in enumerate(scenes):
                cmd1 = [
                    "typst",
                    "compile",
                    "--input", f"fps={args.fps}",            
                    "--input", f"scene={index+1}",
                    "--input", f"total_scenes={total_scenes}",
                    os.path.join(dir_path, input),
                    os.path.join(tmpdir, f"output{index}_"+"{0p}.png"),
                    "--ppi", f"{args.ppi}"
                ]
                if args.root is not None:
                    cmd1 += ["--root", os.path.abspath(args.root)] 

                subprocess.run(cmd1, timeout = args.timeout, check = True)

            if args.cut == "none":
                cmd2 = [
                    "ffmpeg",
                    "-y",
                    "-loglevel", "error",
                    "-r", f"{args.fps}",
                    "-pattern_type", "glob", 
                    "-i", os.path.join(tmpdir, "output*.png"),
                    "-r", f"{args.fps}",
                    output
                ]
                subprocess.run(cmd2, timeout = args.timeout)

            elif args.cut == "scene":
                for index, input in enumerate(scenes):
                    if total_scenes != 1:
                        output = f"{root_path}{index+1}.{args.format}"
                    cmd2 = [
                        "ffmpeg",
                        "-y",
                        "-loglevel", "error",
                        "-r", f"{args.fps}",
                        "-pattern_type", "glob", 
                        "-i", os.path.join(tmpdir, f"output{index}_*.png"),
                        "-r", f"{args.fps}",
                        output
                    ]
                    subprocess.run(cmd2, timeout = args.timeout)

            elif args.cut == "all":
                for index, input in enumerate(scenes):
                    cmd2 = [
                        "typst",
                        "query",                        
                        os.path.join(dir_path, input),
                        "--input", f"fps={args.fps}",
                        "--input", f"scene={index+1}",
                        "--input", f"total_scenes={total_scenes}",
                        "--input", "query=1",
                        "metadata", 
                        "--field", "value"
                    ]
                    if args.root is not None:
                        cmd2 += ["--root", os.path.abspath(args.root)] 

                    result = subprocess.run(cmd2, timeout = args.timeout, capture_output=True, text=True, check = True)
                    data = json.loads(result.stdout)
                    data = [d["glissade"] for d in data if "glissade" in d]
                    
                    for item in data:
                        output = f"{root_path}{index+1}_{item['segment']}.{args.format}"
                        if total_scenes == 1:
                            output = f"{root_path}{item['segment']}.{args.format}"
                            if len(data) == 1:
                                output = f"{root_path}.{args.format}"
                        cmd = [
                            "ffmpeg",
                            "-y",                        
                            "-loglevel", "error",
                            "-r", str(item['fps']),
                            "-pattern_type", "glob",
                            "-i", os.path.join(tmpdir, f"output{index}_*.png"),
                            "-vf", f"select='gte(n,{item['from']})'",
                            "-frames:v", str(item['frames']),
                            "-r", str(item['fps']),
                            output
                        ]
                        
                        result = subprocess.run(cmd, timeout = args.timeout, check = True)
                        
    except subprocess.TimeoutExpired:
        print(f"Timeout after {args.timeout} seconds.\nhint: timeout can be increased using the --timeout option.")
        return 124

    except subprocess.CalledProcessError:
        print("The above exception was raised during conversion.")
        
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1

    return 0

def read_scenes(input_path):
    """Return the scene directory and filenames represented by an input."""
    directory = os.path.dirname(input_path)
    _, extension = os.path.splitext(input_path)
    return directory, [os.path.basename(input_path)]

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
    match = re.search(r"frame-(\d+)\.svg$", str(path))
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
        return lambda t: t ** 2
    if name == "cubic":
        return lambda t: t ** 3
    if name == "quart":
        return lambda t: t ** 4
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
        "children", "child", "body", "base", "num", "denom",
        "t", "b", "tl", "tr", "bl", "br", "sub", "sup",
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
        if start_frame <= frame_index <= end_frame:
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
                start_frame = int(block["start_frame"]) + int(round(fps * hold))
                end_frame = start_frame + int(round(fps * duration))
                animations.append({
                    "id": str(morph_id).removeprefix(svg_tagger.MORPH_ID_PREFIX),
                    "state": str(state),
                    "effect": str(effect),
                    "start_frame": start_frame,
                    "end_frame": end_frame,
                })
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
            variables[pending_slide_id] = item["glissade_animation_scope"].get("variables", {})
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
            morph_specs[pending_slide_id].append({
                "id": None if morph_id is None else str(morph_id),
                "state": item.get("state"),
                "effect": None if morph_effect is None else str(morph_effect),
            })
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
            parts_for_frame.append({
                "id": f"{svg_tagger.PART_ID_PREFIX}{_sanitize_formula_part_token(name)}-{_sanitize_formula_part_token(key)}",
                "state": str(name),
                "key": str(key),
            })
    return _dedupe_formula_parts(parts_for_frame)


def _scene_keyframes(blocks, frame_count):
    last_frame = max(0, int(frame_count) - 1)
    anchors = {0, last_frame}
    for block in blocks:
        anchors.add(max(0, min(last_frame, int(block.get("start_frame", 0)))))
        anchors.add(max(0, min(last_frame, int(block.get("end_frame", last_frame)))))
    return sorted(anchors)


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
    for index, (base_child, target_child) in enumerate(zip(base_children, target_children)):
        patches.extend(_svg_delta_patches(base_child, target_child, path + [index]))

    patch_size = len(json.dumps(patches, separators=(",", ":")))
    replacement_size = len(json.dumps([_svg_replace_patch(path, target)], separators=(",", ":")))
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
            optimized.append({
                "kind": "svg-delta-v1",
                "base": base_index,
                "patches": [],
            })
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


def _read_morph_runtime_source():
    runtime_dir = Path(__file__).parent.parent / "web" / "runtime"
    parts = [
        runtime_dir / "core.js",
        runtime_dir / "path_alignment.js",
        runtime_dir / "geometry.js",
        runtime_dir / "renderer.js",
    ]
    return "\n".join(path.read_text(encoding="utf-8") for path in parts)

def compile_svg_project(args, output_directory, selected_ids=None, log=None):
    """Compile slide definitions from one Typst document to SVG frames."""
    log = log or (lambda message: None)
    assert_installed("typst")
    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": str(time.time_ns()),
        "title": Path(args.input).stem,
        "fps": args.fps,
        "scenes": [],
    }

    query_started = time.perf_counter()
    query = run_typst(
        args,
        [
            "typst", "query", args.input,
            "--input", f"fps={args.fps}",
            "--input", "query=1",
            "metadata", "--field", "value",
        ],
        capture_output=True,
    )
    metadata = json.loads(query.stdout)
    slide_variables = _extract_slide_variables(metadata)
    slide_morph_specs = _extract_slide_morph_specs(metadata)
    timelines = [item["glissade_timeline"] for item in metadata if "glissade_timeline" in item]
    log(f"Discovered {len(timelines)} slide(s) in {time.perf_counter() - query_started:.2f}s")
    slide_ids = [str(timeline["id"]) for timeline in timelines]
    duplicate_ids = sorted({slide_id for slide_id in slide_ids if slide_ids.count(slide_id) > 1})
    if duplicate_ids:
        quoted = ", ".join(repr(slide_id) for slide_id in duplicate_ids)
        raise ValueError(f"Duplicate slide id: {quoted}. Every #slide id must be unique.")

    for position, timeline in enumerate(timelines):
        slide_id = str(timeline["id"])
        index = int(timeline.get("index", position + 1))
        prefix = f"slide-{index:03d}-{re.sub(r'[^a-zA-Z0-9_-]', '-', slide_id)}"
        output_pattern = str(output_directory / f"{prefix}-frame-{{0p}}.svg")
        should_compile = selected_ids is None or slide_id in selected_ids
        if should_compile:
            compile_started = time.perf_counter()
            log(f"Compiling slide {index}/{len(timelines)} {slide_id!r} at {args.fps} FPS")
            for old_frame in output_directory.glob(f"{prefix}-frame-*.svg"):
                old_frame.unlink()
            run_typst(args, [
                "typst", "compile", args.input, output_pattern,
                "--input", f"fps={args.fps}",
                "--input", f"glissade-slide={slide_id}",
                "--input", f"glissade-slide-index={index}",
                "--input", "glissade-frozen-values=" + json.dumps(timeline.get("frozen_values", [])),
            ])
            log(
                f"Compiled slide {slide_id!r} in {time.perf_counter() - compile_started:.2f}s"
            )

        paths = sorted(output_directory.glob(f"{prefix}-frame-*.svg"), key=frame_number)

        # Tag SVG groups with formula part IDs.
        for frame_index, frame_path in enumerate(paths):
            try:
                content = frame_path.read_text(encoding='utf-8')
                part_specs = _frame_formula_parts(
                    slide_variables.get(slide_id, {}),
                    timeline.get("blocks", []),
                    frame_index,
                )
                morph_specs = []
                frame_block, frame_time = _frame_block_and_time(
                    timeline.get("blocks", []), frame_index
                )
                for item in slide_morph_specs.get(slide_id, []):
                    morph_id = item.get("id")
                    if morph_id is None:
                        continue
                    state = item.get("state")
                    effect = item.get("effect")
                    if state is not None:
                        effect = _transition_effect_for_frame(
                            slide_variables.get(slide_id, {}).get(str(state), {}),
                            frame_block,
                            frame_time,
                        )
                    morph_specs.append({
                        "id": morph_id if morph_id.startswith(svg_tagger.MORPH_ID_PREFIX)
                        else f"{svg_tagger.MORPH_ID_PREFIX}{_sanitize_formula_part_token(morph_id)}",
                        "name": morph_id.removeprefix(svg_tagger.MORPH_ID_PREFIX) if morph_id.startswith(svg_tagger.MORPH_ID_PREFIX) else str(morph_id),
                        "effect": effect,
                    })
                if morph_specs:
                    expanded_parts = []
                    for morph in morph_specs:
                        morph_suffix = morph["id"].removeprefix(svg_tagger.MORPH_ID_PREFIX)
                        for part in part_specs:
                            expanded_parts.append({
                                "id": f"{svg_tagger.PART_ID_PREFIX}{morph_suffix}-{part['id'].removeprefix(svg_tagger.PART_ID_PREFIX)}",
                                "state": part["state"],
                                "key": part["key"],
                                "morph": morph["name"],
                            })
                    part_specs = expanded_parts
                tagged = svg_tagger.tag_svg_groups(content, part_specs=part_specs, morph_specs=morph_specs)
                frame_path.write_text(tagged, encoding='utf-8')
            except Exception as e:
                log(f"Warning: Could not tag {frame_path.name}: {e}")
        
        expected_frames = int(timeline.get("frames", len(paths)))
        if should_compile and len(paths) > expected_frames:
            extra_paths = paths[:-expected_frames]
            paths = paths[-expected_frames:]
            for extra_path in extra_paths:
                extra_path.unlink()
        frames = [f"/frames/{path.name}?v={manifest['version']}" for path in paths]
        blocks = timeline.get("blocks", [])
        cuts = []
        for block in blocks:
            if block.get("cut"):
                cuts.append({
                    "frame": min(block["end_frame"], max(0, len(frames) - 1)),
                    "time": block["end"],
                    "loop": block.get("loop", False),
                })

        manifest["scenes"].append({
            "id": slide_id,
            "index": index - 1,
            "name": timeline.get("title") or slide_id,
            "source": os.path.basename(args.input),
            "autoplay": bool(timeline.get("autoplay", False)),
            "fps": timeline.get("fps", args.fps),
            "duration": timeline.get("duration", 0),
            "frameCount": len(frames) if should_compile else timeline.get("frames", 0),
            "frames": frames,
            "blocks": blocks,
            "cuts": cuts,
            "keyframes": _scene_keyframes(
                blocks,
                len(frames) if should_compile else timeline.get("frames", 0),
            ),
            "morphAnimations": _morph_animations(
                slide_morph_specs.get(slide_id, []),
                slide_variables.get(slide_id, {}),
                blocks,
                timeline.get("fps", args.fps),
            ),
        })
    return manifest

def render_editor_template(template_path, title, manifest_source, live_reload):
    with open(template_path, "r") as template_file:
        template_source = template_file.read()
    runtime_source = _read_morph_runtime_source() if "${morph_runtime_source}" in template_source else ""
    template = Template(template_source)
    return template.substitute({
        "title": title,
        "manifest_source": manifest_source,
        "live_reload": "true" if live_reload else "false",
        "morph_runtime_source": runtime_source,
    })

def handle_html(args):
    """Generate a standalone, dependency-free SVG presentation."""
    root_path, _ = os.path.splitext(args.input)
    output_dir = Path(root_path).parent
    frames_dir = output_dir / "frames"
    
    try:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest = compile_svg_project(args, temporary_directory)

            if args.minify_svg:
                for frame_path in Path(temporary_directory).glob("slide-*-frame-*.svg"):
                    frame_path.write_text(
                        svg_tagger.minify_svg(frame_path.read_text(encoding="utf-8")),
                        encoding="utf-8",
                    )

            if args.optimize_frames:
                for scene in manifest["scenes"]:
                    _optimize_scene_frames(scene, temporary_directory)
            
            if args.embed_frames:
                # Embed frames as base64
                for scene in manifest["scenes"]:
                    embedded_frames = []
                    for frame_url in scene["frames"]:
                        if _is_frame_delta(frame_url):
                            embedded_frames.append(frame_url)
                            continue
                        frame_name = _source_frame_name(frame_url)
                        frame_path = Path(temporary_directory) / frame_name
                        frame_bytes = frame_path.read_bytes()
                        if args.compress_frames:
                            frame_bytes = gzip.compress(frame_bytes, compresslevel=9, mtime=0)
                            media_type = "application/gzip"
                        else:
                            media_type = "image/svg+xml"
                        encoded = base64.b64encode(frame_bytes).decode("ascii")
                        embedded_frames.append(f"data:{media_type};base64," + encoded)
                    scene["frames"] = embedded_frames
            else:
                # Copy SVG files to frames directory
                frames_dir.mkdir(parents=True, exist_ok=True)
                for stale_frame in frames_dir.glob("slide-*-frame-*.svg"):
                    stale_frame.unlink()
                for stale_frame in frames_dir.glob("slide-*-frame-*.svg.gz"):
                    stale_frame.unlink()
                
                for scene in manifest["scenes"]:
                    external_frames = []
                    for frame_url in scene["frames"]:
                        if _is_frame_delta(frame_url):
                            external_frames.append(frame_url)
                            continue
                        frame_name = _source_frame_name(frame_url)
                        frame_path = Path(temporary_directory) / frame_name
                        if args.compress_frames:
                            frame_name += ".gz"
                        dest_path = frames_dir / frame_name
                        # Copy SVG file
                        frame_bytes = frame_path.read_bytes()
                        if args.compress_frames:
                            frame_bytes = gzip.compress(frame_bytes, compresslevel=9, mtime=0)
                        dest_path.write_bytes(frame_bytes)
                        # Use relative path from HTML file location
                        external_frames.append(f"frames/{frame_name}")
                    scene["frames"] = external_frames
            
            manifest_source = "Promise.resolve(" + json.dumps(manifest, separators=(",", ":")) + ")"
            result = render_editor_template(
                args.template,
                Path(args.input).stem,
                manifest_source,
                False,
            )
            output_html = f"{root_path}.html"
            with open(output_html, "w") as output_file:
                output_file.write(result)
            
            if not args.embed_frames:
                print(f"HTML: {output_html}")
                print(f"SVGs: {frames_dir}/")
    except subprocess.TimeoutExpired:
        print(f"Timeout after {args.timeout} seconds.\nhint: timeout can be increased using the --timeout option.")
        return 124
    except subprocess.CalledProcessError:
        print("The above exception was raised during SVG compilation.")
        return 1
    except Exception as error:
        print(f"Unexpected error: {error}")
        return 1
    return 0

class LiveBuildState:
    def __init__(self, args):
        self.args = args
        self.condition = threading.Condition()
        self.generation = 0
        self.manifest = None
        self.build_directory = None
        self.error = None
        self.stopped = False
        self.selected_id = None
        self.dirty_ids = set()
        self.build_lock = threading.Lock()

    def log(self, message):
        timestamp = time.strftime("%H:%M:%S")
        print(f"[{timestamp}] Glissade: {message}", flush=True)

    def build(self):
        with self.build_lock:
            build_directory = self.build_directory or Path(tempfile.mkdtemp(prefix="glissade-preview-"))
            try:
                selected_ids = {self.selected_id} if self.build_directory and self.selected_id else None
                build_started = time.perf_counter()
                manifest = compile_svg_project(
                    self.args,
                    build_directory,
                    selected_ids=selected_ids,
                    log=self.log,
                )
            except Exception as error:
                message = getattr(error, "stderr", None) or str(error)
                self.log(f"Build failed: {message.strip()}")
                with self.condition:
                    self.error = message
                    self.generation += 1
                    self.condition.notify_all()
                return False
            with self.condition:
                self.manifest = manifest
                self.build_directory = Path(build_directory)
                if self.selected_id is None and manifest["scenes"]:
                    self.selected_id = manifest["scenes"][0]["id"]
                if selected_ids is not None:
                    self.dirty_ids.update(scene["id"] for scene in manifest["scenes"])
                    self.dirty_ids.discard(self.selected_id)
                else:
                    self.dirty_ids.clear()
                self.error = None
                self.generation += 1
                self.condition.notify_all()
            self.log(f"Build ready in {time.perf_counter() - build_started:.2f}s")
            return True

    def invalidate_all(self):
        with self.condition:
            if self.manifest:
                self.dirty_ids.update(scene["id"] for scene in self.manifest["scenes"])

    def select(self, slide_id):
        with self.condition:
            self.selected_id = slide_id
            return slide_id in self.dirty_ids

def watched_files(args):
    root = Path(args.root or os.path.dirname(args.input) or ".").resolve()
    paths = list(root.rglob("*.typ")) + list(root.rglob("*.toml"))
    return {
        str(path): path.stat().st_mtime_ns
        for path in paths
        if ".git" not in path.parts and path.is_file()
    }

def watch_project(state):
    previous = watched_files(state.args)
    while not state.stopped:
        time.sleep(0.35)
        try:
            current = watched_files(state.args)
        except OSError:
            continue
        if current != previous:
            previous = current
            time.sleep(0.15)
            state.log(f"Source change detected; rebuilding {state.selected_id!r}")
            state.invalidate_all()
            state.build()

class QuietThreadingHTTPServer(ThreadingHTTPServer):
    """Ignore routine browser disconnects without hiding real server errors."""

    def handle_error(self, request, client_address):
        error = sys.exc_info()[1]
        if isinstance(error, (BrokenPipeError, ConnectionResetError)):
            return
        super().handle_error(request, client_address)

def make_editor_handler(state, editor_html):
    class EditorHandler(BaseHTTPRequestHandler):
        def log_message(self, format, *values):
            return

        def send_bytes(self, content, content_type, status=HTTPStatus.OK):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                self.wfile.write(content)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                self.send_bytes(editor_html, "text/html; charset=utf-8")
            elif path == "/manifest.json":
                with state.condition:
                    manifest = state.manifest
                if manifest is None:
                    self.send_bytes(b'{"error":"Preview is not ready"}', "application/json", HTTPStatus.SERVICE_UNAVAILABLE)
                else:
                    self.send_bytes(json.dumps(manifest).encode(), "application/json")
            elif path.startswith("/frames/"):
                filename = Path(path).name
                with state.condition:
                    build_directory = state.build_directory
                frame_path = build_directory / filename if build_directory else None
                if frame_path is None or not frame_path.is_file():
                    self.send_bytes(b"Frame not found", "text/plain", HTTPStatus.NOT_FOUND)
                else:
                    self.send_bytes(frame_path.read_bytes(), "image/svg+xml")
            elif path == "/events":
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                with state.condition:
                    generation = state.generation
                try:
                    while not state.stopped:
                        with state.condition:
                            state.condition.wait_for(
                                lambda: state.generation != generation or state.stopped,
                                timeout=15,
                            )
                            if state.stopped:
                                break
                            if state.generation == generation:
                                self.wfile.write(b": keep-alive\n\n")
                            else:
                                generation = state.generation
                                if state.error:
                                    message = state.error.replace("\n", " ")
                                    self.wfile.write(("event: build-error\ndata: " + message + "\n\n").encode())
                                else:
                                    self.wfile.write(b"event: reload\ndata: ready\n\n")
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
            elif path == "/select":
                query = urlparse(self.path).query
                selected = next(
                    (part.removeprefix("id=") for part in query.split("&") if part.startswith("id=")),
                    None,
                )
                if selected:
                    from urllib.parse import unquote
                    should_rebuild = state.select(unquote(selected))
                    if should_rebuild:
                        state.log(f"Selected stale slide {state.selected_id!r}; rebuilding on demand")
                        threading.Thread(target=state.build, daemon=True).start()
                self.send_bytes(b"ok", "text/plain")
            else:
                self.send_bytes(b"Not found", "text/plain", HTTPStatus.NOT_FOUND)
    return EditorHandler

def handle_dev(args):
    """Run the live SVG editor and rebuild when Typst sources change."""
    state = LiveBuildState(args)
    if not state.build():
        print(f"Initial build failed: {state.error}")
        return 1
    manifest_source = 'fetch("/manifest.json?version=" + Date.now()).then(response => {' \
        ' if (!response.ok) throw new Error("Manifest unavailable"); return response.json(); })'
    editor_html = render_editor_template(
        args.template,
        Path(args.input).stem,
        manifest_source,
        True,
    ).encode()
    server = QuietThreadingHTTPServer((args.host, args.port), make_editor_handler(state, editor_html))
    watcher = threading.Thread(target=watch_project, args=(state,), daemon=True)
    watcher.start()
    print(f"Glissade editor running at http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        state.stopped = True
        with state.condition:
            state.condition.notify_all()
        server.server_close()
    return 0

def handle_revealjs(args):
    """Handle revealjs subcommand"""
    
    assert_installed("typst")
    assert_installed("ffmpeg")

    scenes = []

    dir_path = os.path.dirname(args.input)
    root_path, ext = os.path.splitext(args.input)
    prespath = f"{root_path}.html"
    title = args.title
    if title is None:
        title = os.path.splitext(os.path.basename(args.input))[0]

    scenes.append(os.path.basename(args.input))

    total_scenes = len(scenes)
   
    try:    
        with tempfile.TemporaryDirectory() as tmpdir:
            for index, input in enumerate(scenes):
                cmd1 = [
                    "typst",
                    "compile",
                    "--input", f"fps={args.fps}",            
                    "--input", f"scene={index+1}",
                    "--input", f"total_scenes={total_scenes}",
                    os.path.join(dir_path, input),
                    os.path.join(tmpdir, f"output{index}_"+"{0p}.png"),
                    "--ppi", f"{args.ppi}"
                ]
                if args.root is not None:
                    cmd1 += ["--root", os.path.abspath(args.root)] 

                subprocess.run(cmd1, timeout = args.timeout, check = True)

            if args.cut == "none":
                output = os.path.join(tmpdir, "segment.mp4")
                cmd2 = [
                    "ffmpeg",
                    "-y",
                    "-loglevel", "error",
                    "-r", f"{args.fps}",
                    "-pattern_type", "glob", 
                    "-i", os.path.join(tmpdir, "output*.png"),
                    "-r", f"{args.fps}",
                    output
                ]

                subprocess.run(cmd2, timeout = args.timeout)

                content = f"<section data-background-video=\"{video_to_data_uri(output)[0]}\" data-background-size=\"contain\"></section>"
                navigation = "default"

            elif args.cut == "scene":

                content = ""
                navigation = "default"
                
                for index, _ in enumerate(scenes):
                    output = os.path.join(tmpdir, f"segment{index}.mp4")
                    cmd2 = [
                        "ffmpeg",
                        "-y",
                        "-loglevel", "error",
                        "-r", f"{args.fps}",
                        "-pattern_type", "glob", 
                        "-i", os.path.join(tmpdir, f"output{index}_*.png"),
                        "-r", f"{args.fps}",
                        output
                    ]
                    subprocess.run(cmd2, timeout = args.timeout)

                    content += f"\n<section data-background-video=\"{video_to_data_uri(output)[0]}\" data-background-size=\"contain\"></section>"
                    
            elif args.cut == "all":

                content = ""
                navigation = "default"
                
                for index, input in enumerate(scenes):

                    content+="<section>\n"
                    
                    output = os.path.join(tmpdir, f"segment{index}.mp4")
                    cmd2 = [
                        "typst",
                        "query",     
                        os.path.join(dir_path, input),
                        "--input", f"fps={args.fps}",
                        "--input", "query=1",
                        "--input", f"scene={index+1}",
                        "--input", f"total_scenes={total_scenes}",
                        "metadata", 
                        "--field", "value"
                    ]
                    if args.root is not None:
                        cmd2 += ["--root", os.path.abspath(args.root)] 

                    result = subprocess.run(cmd2, timeout = args.timeout, capture_output=True, text=True, check = True)
                    data = json.loads(result.stdout)
                    data = [d["glissade"] for d in data if "glissade" in d]
                    
                    for item in data:
                        output = os.path.join(tmpdir, f"segment{item['segment']}.mp4")
                        cmd = [
                            "ffmpeg",
                            "-y",                        
                            "-loglevel", "error",
                            "-r", str(item['fps']),
                            "-pattern_type", "glob",
                            "-i", os.path.join(tmpdir, f"output{index}_*.png"),
                            "-vf", f"select='gte(n,{item['from']})'",
                            "-frames:v", str(item['frames']),
                            "-r", str(item['fps']),
                            output
                        ]
            
                        result = subprocess.run(cmd, timeout = args.timeout, check = True)
            
                        loop_attribute = "data-background-video-loop" if item["loop"] else ""
                        content += f'\n<section data-background-video="{video_to_data_uri(output)[0]}" data-background-size="contain" {loop_attribute}></section>'

                    content += "\n</section>\n"

            parameters = {"title": title,
                          "content": content,
                          "navigation": navigation,
                          "progress": "true" if args.progress else "false"}
    
            with open(args.template, 'r') as f:
                template = Template(f.read())
                result = template.substitute(parameters)
            with open(prespath, 'w') as f:
                f.write(result)
                       
    except subprocess.TimeoutExpired:
        print(f"Timeout after {args.timeout} seconds.\nhint: timeout can be increased using the --timeout option.")
        return 124

    except subprocess.CalledProcessError:
        print("The above exception was raised during conversion.")
        
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1

    return 0

def video_to_data_uri(video_path):
    """Convert video file to data URI"""
    # Get MIME type
    mime_type, _ = mimetypes.guess_type(video_path)
    if not mime_type:
        mime_type = 'video/mp4'  # Default fallback
    # Read and encode video
    with open(video_path, 'rb') as video_file:
        video_data = video_file.read()
    # Base64 encode
    base64_data = base64.b64encode(video_data).decode('utf-8')
    # Create data URI
    data_uri = f"data:{mime_type};base64,{base64_data}"
    return data_uri, len(video_data)

def main():
    parser = create_parser()
    pargs = parser.parse_args()
    return pargs.func(pargs)

if __name__ == "__main__":
    sys.exit(main())
