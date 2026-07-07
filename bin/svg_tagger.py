#!/usr/bin/env python3
"""Tag SVG elements representing explicit Kino formula parts."""

import sys
from pathlib import Path
import xml.etree.ElementTree as ET


START_FILL = "#ff4fd8"
END_FILL = "#00d5ff"
MORPH_START_FILL = "#19c37d"
MORPH_END_FILL = "#ff8a00"
PART_ID_PREFIX = "formula-part-"
MORPH_ID_PREFIX = "kino-morph-"
SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
H5_NS = "http://www.w3.org/1999/xhtml"


ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)
ET.register_namespace("h5", H5_NS)


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _marker_kind(group: ET.Element) -> str | None:
    if _local_name(group.tag) != "g":
        return None
    if group.get("transform") is None:
        return None

    paths = [node for node in group.iter() if _local_name(node.tag) == "path"]
    uses = [node for node in group.iter() if _local_name(node.tag) == "use"]
    if uses or len(paths) != 1:
        return None

    path = paths[0]
    fill = path.get("fill", "").lower()
    if fill == START_FILL:
        return "start"
    if fill == END_FILL:
        return "end"
    if fill == MORPH_START_FILL:
        return "morph-start"
    if fill == MORPH_END_FILL:
        return "morph-end"
    return None


def _has_visible_content(element: ET.Element) -> bool:
    for node in element.iter():
        name = _local_name(node.tag)
        if name == "use":
            return True
        if name == "path" and node.get("fill") not in {START_FILL, END_FILL, MORPH_START_FILL, MORPH_END_FILL}:
            return True
    return False


def _previous_content_sibling(parent: ET.Element, marker: ET.Element) -> ET.Element | None:
    children = list(parent)
    marker_index = children.index(marker)
    for sibling in reversed(children[:marker_index]):
        if _marker_kind(sibling) is not None:
            continue
        if _local_name(sibling.tag) != "g":
            continue
        if _has_visible_content(sibling):
            return sibling
    return None


def _remove_old_formula_ids(root: ET.Element) -> None:
    for element in root.iter():
        element_id = element.get("id")
        if element_id and (element_id.startswith(PART_ID_PREFIX) or element_id.startswith(MORPH_ID_PREFIX)):
            del element.attrib["id"]
        for attribute in (
            "data-kino-morph",
            "data-kino-morph-id",
            "data-kino-morph-svg-id",
            "data-kino-morph-name",
            "data-kino-morph-index",
            "data-kino-part",
            "data-kino-part-id",
            "data-kino-part-key",
            "data-kino-state",
            "data-kino-parent-morph",
        ):
            if attribute in element.attrib:
                del element.attrib[attribute]


def tag_svg_groups(
    svg_content: str,
    part_specs: list[dict[str, str]] | None = None,
    morph_specs: list[dict[str, str]] | None = None,
) -> str:
    """Add IDs only to groups explicitly marked by Kino formula sentinels."""
    root = ET.fromstring(svg_content)
    parent_map = {child: parent for parent in root.iter() for child in parent}
    _remove_old_formula_ids(root)

    tagged_targets = []
    morph_targets = []
    open_start = None
    open_morph_start = None

    for element in root.iter():
        kind = _marker_kind(element)
        if kind is None:
            continue

        parent = parent_map.get(element)
        if parent is None:
            continue

        if kind == "morph-start":
            open_morph_start = (element, parent)
            continue

        if kind == "start":
            open_start = (element, parent)
            continue

        if kind == "morph-end":
            if open_morph_start is None:
                continue
            start_marker, start_parent = open_morph_start
            if start_parent is not parent:
                open_morph_start = None
                continue
            target = _previous_content_sibling(parent, element)
            if target is not None:
                morph_targets.append((target, start_marker, element, parent))
            open_morph_start = None
            continue

        if open_start is None:
            continue

        start_marker, start_parent = open_start
        if start_parent is not parent:
            open_start = None
            continue

        target = _previous_content_sibling(parent, start_marker)
        if target is not None:
            tagged_targets.append((target, start_marker, element, parent))

        open_start = None

    for index, (target, start_marker, end_marker, parent) in enumerate(tagged_targets):
        if part_specs is not None and index < len(part_specs):
            part = part_specs[index]
            target.set("id", part["id"])
            target.set("data-kino-part", "true")
            target.set("data-kino-part-id", part["id"])
            target.set("data-kino-part-key", part["key"])
            target.set("data-kino-state", part["state"])
            morph_name = part.get("morph")
            if morph_name is not None:
                target.set("data-kino-parent-morph", morph_name)
        else:
            target.set("id", f"{PART_ID_PREFIX}{index}")
        parent.remove(start_marker)
        parent.remove(end_marker)

    for index, (target, start_marker, end_marker, parent) in enumerate(morph_targets):
        if morph_specs is not None and index < len(morph_specs):
            morph = morph_specs[index]
            target.set("id", morph["id"])
            target.set("data-kino-morph-id", morph["name"])
            target.set("data-kino-morph-svg-id", morph["id"])
            target.set("data-kino-morph-name", morph["name"])
        else:
            target.set("id", f"{MORPH_ID_PREFIX}{index}")
        target.set("data-kino-morph", "true")
        target.set("data-kino-morph-index", str(index))
        parent.remove(start_marker)
        parent.remove(end_marker)

    if tagged_targets:
        print(f"Tagged {len(tagged_targets)} formula parts with explicit marker IDs", file=sys.stderr)
    if morph_targets:
        print(f"Tagged {len(morph_targets)} morph container(s)", file=sys.stderr)

    return ET.tostring(root, encoding="unicode")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 svg_tagger.py <input.svg> [output.svg]")
        print("\nTags SVG groups with sequential formula-part IDs.")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path
    
    input_file = Path(input_path)
    if not input_file.exists():
        print(f"Error: {input_path} not found", file=sys.stderr)
        sys.exit(1)
    
    content = input_file.read_text(encoding='utf-8')
    tagged_content = tag_svg_groups(content)
    
    Path(output_path).write_text(tagged_content, encoding='utf-8')
    print(f"Wrote: {output_path}", file=sys.stderr)


if __name__ == '__main__':
    main()



