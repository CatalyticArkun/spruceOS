from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def test_stage2_poweroff_uses_ledgered_unmount_and_reboot_commands():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/save_poweroff_stage2.sh")
        result = runner.run(["/bin/sh", script, "--reboot"])
        assert result.returncode == 0, result.stderr
        assert runner.called("sync")
        assert runner.called("mount", ["remount,ro"])
        assert runner.called("umount", [runner.fake_root.fake_str("/mnt/sdcard")])
        assert runner.called("reboot")
    finally:
        runner.cleanup()
