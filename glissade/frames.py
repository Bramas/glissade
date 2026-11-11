"""SVG delta encoding and portable frame sources."""

import base64
import gzip
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
GLYPH_REFERENCE = "data-glissade-glyph"

# Serialized frames must keep SVG as the default namespace, whichever module
# is imported first (worker processes import this one alone).
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)

_SVG_PREFIX = "{" + SVG_NS + "}"
_XLINK_PREFIX = "{" + XLINK_NS + "}"
_DEFS_TAG = _SVG_PREFIX + "defs"
_SYMBOL_TAG = _SVG_PREFIX + "symbol"


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


def _svg_element_text(element):
    return ET.tostring(element, encoding="unicode", short_empty_elements=True)


def _escape_text(value):
    if "&" in value:
        value = value.replace("&", "&amp;")
    if "<" in value:
        value = value.replace("<", "&lt;")
    if ">" in value:
        value = value.replace(">", "&gt;")
    return value


def _escape_attribute(value):
    value = _escape_text(value)
    if '"' in value:
        value = value.replace('"', "&quot;")
    if "\n" in value or "\r" in value or "\t" in value:
        value = (
            value.replace("\r", "&#13;").replace("\n", "&#10;").replace("\t", "&#09;")
        )
    return value


class _ForeignMarkup(Exception):
    """The subtree uses a namespace that a bare fragment cannot express."""


def _write_fragment(element, write):
    tag = element.tag
    if tag.startswith(_SVG_PREFIX):
        tag = tag[len(_SVG_PREFIX) :]
    elif tag.startswith("{"):
        raise _ForeignMarkup
    write("<" + tag)
    for name, value in element.attrib.items():
        if name.startswith("{"):
            if not name.startswith(_XLINK_PREFIX):
                raise _ForeignMarkup
            name = "xlink:" + name[len(_XLINK_PREFIX) :]
        write(" " + name + '="' + _escape_attribute(value) + '"')
    if element.text or len(element):
        write(">")
        if element.text:
            write(_escape_text(element.text))
        for child in element:
            _write_fragment(child, write)
        write("</" + tag + ">")
    else:
        write("/>")
    if element.tail:
        write(_escape_text(element.tail))


def _fragment_text(element):
    """Serialize a subtree without namespace declarations.

    The browser parses every fragment inside an `<svg>` wrapper that declares
    the SVG and XLink namespaces, so repeating them on each patch only adds
    bytes. Anything else falls back to a self-describing serialization.
    """
    parts = []
    try:
        _write_fragment(element, parts.append)
    except _ForeignMarkup:
        return _svg_element_text(element)
    return "".join(parts)


def _minify_tree(root):
    for element in root.iter():
        if element.text is not None and element.text.isspace():
            element.text = None
        if element.tail is not None and element.tail.isspace():
            element.tail = None


class _TreeIndex:
    """Gives equal SVG subtrees the same integer, across the frames of a scene.

    Comparing two subtrees and estimating their serialized size then cost one
    dictionary lookup instead of one serialization per comparison.
    """

    def __init__(self):
        self._keys = {}
        self.sizes = []

    def index(self, root):
        """Return a map from every element below `root` to its subtree number."""
        keys = self._keys
        sizes = self.sizes
        numbers = {}

        def visit(element):
            size = 2 * len(element.tag) + 5
            children = []
            for child in element:
                number = visit(child)
                children.append(number)
                size += sizes[number]
            attributes = tuple(element.attrib.items())
            for name, value in attributes:
                size += len(name) + len(value) + 6
            text = element.text or ""
            tail = element.tail or ""
            key = (element.tag, attributes, text, tail, tuple(children))
            number = keys.get(key)
            if number is None:
                number = len(sizes)
                keys[key] = number
                sizes.append(size + len(text) + len(tail))
            numbers[element] = number
            return number

        visit(root)
        return numbers


def _glyph_symbols(root):
    return [
        symbol
        for defs in root.iter(_DEFS_TAG)
        if defs.get("id") == "glyph"
        for symbol in defs
        if symbol.tag == _SYMBOL_TAG
    ]


