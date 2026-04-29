from __future__ import annotations

import os
import stat
from pathlib import Path


SHIMMED_COMMANDS = {
    "7zr",
    "alsactl",
    "amixer",
    "bluealsa",
    "bluetoothctl",
    "curl",
    "darkhttpd",
    "dhclient",
    "dropbearmulti",
    "getevent",
    "hciconfig",
    "hwclock",
    "idlemon",
    "idlemon_mm.sh",
    "ifconfig",
    "ip",
    "jq",
    "kill",
    "killall",
    "modprobe",
    "mount",
    "pgrep",
    "pidof",
    "ping",
    "poweroff",
    "ra32.universal",
    "ra32.a30",
    "ra32.mini",
    "ra64.universal",
    "ra64.pixel2",
    "reboot",
    "rmmod",
    "sendevent",
    "sftpgo",
    "sleep",
    "smbpasswd",
    "smbd",
    "sync",
    "syncthing",
    "systemctl",
    "udhcpc",
    "umount",
    "wget",
    "wpa_supplicant",
    "xradio",
}

PASSTHROUGH_COMMANDS = {
    "awk",
    "basename",
    "cat",
    "chmod",
    "cp",
    "cut",
    "date",
    "dirname",
    "find",
    "grep",
    "head",
    "ln",
    "ls",
    "mkdir",
    "mktemp",
    "mv",
    "printf",
    "readlink",
    "rm",
    "sed",
    "sort",
    "tail",
    "tee",
    "test",
    "touch",
    "tr",
    "wc",
}


