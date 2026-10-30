#!/usr/bin/env python3
"""Compatibility entry point for the SVG tagger."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from glissade.svg_tagger import main  # noqa: E402

if __name__ == "__main__":
    main()
