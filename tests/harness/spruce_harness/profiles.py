from __future__ import annotations

import copy
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


HARNESS_DIR = Path(__file__).resolve().parents[1]
PROFILE_DIR = HARNESS_DIR / "profiles"


def _default_spruce_config() -> dict[str, Any]:
    return {
        "menuOptions": {
            "Network Settings": {
                "enableSamba": {"selected": "False"},
                "enableSSH": {"selected": "False"},
                "enableSFTPGo": {"selected": "False"},
                "enableSyncthing": {"selected": "False"},
            },
            "Emulator Settings": {
                "verboseLogging": {"selected": "False"},
                "perfectOverlays": {"selected": "True"},
                "raAutoSave": {"selected": "Custom"},
                "raAutoLoad": {"selected": "Custom"},
                "raHotkeyTrimUI": {"selected": "Menu"},
                "raHotkeyMiyoo": {"selected": "Select"},
                "raInGameMenu": {"selected": "True"},
                "disableWifiInGame": {"selected": "False"},
            },
            "RetroAchievements Settings": {
                "modeToggle": {"selected": "Manual"},
                "username": {"selected": ""},
                "password": {"selected": ""},
            },
        }
    }


def _default_system_json() -> dict[str, Any]:
    return {
        "wifi": 1,
        "vol": 10,
        "brightness": 5,
        "bluetooth": 0,
    }


def _deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


@dataclass(frozen=True)
class DeviceProfile:
    name: str
    expected_platform: str
    expected_display: dict[str, str]
    cpuinfo: str
    cmdline: str = ""
    system_json_path: str = "/mnt/SDCARD/Saves/spruce-system.json"
    sd_mountpoint: str = "/mnt/SDCARD"
    files: dict[str, str] = field(default_factory=dict)
    sysfs: dict[str, str] = field(default_factory=dict)
    spruce_config: dict[str, Any] = field(default_factory=dict)
    system_json: dict[str, Any] = field(default_factory=dict)
    mount_entries: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "DeviceProfile":
        return cls(
            name=data["name"],
            expected_platform=data["expected_platform"],
            expected_display={
                key: str(value)
                for key, value in data.get("expected_display", {}).items()
            },
            cpuinfo=data.get("cpuinfo", ""),
            cmdline=data.get("cmdline", ""),
            system_json_path=data.get("system_json_path", "/mnt/SDCARD/Saves/spruce-system.json"),
            sd_mountpoint=data.get("sd_mountpoint", "/mnt/SDCARD"),
            files={str(k): str(v) for k, v in data.get("files", {}).items()},
            sysfs={str(k): str(v) for k, v in data.get("sysfs", {}).items()},
            spruce_config=_deep_merge(_default_spruce_config(), data.get("spruce_config", {})),
            system_json=_deep_merge(_default_system_json(), data.get("system_json", {})),
            mount_entries=[str(line) for line in data.get("mount_entries", [])],
            env={str(k): str(v) for k, v in data.get("env", {}).items()},
        )


def profile_names() -> list[str]:
    return sorted(path.stem for path in PROFILE_DIR.glob("*.json"))


def load_profile(name: str) -> DeviceProfile:
    path = PROFILE_DIR / f"{name}.json"
    if not path.exists():
        known = ", ".join(profile_names())
        raise KeyError(f"unknown profile {name!r}; known profiles: {known}")
    return DeviceProfile.from_dict(json.loads(path.read_text()))
