from __future__ import annotations

import json

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _set_system_setting(runner: HarnessRunner, key: str, value: str) -> None:
    config = json.loads(runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce-config.json"))
    system = config["menuOptions"].setdefault("System Settings", {})
    system[key] = {"selected": value}
    runner.fake_root.write_real_path(
        "/mnt/SDCARD/Saves/spruce/spruce-config.json",
        json.dumps(config, indent=2) + "\n",
    )


def test_set_up_swap_creates_configured_swapfile_without_host_swap_calls():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_system_setting(runner, "swapfileSize", "128MB")
        runner.fake_root.write_real_path("/proc/sys/vm/swappiness", "0\n")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/set_up_swap.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 0, result.stderr
        assert runner.fake_root.read_real_path("/mnt/SDCARD/cachefile") == "spruce-harness-swap\n"
        assert runner.fake_root.read_real_path("/proc/sys/vm/swappiness").strip() == "10"
        assert runner.called("dd", ["of=", "cachefile", "count=128"])
        assert runner.called("mkswap", ["cachefile"])
        assert runner.called("swapon", ["cachefile"])
    finally:
        runner.cleanup()


def test_set_up_swap_removes_extraneous_swapfile_when_disabled():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_system_setting(runner, "swapfileSize", "Off")
        swapfile = runner.fake_root.write_real_path("/mnt/SDCARD/cachefile", "old swap\n")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/set_up_swap.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 0, result.stderr
        assert not swapfile.exists()
        assert runner.called("swapoff", ["cachefile"])
    finally:
        runner.cleanup()


def test_enable_zram_disabled_delegates_to_disable_zram_cleanup():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_system_setting(runner, "useZRAM", "False")
        zram_path = runner.fake_root.fake_str("/dev/zram0")
        runner.fake_root.write_real_path("/proc/swaps", f"{zram_path} partition 131068 0 -2\n")
        runner.fake_root.write_real_path("/sys/block/zram0/reset", "0\n")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/enable_zram.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 0, result.stderr
        assert runner.called("swapoff", [zram_path])
        assert runner.fake_root.read_real_path("/sys/block/zram0/reset").strip() == "1"
    finally:
        runner.cleanup()


def test_enable_zram_reports_missing_kernel_surface_when_requested():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_system_setting(runner, "useZRAM", "True")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/enable_zram.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 1
        assert runner.called("modprobe", ["zram"])
        log = runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce.log")
        assert "Kernel may lack zram support." in log
    finally:
        runner.cleanup()


def test_asound_setup_writes_default_device_audio_config_without_bluetooth():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        home = "/mnt/SDCARD/Saves/flip/home"
        runner.fake_root.write_real_path(f"{home}/.keep", "")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/asound-setup.sh")

        result = runner.run(["/bin/sh", script, runner.fake_root.fake_str(home)], timeout=10)

        assert result.returncode == 0, result.stderr
        asound = runner.fake_root.read_real_path(f"{home}/.asoundrc")
        assert 'slave.pcm "dmix"' in asound
        assert "bluealsa" not in asound
    finally:
        runner.cleanup()
