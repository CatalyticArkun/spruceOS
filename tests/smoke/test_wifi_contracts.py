from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner


def test_flip_enable_wifi_uses_fake_radio_power_and_network_clients():
    runner = HarnessRunner(REPO_ROOT, "flip")
    try:
        result = runner.source_helper_and_run("enable_wifi")
        assert result.returncode == 0, result.stderr
        assert runner.fake_root.read_real_path("/sys/class/rkwifi/wifi_power").strip() == "1"
        assert runner.called("ifconfig", ["wlan0", "up"])
        assert runner.called("wpa_supplicant", ["wlan0"])
        assert runner.called("udhcpc", ["wlan0"])
    finally:
        runner.cleanup()


def test_brick_device_exit_sleep_reloads_xradio_in_fake_root():
    runner = HarnessRunner(REPO_ROOT, "brick")
    try:
        runner.fake_root.write_real_path("/tmp/wifi_on", "\n")
        result = runner.source_helper_and_run("device_exit_sleep")
        assert result.returncode == 0, result.stderr
        assert runner.called("modprobe", ["xradio_wlan"])
        assert runner.called("ip", ["link", "show", "wlan0"])
        assert runner.called("wpa_supplicant", ["wlan0"])
    finally:
        runner.cleanup()
