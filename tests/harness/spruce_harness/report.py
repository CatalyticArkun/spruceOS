from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from .fake_root import REAL_PREFIXES
from .profiles import profile_names
from .shims import SHIMMED_COMMANDS


HARNESS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = HARNESS_ROOT.parents[1]


SMOKE_SURFACES = {
    "platform_detection": [
        "spruce/scripts/helperFunctions.sh",
        "spruce/scripts/platform/*.cfg",
        "spruce/scripts/platform/device_functions/*.sh",
    ],
    "wifi_contracts": [
        "spruce/scripts/helperFunctions.sh",
        "spruce/scripts/platform/device_functions/Flip.sh",
        "spruce/scripts/platform/device_functions/trimui_a133p.sh",
    ],
    "network_services": [
        "spruce/scripts/networkservices.sh",
        "spruce/scripts/network/*.sh",
    ],
    "archive_unpacker": [
        "spruce/scripts/archiveUnpacker.sh",
        "spruce/scripts/firstbootLaneCommon.sh",
    ],
    "runtime_helper": [
        "spruce/scripts/runtimeHelper.sh",
    ],
    "sleep_helper": [
        "spruce/scripts/sleep_helper.sh",
        "spruce/scripts/platform/device_functions/utils/sleep_functions.sh",
    ],
    "poweroff_stage2": [
        "spruce/scripts/save_poweroff_stage2.sh",
    ],
    "standard_launch": [
        "spruce/scripts/emu/standard_launch.sh",
        "spruce/scripts/emu/lib/*.sh",
    ],
    "layer_gates": [
        "tests/harness/spruce_harness/runner.py",
        "tests/harness/spruce_harness/device_surface.py",
    ],
}


def build_harness_report() -> dict[str, Any]:
    smoke_tests = sorted(str(path.relative_to(REPO_ROOT)) for path in (REPO_ROOT / "tests/smoke").glob("test_*.py"))
    return {
        "layers": ["host-sim", "device-sim", "device-surface"],
        "profiles": profile_names(),
        "real_path_prefixes": dict(sorted(REAL_PREFIXES.items())),
        "shimmed_commands": sorted(SHIMMED_COMMANDS),
        "smoke_tests": smoke_tests,
        "smoke_surfaces": SMOKE_SURFACES,
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = ["# spruceOS Harness Coverage", ""]
    lines.append("## Layers")
    lines.extend(f"- `{layer}`" for layer in report["layers"])
    lines.append("")
    lines.append("## Device Profiles")
    lines.extend(f"- `{profile}`" for profile in report["profiles"])
    lines.append("")
    lines.append("## Rewritten Real-Path Prefixes")
    lines.extend(f"- `{source}` -> `{target}`" for source, target in report["real_path_prefixes"].items())
    lines.append("")
    lines.append("## Shimmed Commands")
    lines.extend(f"- `{command}`" for command in report["shimmed_commands"])
    lines.append("")
    lines.append("## Smoke Tests")
    lines.extend(f"- `{test}`" for test in report["smoke_tests"])
    lines.append("")
    lines.append("## Exercised Surfaces")
    for name, paths in report["smoke_surfaces"].items():
        lines.append(f"- `{name}`: " + ", ".join(f"`{path}`" for path in paths))
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Print spruceOS harness coverage.")
    parser.add_argument("--format", choices=["markdown", "json"], default="markdown")
    args = parser.parse_args()
    report = build_harness_report()
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_markdown(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
