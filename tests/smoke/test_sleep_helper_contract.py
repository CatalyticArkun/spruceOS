from __future__ import annotations

import json

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _set_sleep_timer(runner: HarnessRunner, value: str) -> None:
    config = json.loads(runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce-config.json"))
    battery = config["menuOptions"].setdefault("Battery Settings", {})
    battery["shutdownFromSleep"] = {"selected": value}
    runner.fake_root.write_real_path(
        "/mnt/SDCARD/Saves/spruce/spruce-config.json",
        json.dumps(config, indent=2) + "\n",
    )


def test_sleep_helper_runs_bounded_fake_sleep_and_restores_runtime_state():
    runner = HarnessRunner(REPO_ROOT, "a30")
    try:
        _set_sleep_timer(runner, "5s")
        runner.fake_root.write_real_path("/sys/power/state", "\n")
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/sleep_helper.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 0, result.stderr
        assert runner.called("getevent")
        assert runner.called("hwclock")
        assert runner.called("killall", ["idlemon"])
        assert runner.called("idlemon_mm.sh")
        assert runner.fake_root.read_real_path("/sys/power/state").strip() == "mem"
        assert runner.fake_root.read_real_path("/sys/class/rtc/rtc0/wakealarm").strip() == "0"
        sleep_info = runner.fake_root.read_real_path("/tmp/sleep_timer_info")
        assert "TIMEOUT=5" in sleep_info
        assert runner.fake_root.fake_path("/tmp/audio_reinit_needed").exists()
        assert not runner.fake_root.fake_path("/tmp/sleep_helper_started").exists()
    finally:
        runner.cleanup()
