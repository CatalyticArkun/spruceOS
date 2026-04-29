from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HARNESS_ROOT = REPO_ROOT / "tests" / "harness"

sys.path.insert(0, str(HARNESS_ROOT))
