from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def test_gb_standard_launch_reaches_retroarch_through_fake_binary():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        standard_launch = runner.fake_root.fake_path("/mnt/SDCARD/spruce/scripts/emu/standard_launch.sh")
        launcher = runner.fake_root.fake_path("/mnt/SDCARD/Emu/GB/launch.sh")
        launcher.parent.mkdir(parents=True, exist_ok=True)
        launcher.symlink_to(standard_launch)
        rom = runner.fake_root.fake_str("/mnt/SDCARD/Roms/GB/Tetris.gb")

        result = runner.run(["/bin/sh", str(launcher), rom], timeout=15)
        assert result.returncode == 0, result.stderr
        assert runner.called("ra64.universal", ["gambatte_libretro.so", "Tetris.gb"])
        assert runner.fake_root.fake_path("/mnt/SDCARD/RetroArch/IGM.txt").exists()
    finally:
        runner.cleanup()
