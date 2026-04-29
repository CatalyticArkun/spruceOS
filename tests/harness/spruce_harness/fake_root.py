from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path

from .profiles import DeviceProfile


REAL_PREFIXES = {
    "/media/SDCARD0": "media/SDCARD0",
    "/media/sdcard0": "media/sdcard0",
    "/mnt/SDCARD": "mnt/SDCARD",
    "/mnt/sdcard": "mnt/sdcard",
    "/mnt/UDISK": "mnt/UDISK",
    "/mnt/vendor": "mnt/vendor",
    "/customer": "customer",
    "/userdata": "userdata",
    "/proc": "proc",
    "/sys": "sys",
    "/dev": "dev",
    "/tmp": "tmp",
    "/run": "run",
    "/etc": "etc",
    "/usr": "usr",
}


class FakeRoot:
    """Builds a fake device filesystem for smoke tests.

    Production scripts are copied into the fake SD card and rewritten in that
    temporary copy only. The source checkout remains untouched.
    """

    def __init__(self, repo_root: Path, profile: DeviceProfile, root: Path):
        self.repo_root = Path(repo_root)
        self.profile = profile
        self.root = Path(root)
        self.state_dir = self.root / "harness"
        self.calls_file = self.state_dir / "calls.jsonl"
        self.process_file = self.state_dir / "processes.json"

    def build(self) -> "FakeRoot":
        if self.root.exists():
            shutil.rmtree(self.root)
        self._create_base_dirs()
        self._copy_runtime_scripts()
        self._write_profile_files()
        self._write_emulator_fixture()
        self._rewrite_runtime_copy()
        self._write_system_emit()
        self.calls_file.write_text("")
        self.process_file.write_text("{}")
        return self

    def fake_path(self, real_path: str) -> Path:
        for prefix, relative in sorted(REAL_PREFIXES.items(), key=lambda item: len(item[0]), reverse=True):
            if real_path == prefix:
                return self.root / relative
            if real_path.startswith(prefix + "/"):
                return self.root / relative / real_path[len(prefix) + 1 :]
        raise ValueError(f"path is not mapped into fake root: {real_path}")

    def fake_str(self, real_path: str) -> str:
        return str(self.fake_path(real_path))

    def write_real_path(self, real_path: str, content: str, mode: int | None = None) -> Path:
        target = self.fake_path(real_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        if mode is not None:
            target.chmod(mode)
        return target

    def read_real_path(self, real_path: str) -> str:
        return self.fake_path(real_path).read_text()

    def rewrite_text(self, text: str) -> str:
        prefixes = sorted(REAL_PREFIXES, key=len, reverse=True)
        pattern = re.compile(
            "|".join(f"{re.escape(prefix)}(?=/|$|[^A-Za-z0-9_./-])" for prefix in prefixes)
        )

        def replace(match: re.Match[str]) -> str:
            return str(self.fake_path(match.group(0)))

        return pattern.sub(replace, text)

    def _create_base_dirs(self) -> None:
        for relative in [
            "harness",
            "mnt",
            "mnt/SDCARD",
            "mnt/UDISK",
            "mnt/vendor/bin",
            "mnt/vendor/oem",
            "media/SDCARD0",
            "media/sdcard0",
            "proc/1/fd",
            "proc/self",
            "sys",
            "dev/input",
            "tmp",
            "run",
            "etc/bluetooth",
            "usr/bin",
            "usr/sbin",
            "usr/libexec/bluetooth",
            "usr/trimui/osd",
            "customer/app",
            "userdata",
            "bin",
            "sbin",
        ]:
            (self.root / relative).mkdir(parents=True, exist_ok=True)
        sd_lower = self.root / "mnt/sdcard"
        if not sd_lower.exists():
            os.symlink("SDCARD", sd_lower)
        (self.root / "dev/null").write_text("")

    def _copy_runtime_scripts(self) -> None:
        src = self.repo_root / "spruce" / "scripts"
        dst = self.fake_path("/mnt/SDCARD/spruce/scripts")
        shutil.copytree(src, dst)

    def _write_profile_files(self) -> None:
        self.write_real_path("/proc/cpuinfo", self.profile.cpuinfo)
        self.write_real_path("/proc/cmdline", self.profile.cmdline)
        mounts = self.profile.mount_entries or [
            f"/dev/mmcblk-test {self.profile.sd_mountpoint} vfat rw,relatime 0 0",
        ]
        rewritten_mounts = [self.rewrite_text(line) for line in mounts]
        mount_text = "\n".join(rewritten_mounts) + "\n"
        self.write_real_path("/proc/mounts", mount_text)
        self.write_real_path("/proc/self/mountinfo", self._mountinfo_from_mounts(rewritten_mounts))
        self.write_real_path(self.profile.system_json_path, json.dumps(self.profile.system_json, indent=2) + "\n")
        self.write_real_path("/mnt/SDCARD/Saves/spruce/spruce-config.json", json.dumps(self.profile.spruce_config, indent=2) + "\n")
        self.write_real_path("/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf", "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1\n")
        self.write_real_path("/mnt/SDCARD/RetroArch/retroarch.cfg", 'cheevos_enable = "false"\n')

        for real_path, content in self.profile.files.items():
            self.write_real_path(real_path, content)
        for real_path, content in self.profile.sysfs.items():
            self.write_real_path(real_path, content)

    def _write_emulator_fixture(self) -> None:
        emu_config = {
            "default_emulator": "gambatte",
            "scaling_min_freq": "1008000",
            "menuOptions": {
                "Governor": {"selected": "Performance", "overrides": {}},
                "Emulator": {"selected": "gambatte", "overrides": {}},
                "Emulator_32": {"selected": "gambatte", "overrides": {}},
                "Emulator_64": {"selected": "gambatte", "overrides": {}},
                "raBuild": {"selected": "", "overrides": {}},
            },
        }
        self.write_real_path("/mnt/SDCARD/Emu/GB/config.json", json.dumps(emu_config, indent=2) + "\n")
        self.write_real_path("/mnt/SDCARD/Roms/GB/Tetris.gb", "fake rom\n")
        platform = self.profile.expected_platform
        for cfg_name in [platform, "AnbernicRG_XX-universal"]:
            self.write_real_path(
                f"/mnt/SDCARD/RetroArch/platform/retroarch-{cfg_name}.cfg",
                "\n".join(
                    [
                        'cheevos_enable = "false"',
                        'cheevos_hardcore_mode_enable = "false"',
                        'cheevos_username = ""',
                        'cheevos_password = ""',
                        'savestate_auto_save = "false"',
                        'savestate_auto_load = "false"',
                        'input_enable_hotkey = "8"',
                        'video_rotation = "0"',
                    ]
                )
                + "\n",
            )

    def _rewrite_runtime_copy(self) -> None:
        runtime_root = self.fake_path("/mnt/SDCARD/spruce/scripts")
        for path in runtime_root.rglob("*"):
            if not path.is_file() or path.suffix not in {".sh", ".cfg", ".py"}:
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            path.write_text(self.rewrite_text(text))

    def _write_system_emit(self) -> None:
        dispatcher = self.root / "harness" / "shim_dispatch.py"
        target = self.fake_path("/mnt/SDCARD/spruce/scripts/system-emit")
        target.write_text(
            "#!/bin/sh\n"
            f'exec "{os.environ.get("PYTHON", "python3")}" "{dispatcher}" system-emit "$@"\n'
        )
        target.chmod(0o755)

    @staticmethod
    def _mountinfo_from_mounts(mounts: list[str]) -> str:
        lines = []
        for index, line in enumerate(mounts, start=30):
            parts = line.split()
            if len(parts) < 3:
                continue
            source, mountpoint, fs_type = parts[:3]
            lines.append(f"{index} 1 0:0 / {mountpoint} rw,relatime - {fs_type} {source} rw")
        return "\n".join(lines) + "\n"
