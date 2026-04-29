from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from enum import Enum
from pathlib import Path
from typing import Iterable

from .fake_root import FakeRoot
from .profiles import DeviceProfile, load_profile
from .shims import CommandShims


class HarnessLayer(str, Enum):
    HOST_SIM = "host-sim"
    DEVICE_SIM = "device-sim"
    DEVICE_SURFACE = "device-surface"


class HarnessRunner:
    def __init__(
        self,
        repo_root: Path,
        profile: str | DeviceProfile,
        layer: HarnessLayer | str = HarnessLayer.HOST_SIM,
        root: Path | None = None,
    ):
        self.repo_root = Path(repo_root)
        self.profile = load_profile(profile) if isinstance(profile, str) else profile
        self.layer = HarnessLayer(layer)
        self._tempdir: tempfile.TemporaryDirectory[str] | None = None
        self.root_path = root or self._default_root()
        self.fake_root = FakeRoot(self.repo_root, self.profile, self.root_path).build()
        self.shims = CommandShims(self.root_path).install()
        self.env = os.environ.copy()
        self.env.update(self.shims.env())
        self.env.update(self.profile.env)
        self.env["SPRUCE_HARNESS_LAYER"] = self.layer.value

    def cleanup(self) -> None:
        if self._tempdir is not None:
            self._tempdir.cleanup()
            self._tempdir = None

    def run(
        self,
        argv: list[str],
        *,
        cwd: Path | None = None,
        timeout: float = 10,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            argv,
            cwd=cwd or self.root_path,
            env=env,
            text=True,
            capture_output=True,
            timeout=timeout,
        )

    def sh(self, script: str, *, timeout: float = 10, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return self.run(["/bin/sh", "-lc", script], timeout=timeout, extra_env=extra_env)

    def source_helper_and_run(self, script: str, *, timeout: float = 10) -> subprocess.CompletedProcess[str]:
        helper = self.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/helperFunctions.sh")
        return self.sh(f'. "{helper}"; {script}', timeout=timeout)

    def calls(self) -> list[dict[str, object]]:
        calls_file = self.fake_root.calls_file
        if not calls_file.exists():
            return []
        return [json.loads(line) for line in calls_file.read_text().splitlines() if line.strip()]

    def called(self, command: str, contains: Iterable[str] | None = None) -> bool:
        expected = list(contains or [])
        for call in self.calls():
            if call["command"] != command:
                continue
            argv = [str(part) for part in call.get("argv", [])]
            if all(any(value in arg for arg in argv) for value in expected):
                return True
        return False

    def wait_called(
        self,
        command: str,
        contains: Iterable[str] | None = None,
        *,
        timeout: float = 1,
    ) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.called(command, contains):
                return True
            time.sleep(0.02)
        return self.called(command, contains)

    def _default_root(self) -> Path:
        if self.layer == HarnessLayer.DEVICE_SURFACE:
            raise ValueError("device-surface layer does not use a fake root runner")
        if self.layer == HarnessLayer.DEVICE_SIM:
            if os.environ.get("SPRUCE_HARNESS_ALLOW_DEVICE_SIM") != "1":
                raise RuntimeError("set SPRUCE_HARNESS_ALLOW_DEVICE_SIM=1 to run device-sim")
            return Path(os.environ.get("SPRUCE_HARNESS_DEVICE_SIM_ROOT", "/tmp/spruce-harness-device-sim"))
        self._tempdir = tempfile.TemporaryDirectory(prefix="spruce-harness-")
        return Path(self._tempdir.name)