class SceneEncoder:
    """Turns the SVG frames of one slide into portable frame sources.

    Frames are fed in order and parsed once. Each one comes back either as SVG
    text or, when that is smaller, as a delta against the last keyframe. Glyph
    outlines are collected in `glyphs` and replaced by one-element placeholders,
    which keeps the tree paths used by deltas valid before and after the
    browser restores them.
    """

    def __init__(self, keyframes=None, *, minify=True, share_glyphs=True, optimize=True):
        self.keyframes = None if keyframes is None else set(keyframes)
        self.minify = minify
        self.share_glyphs = share_glyphs
        self.optimize = optimize
        self.glyphs = []
        self._glyph_numbers = {}
        self._index = _TreeIndex()
        self._base = None

    def _share_glyphs(self, root):
        symbols = _glyph_symbols(root)
        if not symbols:
            return False
        for symbol in symbols:
            number = self._index.index(symbol)[symbol]
            glyph = self._glyph_numbers.get(number)
            if glyph is None:
                glyph = len(self.glyphs)
                self._glyph_numbers[number] = glyph
                self.glyphs.append(_svg_element_text(symbol))
            # A single placeholder replaces a single symbol. Delta paths stay
            # valid both before and after restoring the original glyph.
            tail = symbol.tail
            symbol.clear()
            symbol.set(GLYPH_REFERENCE, str(glyph))
            symbol.tail = tail
        return True

    def encode(self, index, text):
        """Return `(source, changed)` for the frame at `index`.

        `source` is SVG text or a delta dictionary. `changed` tells whether SVG
        text differs from the input and has to be stored again.
        """
        try:
            root = ET.fromstring(text)
        except ET.ParseError:
            self._base = None
            return text, False

        changed = False
        if self.minify:
            _minify_tree(root)
            changed = True
        if self.share_glyphs and self._share_glyphs(root):
            changed = True

        def full():
            return (_svg_element_text(root), True) if changed else (text, False)

        if not self.optimize:
            return full()
        numbers = self._index.index(root)
        is_keyframe = self.keyframes is None or index in self.keyframes
        if is_keyframe or self._base is None:
            self._base = (index, root, numbers)
            return full()

        base_index, base_root, base_numbers = self._base
        patches = self._patches(base_root, root, base_numbers, numbers, [])
        if any(not patch["path"] for patch in patches):
            return full()
        delta = {"kind": "svg-delta-v1", "base": base_index, "patches": patches}
        if not patches:
            return delta, True
        full_text, full_changed = full()
        if len(json.dumps(delta, separators=(",", ":"))) < len(full_text):
            return delta, True
        return full_text, full_changed

    def _replacement(self, path, target, numbers):
        cost = self._index.sizes[numbers[target]] + 4 * len(path) + 20
        return [{"path": path, "svg": target}], cost

    def _regrouping(self, base, target, base_numbers, numbers, path):
        """Rebuild a child list from the base's children and new markup.

        Elements that appear or disappear between two frames shift their
        siblings, so comparing children by position would resend all of them.
        """
        if base.text or target.text or any(child.tail for child in target):
            return None
        available = {}
        for position, child in enumerate(base):
            available.setdefault(base_numbers[child], []).append(position)
        children = []
        cost = 4 * len(path) + 30
        for child in target:
            positions = available.get(numbers[child])
            if positions:
                # Reuse each base child once before repeating one of them.
                children.append(positions.pop(0) if len(positions) > 1 else positions[0])
                cost += 4
            else:
                children.append(child)
                cost += self._index.sizes[numbers[child]] + 3
        return [{"path": path, "children": children}], cost

    def _patches(self, base, target, base_numbers, numbers, path):
        """Smallest set of patches found, with their markup serialized."""
        patches, _ = self._diff(base, target, base_numbers, numbers, path)
        for patch in patches:
            if "svg" in patch:
                patch["svg"] = _fragment_text(patch["svg"])
            else:
                patch["children"] = [
                    child if isinstance(child, int) else _fragment_text(child)
                    for child in patch["children"]
                ]
        return patches

    def _diff(self, base, target, base_numbers, numbers, path):
        if base_numbers[base] == numbers[target]:
            return [], 0
        if (
            base.tag != target.tag
            or base.attrib != target.attrib
            or (base.text or "") != (target.text or "")
            or (base.tail or "") != (target.tail or "")
        ):
            return self._replacement(path, target, numbers)
        options = []
        if path:
            options.append(self._replacement(path, target, numbers))
            regrouping = self._regrouping(base, target, base_numbers, numbers, path)
            if regrouping is not None:
                options.append(regrouping)
        if len(base) == len(target):
            patches = []
            cost = 0
            for position, (base_child, target_child) in enumerate(zip(base, target)):
                child_patches, child_cost = self._diff(
                    base_child, target_child, base_numbers, numbers, path + [position]
                )
                patches += child_patches
                cost += child_cost
            options.append((patches, cost))
        elif not path:
            # Only a new frame can change the children of the root.
            return self._replacement(path, target, numbers)
        return min(options, key=lambda option: option[1])


