#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pypdf",
# ]
# ///

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "site" / "examples"
GLISSADE = ROOT / "bin" / "glissade.py"


def build(source: Path) -> None:
    title = source.stem.replace("-", " ").title()
    common = [
        sys.executable,
        str(GLISSADE),
        "--root",
        str(ROOT),
        str(source),
    ]
    subprocess.run(
        [*common, "html", "--fps", "24", "--title", title],
        cwd=ROOT,
        check=True,
    )
    subprocess.run([*common, "slides"], cwd=ROOT, check=True)
    print(f"Built {source.stem}.html and {source.stem}.pdf")


def main() -> None:
    sources = sorted(EXAMPLES.glob("*.typ"))
    if not sources:
        raise SystemExit(f"No Typst examples found in {EXAMPLES}")
    for source in sources:
        build(source)


if __name__ == "__main__":
    main()
