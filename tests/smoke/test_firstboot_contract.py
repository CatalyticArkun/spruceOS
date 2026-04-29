from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _write_archive(runner: HarnessRunner, real_path: str) -> None:
    runner.fake_root.write_real_path(real_path, "fake archive\n")


def test_firstboot_extracts_planned_packages_and_runs_wrapup():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        runner.fake_root.write_real_path("/mnt/SDCARD/spruce/spruce", "4.0.0-test\n")
        _write_archive(runner, "/mnt/SDCARD/App/PortMaster/portmaster.7z")
        _write_archive(runner, "/mnt/SDCARD/Emu/SCUMMVM/scummvm_64.7z")
        _write_archive(runner, "/mnt/SDCARD/Emu/SCUMMVM/scummvm_extra.7z")
        _write_archive(runner, "/mnt/SDCARD/Emu/SCUMMVM/scummvm_theme.7z")
        _write_archive(runner, "/mnt/SDCARD/Emu/ARCADE/advmame.7z")
        _write_archive(runner, "/mnt/SDCARD/Themes/test-theme.7z")
        _write_archive(runner, "/mnt/SDCARD/spruce/archives/preMenu/test-pre-menu.7z")
        _write_archive(runner, "/mnt/SDCARD/spruce/archives/preCmd/test-pre-cmd.7z")
        runner.fake_root.write_real_path("/mnt/SDCARD/Roms/PICO8/.keep", "")
        runner.fake_root.write_real_path("/mnt/SDCARD/spruce/flags/first_boot_Flip.lock", "")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/firstboot.sh")

        result = runner.run(["/bin/sh", script], timeout=15)

        assert result.returncode == 0, result.stderr
        assert not runner.fake_root.fake_path("/tmp/firstboot_packages_extracting.lock").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/spruce/flags/first_boot_Flip.lock").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/App/PortMaster/portmaster.7z").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/Emu/SCUMMVM/scummvm_64.7z").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/Emu/SCUMMVM/scummvm_extra.7z").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/Emu/SCUMMVM/scummvm_theme.7z").exists()
        assert not runner.fake_root.fake_path("/mnt/SDCARD/Emu/ARCADE/advmame.7z").exists()
        assert runner.fake_root.fake_path("/mnt/SDCARD/Roms/PICO8").is_dir()
        assert any(path.suffix == ".splore" for path in runner.fake_root.fake_path("/mnt/SDCARD/Roms/PICO8").iterdir())
        assert runner.called("MainUI", ["msgDisplayRealtimePort", "50980"])
        assert runner.called("dropbearmulti", ["dropbearkey", "rsa"])
        assert runner.called("dropbearmulti", ["dropbearkey", "dss"])
        assert runner.called("python", ["compileall"])
        assert runner.called("system-emit", ["PACKAGE_PHASE_BEGIN"])
        assert runner.called("system-emit", ["PACKAGE_PHASE_END"])
        assert runner.called("system-emit", ["ARCHIVE_PLAN", "pre_menu_total=1", "pre_cmd_total=1"])
        assert runner.called("system-emit", ["process-finalize", "COMPLETE"])
        assert runner.fake_root.fake_path("/mnt/SDCARD/spruce/archives/preMenu/test-pre-menu.7z").exists()
        assert runner.fake_root.fake_path("/mnt/SDCARD/spruce/archives/preCmd/test-pre-cmd.7z").exists()

        archive_extracts = [
            call
            for call in runner.calls()
            if call["command"] == "7zr" and "x" in [str(arg) for arg in call.get("argv", [])]
        ]
        assert len(archive_extracts) == 6
    finally:
        runner.cleanup()
