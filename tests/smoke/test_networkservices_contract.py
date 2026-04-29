from __future__ import annotations

import json

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def _enable_network_services(runner: HarnessRunner) -> None:
    config = json.loads(runner.fake_root.read_real_path("/mnt/SDCARD/Saves/spruce/spruce-config.json"))
    network = config["menuOptions"]["Network Settings"]
    network["enableSamba"]["selected"] = "True"
    network["enableSSH"]["selected"] = "True"
    network["enableSFTPGo"]["selected"] = "True"
    network["enableSyncthing"]["selected"] = "False"
    runner.fake_root.write_real_path(
        "/mnt/SDCARD/Saves/spruce/spruce-config.json",
        json.dumps(config, indent=2) + "\n",
    )


def test_networkservices_starts_enabled_services_and_landing_page():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _enable_network_services(runner)
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/networkservices.sh")

        result = runner.run(["/bin/sh", script], timeout=10)

        assert result.returncode == 0, result.stderr
        assert runner.called("smbpasswd")
        assert runner.called("smbd", ["-D"])
        assert runner.called("dropbearmulti", ["dropbear"])
        assert runner.called("sftpgo", ["serve"])
        assert runner.wait_called("darkhttpd")
        assert runner.called("killall", ["syncthing"])
    finally:
        runner.cleanup()


def test_networkservices_off_stops_running_service_processes():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        _enable_network_services(runner)
        script = runner.fake_root.fake_str("/mnt/SDCARD/spruce/scripts/networkservices.sh")

        start = runner.run(["/bin/sh", script], timeout=10)
        assert start.returncode == 0, start.stderr
        stop = runner.run(["/bin/sh", script, "off"], timeout=10)

        assert stop.returncode == 0, stop.stderr
        assert runner.called("killall", ["dropbearmulti"])
        assert runner.called("killall", ["darkhttpd"])
        assert runner.called("pgrep", ["smbd"])
    finally:
        runner.cleanup()
