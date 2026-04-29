from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _run_task(runner: HarnessRunner, task_name: str):
    script = runner.fake_root.fake_str(f"/mnt/SDCARD/spruce/scripts/tasks/{task_name}")
    return runner.run(["/bin/sh", script], timeout=10)


def test_clear_favorites_and_recents_remove_pyui_state_and_restart_menu():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        favorites = runner.fake_root.write_real_path("/mnt/SDCARD/Saves/pyui-favorites.json", "[]\n")
        recents = runner.fake_root.write_real_path("/mnt/SDCARD/Saves/pyui-recents.json", "[]\n")

        result = _run_task(runner, "clearFavorites.sh")
        assert result.returncode == 0, result.stderr
        result = _run_task(runner, "clearRecents.sh")
        assert result.returncode == 0, result.stderr

        assert not favorites.exists()
        assert not recents.exists()
        assert runner.called("killall", ["MainUI"])
        log = runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce.log")
        assert "Favorites: Cleared by request of user." in log
        assert "Recents: Cleared by request of user." in log
    finally:
        runner.cleanup()


def test_clearwifi_resets_wpa_supplicant_and_cycles_wifi_processes():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        runner.fake_root.write_real_path(
            "/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf",
            "network={\n    ssid=\"old\"\n}\n",
        )

        result = _run_task(runner, "clearwifi.sh")

        assert result.returncode == 0, result.stderr
        wifi_config = runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf")
        assert "ctrl_interface=DIR=/var/run/wpa_supplicant" in wifi_config
        assert "update_config=1" in wifi_config
        assert "ssid=\"old\"" not in wifi_config
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf.tmp") == wifi_config
        assert runner.called("ifconfig", ["wlan0", "down"])
        assert runner.called("ifconfig", ["wlan0", "up"])
        assert runner.called("killall", ["wpa_supplicant"])
        assert runner.called("killall", ["udhcpc"])
    finally:
        runner.cleanup()


def test_reset_tasks_restore_emulator_configs_from_backups():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        fixtures = {
            "/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg.bak": "ra backup\n",
            "/mnt/SDCARD/Emu/NDS/config/drastic-Flip.cfg.bak": "nds backup\n",
            "/mnt/SDCARD/Emu/NDS/config/drastic.cf2.bak": "cf2 backup\n",
            "/mnt/SDCARD/Emu/NDS/resources/settings_Flip.json.bak": "{}\n",
            "/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg.bak": "pcsx backup\n",
            "/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/ppsspp-Flip.ini": "old ppsspp\n",
            "/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-Flip.ini": "old controls\n",
            "/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/ppsspp-Flip.ini": "ppsspp backup\n",
            "/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/controls-Flip.ini": "controls backup\n",
        }
        for path, content in fixtures.items():
            runner.fake_root.write_real_path(path, content)

        for task_name in ["resetRA.sh", "resetNDS.sh", "resetPCSXR.sh", "resetPPSSPP.sh"]:
            result = _run_task(runner, task_name)
            assert result.returncode == 0, result.stderr

        assert runner.fake_root.read_real_path("/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg") == "ra backup\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Emu/NDS/config/drastic-Flip.cfg") == "nds backup\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Emu/NDS/config/drastic.cf2") == "cf2 backup\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Emu/NDS/resources/settings_Flip.json") == "{}\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg") == "pcsx backup\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/ppsspp-Flip.ini") == "ppsspp backup\n"
        assert runner.fake_root.read_real_path("/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-Flip.ini") == "controls backup\n"
    finally:
        runner.cleanup()


def test_bug_report_collects_expected_logs_and_config_inputs():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        result = _run_task(runner, "bugReport.sh")

        assert result.returncode == 0, result.stderr
        assert runner.called("7zr", ["a", "bug_report.7z"])
        assert runner.called("7zr", ["Saves/*.json"])
        assert runner.called("7zr", ["Saves/spruce/*.log"])
        assert runner.called("7zr", ["RetroArch/.retroarch/logs"])
    finally:
        runner.cleanup()
