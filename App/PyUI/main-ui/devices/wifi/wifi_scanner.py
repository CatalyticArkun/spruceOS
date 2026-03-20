import subprocess
import time
import threading
from dataclasses import dataclass
from typing import List, Set

from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from utils.logger import PyUiLogger


@dataclass
class WiFiNetwork:
    bssid: str
    frequency: int
    signal_level: int
    flags: str
    ssid: str

    def requires_password(self) -> bool:
        return "WPA" in self.flags or "WEP" in self.flags


class WiFiScanner:
    WPA_CLI_TIMEOUT_SECONDS = 5
    STATUS_TIMEOUT_SECONDS = 2

    def __init__(self, interface="wlan0", delay=2):
        self.interface = interface
        self.delay = delay

        # Thread state
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._pause_event = threading.Event()
        self._pause_ack_event = threading.Event()
        self._worker_lock = threading.Lock()
        self._active_scan_calls = 0

        # Shared scan results
        self._lock = threading.Lock()
        self._known_ssids: Set[str] = set()
        self._known_bssids: Set[str] = set()
        self._networks: List[WiFiNetwork] = []
        self._connected_lock = threading.Lock()
        self._connected_ssid: str | None = None
        self._connected_freq: int | None = None
        self._last_status_update = 0.0

    # ----------------------------
    # Worker thread
    # ----------------------------

    def _scan_worker(self):
        log = PyUiLogger.get_logger()
        log.info("WiFi scan thread started")

        while not self._stop_event.is_set():
            if self._pause_event.is_set():
                self._pause_ack_event.set()
                self._stop_event.wait(0.1)
                continue
            self._pause_ack_event.clear()

            try:
                self._scan_once_internal()
            except Exception:
                log.exception("WiFi scan worker error")

            # Cooperative sleep so stop() reacts immediately
            self._stop_event.wait(self.delay)

        log.info("WiFi scan thread stopped")

    def _scan_once_internal(self):
        """
        Runs inside worker thread only.
        """
        log = PyUiLogger.get_logger()

        result = self._run_scan_command(["wpa_cli", "-i", self.interface, "scan"])
        if result is None:
            return
        if result.returncode != 0 or "FAIL" in result.stdout.upper():
            log.warning(
                f"WiFi scan failed: rc={result.returncode}, stdout={result.stdout.strip()}, stderr={result.stderr.strip()}"
            )
        if "Failed to connect to" in result.stderr:
            log.error("wlan0 seems broken, restarting and retrying")
            Device.get_device().wifi_error_detected()
            time.sleep(15)
            retry_result = self._run_scan_command(["wpa_cli", "-i", self.interface, "scan"])
            if retry_result is None:
                return
            if retry_result.returncode != 0 or "FAIL" in retry_result.stdout.upper():
                log.warning(
                    f"WiFi scan retry failed: rc={retry_result.returncode}, "
                    f"stdout={retry_result.stdout.strip()}, stderr={retry_result.stderr.strip()}"
                )
                return

        # Let wpa_supplicant populate results
        if self._stop_event.wait(self.delay) or self._pause_event.is_set():
            return

        result = self._run_scan_command(["wpa_cli", "-i", self.interface, "scan_results"])
        if result is None:
            return
        if result.returncode != 0 or "FAIL" in result.stdout.upper():
            log.warning(
                f"WiFi scan results failed: rc={result.returncode}, stdout={result.stdout.strip()}, stderr={result.stderr.strip()}"
            )
            return
        lines = result.stdout.strip().splitlines()

        new_networks: List[WiFiNetwork] = []

        for line in lines[1:]:  # Skip header
            parts = line.strip().split("\t")
            if len(parts) < 5:
                continue

            bssid, freq, signal, flags, ssid = parts[:5]

            try:
                network = WiFiNetwork(
                    bssid=bssid,
                    frequency=int(freq),
                    signal_level=int(signal),
                    flags=flags,
                    ssid=ssid,
                )
            except ValueError:
                continue

            new_networks.append(network)

        # Merge uniquely seen networks
        with self._lock:
            for net in new_networks:
                if net.bssid not in self._known_bssids:
                    self._known_bssids.add(net.bssid)
                    self._known_ssids.add(net.ssid)
                    self._networks.append(net)

    # ----------------------------
    # Public API
    # ----------------------------

    def scan_networks(self) -> List[WiFiNetwork]:
        """
        Non-blocking.
        Starts the worker thread if not already running and
        returns currently known networks immediately.
        """
        if not self._thread or not self._thread.is_alive():
            self._start_thread()

        with self._lock:
            # Return a snapshot copy
            return list(self._networks)

    def _start_thread(self):
        PyUiLogger.get_logger().info("Starting WiFi scan thread")
        self._stop_event.clear()
        self._pause_event.clear()
        self._thread = threading.Thread(
            target=self._scan_worker,
            name="WiFiScannerThread",
            daemon=True,
        )
        self._thread.start()

    def _run_scan_command(self, args):
        with self._worker_lock:
            self._active_scan_calls += 1
            self._pause_ack_event.clear()
        try:
            return ProcessRunner.run(
                args,
                timeout=self.WPA_CLI_TIMEOUT_SECONDS
            )
        finally:
            with self._worker_lock:
                self._active_scan_calls -= 1
                if self._pause_event.is_set() and self._active_scan_calls == 0:
                    self._pause_ack_event.set()

    def pause(self, wait=False, timeout=None):
        PyUiLogger.get_logger().info("Pausing WiFi scan thread")
        self._pause_event.set()
        if not wait:
            return True

        if not self._thread or not self._thread.is_alive():
            self._pause_ack_event.set()
            return True

        with self._worker_lock:
            if self._active_scan_calls == 0:
                self._pause_ack_event.set()

        return self._pause_ack_event.wait(timeout)

    def resume(self):
        PyUiLogger.get_logger().info("Resuming WiFi scan thread")
        self._pause_event.clear()
        self._pause_ack_event.clear()

    def stop(self):
        """
        Stops the worker thread and clears scanned networks.
        """
        log = PyUiLogger.get_logger()
        log.info("Stopping WiFi scan thread")
        self._stop_event.set()
        self._pause_event.clear()
        self._pause_ack_event.set()

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

        self._thread = None

        with self._lock:
            self._known_ssids.clear()
            self._known_bssids.clear()
            self._networks.clear()

    # ----------------------------
    # Other helpers (unchanged)
    # ----------------------------

    def get_connected_ssid(self):
        now = time.monotonic()
        with self._connected_lock:
            if now - self._last_status_update < 1:
                return self._connected_ssid, self._connected_freq

        ssid = None
        freq = None
        try:
            result = ProcessRunner.run(
                ["wpa_cli", "status"],
                timeout=self.STATUS_TIMEOUT_SECONDS
            )
            if result.returncode != 0:
                PyUiLogger.get_logger().warning(
                    f"Failed to get Wi-Fi details: rc={result.returncode}, stderr={result.stderr.strip()}"
                )
            else:
                for line in result.stdout.splitlines():
                    if line.startswith("ssid="):
                        ssid = line.split("=", 1)[1]
                    elif line.startswith("freq="):
                        freq = int(line.split("=", 1)[1])
                with self._connected_lock:
                    self._connected_ssid = ssid
                    self._connected_freq = freq
                    self._last_status_update = now
        except subprocess.TimeoutExpired:
            PyUiLogger.get_logger().warning("Timed out getting Wi-Fi details")
        with self._connected_lock:
            if ssid is None and freq is None:
                return self._connected_ssid, self._connected_freq

        return ssid, freq
