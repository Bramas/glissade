#!/usr/bin/env python3
"""Repository entry point; installed users can run `glissade` directly."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from glissade.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
