"""Local preview server and transactional live builds."""

import json
import os
import shutil
import sys
import tempfile
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from .compiler import compile_svg_project


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
        self._directories = {}
        self._temporary = tempfile.TemporaryDirectory(prefix="glissade-preview-")

    def log(self, message):
        timestamp = time.strftime("%H:%M:%S")
        print(f"[{timestamp}] Glissade: {message}", flush=True)

    def build(self):
        with self.build_lock:
            if self.stopped:
                return False
            with self.condition:
                selected_id = self.selected_id
                previous_manifest = self.manifest
                previous_directory = self.build_directory
            build_directory = Path(tempfile.mkdtemp(dir=self._temporary.name))
            if previous_directory:
                for source in previous_directory.glob("*.svg"):
                    shutil.copyfile(source, build_directory / source.name)
            try:
                selected_ids = (
                    {selected_id} if previous_directory and selected_id else None
                )
                build_started = time.perf_counter()
                manifest = compile_svg_project(
                    self.args,
                    build_directory,
                    selected_ids=selected_ids,
                    log=self.log,
                    previous_scenes={
                        scene["id"]: scene for scene in previous_manifest["scenes"]
                    }
                    if previous_manifest
                    else None,
                )
            except Exception as error:
                shutil.rmtree(build_directory, ignore_errors=True)
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
                self._directories[manifest["version"]] = self.build_directory
                while len(self._directories) > 2:
                    oldest = next(iter(self._directories))
                    shutil.rmtree(self._directories.pop(oldest), ignore_errors=True)
                if self.selected_id not in {
                    scene["id"] for scene in manifest["scenes"]
                }:
                    self.selected_id = manifest["scenes"][0]["id"]
                if selected_ids is not None:
                    self.dirty_ids.intersection_update(
                        scene["id"] for scene in manifest["scenes"]
                    )
                    self.dirty_ids.discard(selected_id)
                else:
                    self.dirty_ids.clear()
                self.error = None
                self.generation += 1
                self.condition.notify_all()
            self.log(f"Build ready in {time.perf_counter() - build_started:.2f}s")
            return True

    def close(self):
        self.stopped = True
        with self.condition:
            self.condition.notify_all()
        with self.build_lock:
            self._temporary.cleanup()

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
    extensions = {
        ".typ",
        ".toml",
        ".svg",
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".json",
        ".csv",
        ".tsv",
        ".yaml",
        ".yml",
        ".bib",
        ".txt",
        ".pdf",
        ".xml",
        ".ttf",
        ".otf",
    }
    ignored = {
        ".git",
        ".venv",
        "node_modules",
        "__pycache__",
        "public",
        "dist",
        "build",
    }
    result = {}
    for directory, folders, files in os.walk(root):
        folders[:] = [
            name
            for name in folders
            if name not in ignored and not name.endswith(".frames")
        ]
        for name in files:
            path = Path(directory) / name
            if path.suffix.lower() in extensions:
                try:
                    result[str(path)] = (path.stat().st_mtime_ns, path.stat().st_size)
                except FileNotFoundError:
                    pass
    return result


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
                    self.send_bytes(
                        b'{"error":"Preview is not ready"}',
                        "application/json",
                        HTTPStatus.SERVICE_UNAVAILABLE,
                    )
                else:
                    self.send_bytes(json.dumps(manifest).encode(), "application/json")
            elif path.startswith("/frames/"):
                filename = Path(path).name
                from urllib.parse import parse_qs

                version = parse_qs(urlparse(self.path).query).get("v", [None])[0]
                with state.condition:
                    build_directory = (
                        state._directories.get(version)
                        if version
                        else state.build_directory
                    )
                    frame_path = build_directory / filename if build_directory else None
                    try:
                        content = frame_path.read_bytes() if frame_path else None
                    except FileNotFoundError:
                        content = None
                if content is None:
                    self.send_bytes(
                        b"Frame not found", "text/plain", HTTPStatus.NOT_FOUND
                    )
                else:
                    self.send_bytes(content, "image/svg+xml")
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
                                    self.wfile.write(
                                        (
                                            "event: build-error\ndata: "
                                            + message
                                            + "\n\n"
                                        ).encode()
                                    )
                                else:
                                    self.wfile.write(b"event: reload\ndata: ready\n\n")
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    pass
            elif path == "/select":
                query = urlparse(self.path).query
                selected = next(
                    (
                        part.removeprefix("id=")
                        for part in query.split("&")
                        if part.startswith("id=")
                    ),
                    None,
                )
                if selected:
                    from urllib.parse import unquote

                    should_rebuild = state.select(unquote(selected))
                    if should_rebuild:
                        state.log(
                            f"Selected stale slide {state.selected_id!r}; rebuilding on demand"
                        )
                        threading.Thread(target=state.build, daemon=True).start()
                self.send_bytes(b"ok", "text/plain")
            else:
                self.send_bytes(b"Not found", "text/plain", HTTPStatus.NOT_FOUND)

    return EditorHandler


def handle_dev(args):
    """Run the live SVG editor and rebuild when Typst sources change."""
    from .cli import render_editor_template

    state = LiveBuildState(args)
    if not state.build():
        print(f"Initial build failed: {state.error}")
        state.close()
        return 1
    manifest_source = (
        'fetch("/manifest.json?version=" + Date.now()).then(response => {'
        ' if (!response.ok) throw new Error("Manifest unavailable"); return response.json(); })'
    )
    editor_html = render_editor_template(
        args.template,
        Path(args.input).stem,
        manifest_source,
        True,
    ).encode()
    server = QuietThreadingHTTPServer(
        (args.host, args.port), make_editor_handler(state, editor_html)
    )
    watcher = threading.Thread(target=watch_project, args=(state,), daemon=True)
    watcher.start()
    print(f"Glissade editor running at http://{args.host}:{args.port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        state.close()
        server.server_close()
    return 0
