from __future__ import annotations

import json

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _set_boot_action(runner: HarnessRunner, value: str) -> None:
    config = json.loads(runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce-config.json"))
    system = config["menuOptions"].setdefault("System Settings", {})
    system["bootTo"] = {"selected": value}
    runner.fake_root.write_real_path(
        "/mnt/SDCARD/Saves/spruce/spruce-config.json",
        json.dumps(config, indent=2) + "\n",
    )


def test_runtime_helper_boot_action_random_game_stages_command():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_boot_action(runner, "Random Game")
        runtime_helper = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/runtimeHelper.sh")

        result = runner.source_helper_and_run(f'. "{runtime_helper}"; set_up_boot_action')

        assert result.returncode == 0, result.stderr
        staged = runner.fake_root.read_real_path("/tmp/cmd_to_run.sh")
        assert "App/RandomGame/random.sh" in staged
    finally:
        runner.cleanup()


def test_runtime_helper_boot_action_splore_requires_pico8_binaries():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _set_boot_action(runner, "Splore")
        runner.fake_root.write_real_path("/mnt/SDCARD/BIOS/pico8.dat", "fake\n")
        runner.fake_root.write_real_path("/mnt/SDCARD/BIOS/pico8_64", "fake\n")
        runtime_helper = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/runtimeHelper.sh")

        result = runner.source_helper_and_run(f'. "{runtime_helper}"; set_up_boot_action')

        assert result.returncode == 0, result.stderr
        staged = runner.fake_root.read_real_path("/tmp/cmd_to_run.sh")
        assert "Roms/PICO8" in staged
        assert "standard_launch.sh" in staged
    finally:
        runner.cleanup()


def test_runtime_helper_auto_resume_stages_lastgame_once():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        lastgame = '"/mnt/SDCARD/Emu/GB/../../spruce/scripts/emu/standard_launch.sh" "/mnt/SDCARD/Roms/GB/Tetris.gb"\n'
        runner.fake_root.write_real_path("/mnt/SDCARD/spruce/flags/lastgame.lock", lastgame)
        runtime_helper = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/runtimeHelper.sh")

        result = runner.source_helper_and_run(f'. "{runtime_helper}"; auto_resume_game')

        assert result.returncode == 0, result.stderr
        assert "Tetris.gb" in runner.fake_root.read_real_path("/tmp/cmd_to_run.sh")
        assert runner.fake_root.fake_path("/tmp/autoresume_staged.lock").exists()
        assert runner.called("MainUI", ["-startupInitOnly"])
        assert runner.called("sync")
    finally:
        runner.cleanup()
