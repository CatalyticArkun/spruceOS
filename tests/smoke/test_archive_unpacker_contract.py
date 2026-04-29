from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def test_archive_unpacker_silent_precmd_extracts_and_clears_flags():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        archive = runner.fake_root.write_real_path(
            "/mnt/SDCARD/spruce/archives/preCmd/harness.7z",
            "fake archive\n",
        )
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh")

        result = runner.run(["/bin/sh", script, "--silent", "pre_cmd"], timeout=10)

        assert result.returncode == 0, result.stderr
        assert runner.called("7zr", ["l", "harness.7z"])
        assert runner.called("7zr", ["x", "harness.7z"])
        assert not archive.exists()
        assert not runner.fake_root.fake_path("/tmp/pre_cmd_unpacking.lock").exists()
        state = runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/unpacker_state")
        assert "state=complete" in state
        assert "run_mode=pre_cmd" in state
    finally:
        runner.cleanup()
