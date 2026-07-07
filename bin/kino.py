# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pypdf"
# ]
# ///

from string import Template
import argparse
import base64
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

def assert_installed(program: str):
    if shutil.which(program) is None:
        raise RuntimeError(f"Failed to run {program}. Is {program} installed?")

def create_parser():
    parser = argparse.ArgumentParser(
        description="Utility for creating animations",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  kino.py presentation.typ slides
  kino.py animation.typ video --cut none --fps 24 --ppi 150
  kino.py --root ./project presentation.typ html --fps 24
  kino.py --root ./project presentation.typ dev
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
        "--template",
        type=str,
        default="bin/present.html",
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
        default="bin/editor.html",
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

    if ext == ".toml":
        with open(args.input, 'rb') as f:
            data = tomllib.load(f)
            scenes = data["scenes"] 
    else:
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

    if ext == ".toml":
        with open(args.input, 'rb') as f:
            data = tomllib.load(f)
            scenes = data["scenes"] 
    else:
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
                    data = [d["kino"] for d in data if "kino" in d]
                    
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
    if extension == ".toml":
        with open(input_path, "rb") as input_file:
            return directory, tomllib.load(input_file)["scenes"]
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
    timelines = [item["kino_timeline"] for item in metadata if "kino_timeline" in item]
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
                "--input", f"kino-slide={slide_id}",
                "--input", f"kino-slide-index={index}",
                "--input", "kino-frozen-values=" + json.dumps(timeline.get("frozen_values", [])),
            ])
            log(
                f"Compiled slide {slide_id!r} in {time.perf_counter() - compile_started:.2f}s"
            )

        paths = sorted(output_directory.glob(f"{prefix}-frame-*.svg"), key=frame_number)
        
        # Tag SVG groups with formula part IDs
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("svg_tagger", Path(__file__).parent / "svg_tagger.py")
            if spec and spec.loader:
                svg_tagger = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(svg_tagger)
                for frame_path in paths:
                    try:
                        content = frame_path.read_text(encoding='utf-8')
                        tagged = svg_tagger.tag_svg_groups(content)
                        frame_path.write_text(tagged, encoding='utf-8')
                    except Exception as e:
                        log(f"Warning: Could not tag {frame_path.name}: {e}")
        except Exception as e:
            log(f"Note: SVG tagging skipped: {e}")
        
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
            "fps": timeline.get("fps", args.fps),
            "duration": timeline.get("duration", 0),
            "frameCount": len(frames) if should_compile else timeline.get("frames", 0),
            "frames": frames,
            "blocks": blocks,
            "cuts": cuts,
        })
    return manifest

def render_editor_template(template_path, title, manifest_source, live_reload):
    with open(template_path, "r") as template_file:
        template = Template(template_file.read())
    return template.substitute({
        "title": title,
        "manifest_source": manifest_source,
        "live_reload": "true" if live_reload else "false",
    })

def handle_html(args):
    """Generate a standalone, dependency-free SVG presentation."""
    root_path, _ = os.path.splitext(args.input)
    output_dir = Path(root_path).parent
    frames_dir = output_dir / "frames"
    
    try:
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest = compile_svg_project(args, temporary_directory)
            
            if args.embed_frames:
                # Embed frames as base64
                for scene in manifest["scenes"]:
                    embedded_frames = []
                    for frame_url in scene["frames"]:
                        frame_name = urlparse(frame_url).path.removeprefix("/frames/")
                        frame_path = Path(temporary_directory) / frame_name
                        encoded = base64.b64encode(frame_path.read_bytes()).decode("ascii")
                        embedded_frames.append("data:image/svg+xml;base64," + encoded)
                    scene["frames"] = embedded_frames
            else:
                # Copy SVG files to frames directory
                frames_dir.mkdir(parents=True, exist_ok=True)
                for stale_frame in frames_dir.glob("slide-*-frame-*.svg"):
                    stale_frame.unlink()
                
                for scene in manifest["scenes"]:
                    external_frames = []
                    for frame_url in scene["frames"]:
                        frame_name = urlparse(frame_url).path.removeprefix("/frames/")
                        frame_path = Path(temporary_directory) / frame_name
                        dest_path = frames_dir / frame_name
                        # Copy SVG file
                        dest_path.write_bytes(frame_path.read_bytes())
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
        print(f"[{timestamp}] Kino: {message}", flush=True)

    def build(self):
        with self.build_lock:
            build_directory = self.build_directory or Path(tempfile.mkdtemp(prefix="kino-preview-"))
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
    print(f"Kino editor running at http://{args.host}:{args.port}")
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

    if ext == ".toml":
        with open(args.input, 'rb') as f:
            data = tomllib.load(f)
            scenes = data["scenes"] 
    else:
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
                    data = [d["kino"] for d in data if "kino" in d]
                    
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
