from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SurfaceProbe:
    name: str
    argv: list[str]
    timeout: float = 2


SAFE_PROBES = [
    SurfaceProbe("cpuinfo", ["cat", "/proc/cpuinfo"]),
    SurfaceProbe("mounts", ["cat", "/proc/mounts"]),
    SurfaceProbe("wlan0_link", ["ip", "link", "show", "wlan0"]),
    SurfaceProbe("processes", ["ps"]),
]

SAFE_FILES = [
    "/sys/class/power_supply/battery/capacity",
    "/sys/class/power_supply/axp2202-battery/capacity",
    "/sys/class/rkwifi/wifi_power",
    "/sys/class/backlight/backlight/brightness",
    "/sys/class/backlight/backlight0/brightness",
    "/sys/class/rtc/rtc0/wakealarm",
]


def surface_enabled() -> bool:
    return os.environ.get("SPRUCE_HARNESS_ALLOW_DEVICE_SURFACE") == "1"


def collect_surface_observations() -> dict[str, object]:
    if not surface_enabled():
        raise RuntimeError("set SPRUCE_HARNESS_ALLOW_DEVICE_SURFACE=1 to run device-surface probes")

    observations: dict[str, object] = {"commands": {}, "files": {}}
    for probe in SAFE_PROBES:
        completed = subprocess.run(
            probe.argv,
            text=True,
            capture_output=True,
            timeout=probe.timeout,
        )
        observations["commands"][probe.name] = {
            "exit": completed.returncode,
            "stdout": completed.stdout[:4000],
            "stderr": completed.stderr[:1000],
        }

    for file_name in SAFE_FILES:
        path = Path(file_name)
        if path.exists() and path.is_file():
            try:
                value = path.read_text(errors="replace")[:1000]
            except OSError as exc:
                value = f"error: {exc}"
        else:
            value = None
        observations["files"][file_name] = value
    return observations