def _source_frame_name(frame_source):
    return urlparse(frame_source).path.removeprefix("/frames/")


def _is_frame_delta(frame_source):
    return isinstance(frame_source, dict) and frame_source.get("kind") == "svg-delta-v1"


def _share_scene_glyphs(scene, frame_directory):
    """Replace glyph symbols with references, preserving SVG tree paths."""
    if len(scene["frames"]) < 2:
        return []
    encoder = SceneEncoder(minify=False, optimize=False)
    for source in scene["frames"]:
        path = Path(frame_directory) / _source_frame_name(source)
        text, changed = encoder.encode(0, path.read_text(encoding="utf-8"))
        if changed:
            path.write_text(text, encoding="utf-8")
    return encoder.glyphs


def _optimize_scene_frames(scene, frame_directory):
    """Store intermediate frames as deltas when that is smaller."""
    frames = scene.get("frames", [])
    if len(frames) < 3:
        return
    keyframes = scene.get("keyframes") or [0, len(frames) - 1]
    encoder = SceneEncoder(keyframes, minify=False, share_glyphs=False)
    optimized = []
    for index, frame_source in enumerate(frames):
        path = Path(frame_directory) / _source_frame_name(frame_source)
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            optimized.append(frame_source)
            continue
        source, _ = encoder.encode(index, text)
        optimized.append(source if _is_frame_delta(source) else frame_source)
    scene["frames"] = optimized


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


def encode_scene(
    scene,
    frame_directory,
    *,
    minify=True,
    share_glyphs=True,
    optimize=True,
    compress=True,
):
    """Read a scene's SVG files once and return its portable frame sources.

    Full frames come back as `(file name, SVG bytes)` pairs so that the caller
    can embed them or write them next to the presentation; deltas are returned
    as they will appear in the manifest. The scene itself is updated with the
    shared glyph and patch payload.
    """
    frames = scene.get("frames", [])
    keyframes = scene.get("keyframes") or [0, len(frames) - 1]
    encoder = SceneEncoder(
        keyframes,
        minify=minify,
        share_glyphs=share_glyphs and len(frames) > 1,
        optimize=optimize and len(frames) > 2,
    )
    sources = []
    for index, frame_source in enumerate(frames):
        name = _source_frame_name(frame_source)
        text = (Path(frame_directory) / name).read_text(encoding="utf-8")
        source, _ = encoder.encode(index, text)
        if _is_frame_delta(source):
            sources.append(source)
        else:
            data = source.encode("utf-8")
            if compress:
                data = gzip.compress(data, compresslevel=9, mtime=0)
            sources.append((name, data))
    scene["frames"] = [
        source if _is_frame_delta(source) else None for source in sources
    ]
    _pack_scene_svg(scene, encoder.glyphs, compress)
    return scene, sources