class CommandShims:
    def __init__(self, fake_root: Path):
        self.fake_root = Path(fake_root)
        self.state_dir = self.fake_root / "harness"
        self.dispatcher = self.state_dir / "shim_dispatch.py"
        self.bin_dir = self.state_dir / "bin"

    def install(self) -> "CommandShims":
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        self._write_dispatcher()
        self._install_command_bins()
        self._install_direct_binary_wrappers()
        return self

    def env(self) -> dict[str, str]:
        bins = [
            self.bin_dir,
            self.fake_root / "usr/bin",
            self.fake_root / "usr/sbin",
            self.fake_root / "bin",
            self.fake_root / "sbin",
        ]
        return {
            "SPRUCE_HARNESS_FAKE_ROOT": str(self.fake_root),
            "SPRUCE_HARNESS_CALLS": str(self.state_dir / "calls.jsonl"),
            "SPRUCE_HARNESS_PROCESSES": str(self.state_dir / "processes.json"),
            "SPRUCE_HARNESS_POWER_ACTION": str(self.state_dir / "power_action"),
            "PATH": os.pathsep.join(str(path) for path in bins) + os.pathsep + os.environ.get("PATH", ""),
        }

    def _write_dispatcher(self) -> None:
        self.dispatcher.write_text(DISPATCHER_SOURCE)
        self.dispatcher.chmod(0o755)

    def _install_command_bins(self) -> None:
        command_dirs = [
            self.bin_dir,
            self.fake_root / "usr/bin",
            self.fake_root / "usr/sbin",
            self.fake_root / "bin",
            self.fake_root / "sbin",
        ]
        for directory in command_dirs:
            directory.mkdir(parents=True, exist_ok=True)
            for command in SHIMMED_COMMANDS:
                self._write_wrapper(directory / command, command)
            for command in PASSTHROUGH_COMMANDS:
                target = directory / command
                if target.exists():
                    continue
                host = Path("/usr/bin") / command
                if host.exists():
                    target.symlink_to(host)

    def _install_direct_binary_wrappers(self) -> None:
        direct_commands = {
            "/mnt/SDCARD/RetroArch/ra32.universal": "ra32.universal",
            "/mnt/SDCARD/RetroArch/ra32.a30": "ra32.a30",
            "/mnt/SDCARD/RetroArch/ra32.mini": "ra32.mini",
            "/mnt/SDCARD/RetroArch/ra64.universal": "ra64.universal",
            "/mnt/SDCARD/RetroArch/ra64.pixel2": "ra64.pixel2",
            "/mnt/SDCARD/spruce/bin/Samba/bin/smbpasswd": "smbpasswd",
            "/mnt/SDCARD/spruce/bin/Samba/bin/smbd": "smbd",
            "/mnt/SDCARD/spruce/bin64/Samba/bin/smbpasswd": "smbpasswd",
            "/mnt/SDCARD/spruce/bin64/Samba/bin/smbd": "smbd",
            "/mnt/SDCARD/spruce/bin/SSH/bin/dropbearmulti": "dropbearmulti",
            "/mnt/SDCARD/spruce/bin/SFTPGo/sftpgo/sftpgo": "sftpgo",
            "/mnt/SDCARD/spruce/bin64/SFTPGo/sftpgo/sftpgo": "sftpgo",
            "/mnt/SDCARD/spruce/bin/Syncthing/bin/syncthing": "syncthing",
            "/mnt/SDCARD/spruce/bin64/Syncthing/bin/syncthing": "syncthing",
            "/mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh": "idlemon_mm.sh",
            "/mnt/SDCARD/App/PyUI/launch.sh": "MainUI",
            "/usr/trimui/osd/show_volume_msg.sh": "show_volume_msg.sh",
            "/usr/libexec/bluetooth/bluetoothd": "bluetoothd",
            "/etc/bluetooth/bluetoothd": "bluetoothd",
        }
        for real_path, command in direct_commands.items():
            mapped = self._map_real_path(real_path)
            mapped.parent.mkdir(parents=True, exist_ok=True)
            self._write_wrapper(mapped, command)

    def _write_wrapper(self, path: Path, command: str) -> None:
        path.write_text(
            "#!/bin/sh\n"
            f'exec "{os.environ.get("PYTHON", "python3")}" "{self.dispatcher}" "{command}" "$@"\n'
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _map_real_path(self, real_path: str) -> Path:
        mapping = {
            "/mnt/SDCARD": "mnt/SDCARD",
            "/usr": "usr",
            "/etc": "etc",
        }
        for prefix, relative in sorted(mapping.items(), key=lambda item: len(item[0]), reverse=True):
            if real_path == prefix:
                return self.fake_root / relative
            if real_path.startswith(prefix + "/"):
                return self.fake_root / relative / real_path[len(prefix) + 1 :]
        raise ValueError(real_path)


DISPATCHER_SOURCE = r'''#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(os.environ["SPRUCE_HARNESS_FAKE_ROOT"])
CALLS = Path(os.environ["SPRUCE_HARNESS_CALLS"])
PROCESSES = Path(os.environ["SPRUCE_HARNESS_PROCESSES"])
POWER_ACTION = Path(os.environ["SPRUCE_HARNESS_POWER_ACTION"])


def record(command, argv, exit_code=0, stdout="", stderr="", stdin=""):
    CALLS.parent.mkdir(parents=True, exist_ok=True)
    with CALLS.open("a") as handle:
        handle.write(json.dumps({
            "command": command,
            "argv": argv,
            "cwd": os.getcwd(),
            "exit": exit_code,
            "stdout": stdout,
            "stderr": stderr,
            "stdin": stdin,
        }, sort_keys=True) + "\n")


def load_processes():
    if not PROCESSES.exists():
        return {}
    try:
        return json.loads(PROCESSES.read_text() or "{}")
    except json.JSONDecodeError:
        return {}


def save_processes(processes):
    PROCESSES.write_text(json.dumps(processes, indent=2, sort_keys=True) + "\n")


def add_process(name, argv):
    processes = load_processes()
    pid = str(2000 + len(processes) + 1)
    processes[pid] = {"name": name, "cmdline": " ".join([name] + argv)}
    save_processes(processes)
    return pid


def remove_matching(pattern):
    processes = load_processes()
    kept = {
        pid: proc for pid, proc in processes.items()
        if pattern not in proc.get("name", "") and pattern not in proc.get("cmdline", "")
    }
    changed = len(kept) != len(processes)
    save_processes(kept)
    return changed


def find_processes(pattern, full=False):
    matches = []
    for pid, proc in load_processes().items():
        haystack = proc.get("cmdline", "") if full else proc.get("name", "")
        if pattern in haystack:
            matches.append(pid)
    return matches


def print_and_exit(command, argv, code=0, stdout="", stderr=""):
    record(command, argv, code, stdout, stderr)
    if stdout:
        sys.stdout.write(stdout)
    if stderr:
        sys.stderr.write(stderr)
    raise SystemExit(code)


def fake_jq(command, argv):
    host_jq = shutil.which("jq", path="/usr/bin:/bin:/usr/local/bin")
    if host_jq and os.environ.get("SPRUCE_HARNESS_FORCE_FAKE_JQ") != "1":
        completed = subprocess.run([host_jq] + argv, text=True)
        record(command, argv, completed.returncode)
        raise SystemExit(completed.returncode)

    raw = False
    exists_mode = False
    args = list(argv)
    while args and args[0].startswith("-"):
        flag = args.pop(0)
        raw = raw or "r" in flag
        exists_mode = exists_mode or "e" in flag
    if len(args) < 2:
        print_and_exit(command, argv, 2, stderr="fake jq: unsupported arguments\n")
    expr, path = args[0], Path(args[-1])
    try:
        data = json.loads(path.read_text())
    except Exception:
        print_and_exit(command, argv, 1)
    default = None
    if " // " in expr:
        expr, default_expr = expr.split(" // ", 1)
        default = default_expr.strip().strip('"')
    try:
        value = resolve_json_expr(data, expr)
    except KeyError:
        value = default
    if exists_mode:
        print_and_exit(command, argv, 0 if value is not None else 1)
    if value is None:
        value = "null"
    elif isinstance(value, bool):
        value = "true" if value else "false"
    elif not raw:
        value = json.dumps(value)
    else:
        value = str(value)
    print_and_exit(command, argv, 0, value + "\n")


def resolve_json_expr(data, expr):
    expr = expr.strip()
    if expr == "empty":
        return ""
    if not expr.startswith("."):
        raise KeyError(expr)
    tokens = []
    current = ""
    in_quote = False
    index = 1
    while index < len(expr):
        char = expr[index]
        if char == '"':
            in_quote = not in_quote
        elif char == "." and not in_quote:
            if current:
                tokens.append(current.strip('"'))
                current = ""
        elif char == "[":
            if current:
                tokens.append(current.strip('"'))
                current = ""
            end = expr.index("]", index)
            key = expr[index + 1:end].strip().strip('"')
            if key.startswith("$"):
                raise KeyError(expr)
            tokens.append(key)
            index = end
        else:
            current += char
        index += 1
    if current:
        tokens.append(current.strip('"'))
    value = data
    for token in tokens:
        if token == "":
            continue
        if not isinstance(value, dict) or token not in value:
            raise KeyError(token)
        value = value[token]
    return value


def main():
    command = sys.argv[1]
    argv = sys.argv[2:]

    if command in {"sleep", "sync", "modprobe", "rmmod", "systemctl", "hciconfig", "bluealsa", "bluetoothctl", "dhclient", "xradio", "alsactl", "smbpasswd"}:
        print_and_exit(command, argv)

    if command == "hwclock":
        print_and_exit(command, argv, stdout="Sat Jan 10 14:23:54 2026  0.000000 seconds\n")

    if command == "amixer":
        print_and_exit(command, argv, stdout="Front Left: 10 [50%]\n")

    if command in {"reboot", "poweroff"}:
        POWER_ACTION.write_text(command + "\n")
        print_and_exit(command, argv)

    if command == "mount":
        if not argv:
            mounts = ROOT / "proc/mounts"
            print_and_exit(command, argv, stdout=mounts.read_text() if mounts.exists() else "")
        print_and_exit(command, argv)

    if command == "umount":
        print_and_exit(command, argv)

    if command == "ifconfig":
        if argv and argv[0] == "wlan0":
            if os.environ.get("SPRUCE_HARNESS_WIFI_CONNECTED", "1") == "1":
                print_and_exit(command, argv, stdout="wlan0 Link encap:Ethernet\n          inet addr:192.168.1.22\n")
            print_and_exit(command, argv, stdout="wlan0 Link encap:Ethernet\n")
        print_and_exit(command, argv)

    if command == "ip":
        if "wlan0" in argv:
            if os.environ.get("SPRUCE_HARNESS_WLAN0_PRESENT", "1") == "1":
                print_and_exit(command, argv, stdout="3: wlan0: <BROADCAST,MULTICAST,UP> mtu 1500\n")
            print_and_exit(command, argv, 1)
        print_and_exit(command, argv)

    if command in {"wpa_supplicant", "udhcpc", "darkhttpd", "syncthing", "smbd", "sftpgo", "dropbearmulti", "idlemon", "idlemon_mm.sh", "ra32.universal", "ra32.a30", "ra32.mini", "ra64.universal", "ra64.pixel2", "MainUI", "bluetoothd"}:
        add_process(command, argv)
        print_and_exit(command, argv)

    if command == "pgrep":
        args = list(argv)
        full = False
        if args and args[0] == "-f":
            full = True
            args.pop(0)
        pattern = args[-1] if args else ""
        matches = find_processes(pattern, full=full)
        print_and_exit(command, argv, 0 if matches else 1, "".join(pid + "\n" for pid in matches))

    if command == "pidof":
        pattern = argv[-1] if argv else ""
        matches = find_processes(pattern)
        print_and_exit(command, argv, 0 if matches else 1, " ".join(matches) + ("\n" if matches else ""))

    if command == "killall":
        targets = [arg for arg in argv if not arg.startswith("-")]
        for target in targets:
            remove_matching(target)
        print_and_exit(command, argv)

    if command == "kill":
        processes = load_processes()
        for target in [arg for arg in argv if not arg.startswith("-")]:
            processes.pop(target, None)
        save_processes(processes)
        print_and_exit(command, argv)

    if command == "sendevent":
        stdin = sys.stdin.read()
        record(command, argv, stdin=stdin)
        raise SystemExit(0)

    if command == "getevent":
        lines = os.environ.get("SPRUCE_HARNESS_GETEVENT_LINES", "")
        print_and_exit(command, argv, stdout=lines)

    if command == "ping":
        print_and_exit(command, argv, 0, "64 bytes from github.com: icmp_seq=1 ttl=56 time=1.0 ms\n")

    if command in {"curl", "wget"}:
        print_and_exit(command, argv, 0, "{}\n")

    if command == "7zr":
        if argv and argv[0] == "l":
            print_and_exit(command, argv, 0, str(ROOT / "mnt/SDCARD/fake-content") + "\n")
        print_and_exit(command, argv)

    if command == "jq":
        fake_jq(command, argv)

    if command == "system-emit":
        print_and_exit(command, argv)

    record(command, argv, 127, stderr=f"unhandled harness command: {command}\n")
    sys.stderr.write(f"unhandled harness command: {command}\n")
    raise SystemExit(127)


if __name__ == "__main__":
    main()
'''
