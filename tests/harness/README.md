# spruceOS Harness

This harness is intentionally separate from the active `spruceOS` checkout. It
tests copied scripts inside a fake device root and records external program
calls through shims, so smoke tests can exercise shell flow without calling the
host or device system surfaces by accident.

## Layers

- `host-sim`: default. Runs on the development host with a fake root under
  `/tmp`, rewritten script copies, command shims, command ledger assertions, and
  profile fixtures.
- `device-sim`: same fake-root and shim model, but intended to run on the
  handheld itself. It is still non-destructive and must not write real `/sys`,
  `/proc`, `/dev`, `/mnt/SDCARD`, or `/tmp` paths outside the fake root.
- `device-surface`: opt-in read-only probes against actual device surfaces.
  These tests are gated and should only observe safe paths or safe commands.

## Remote Safety

This harness branch must never be pushed to `upstream`. The `upstream` remote is
receive-only for pulling updates from `spruceUI/spruceOS`; all harness work must
push to `origin`, the `CatalyticArkun/spruceOS` fork.

This checkout uses a local `core.hooksPath=.githooks` setting and a pre-push hook
that rejects pushes to `upstream` or to the canonical `spruceUI/spruceOS` URL.
The local `upstream` push URL should also remain set to a disabled placeholder.

## Running

Host simulated smoke tests:

```sh
python3 -m pytest tests/smoke -m "not device_surface"
```

On-device simulated smoke tests:

```sh
SPRUCE_HARNESS_ALLOW_DEVICE_SIM=1 python3 -m pytest tests/smoke -m "not device_surface"
```

Actual device surface probes:

```sh
SPRUCE_HARNESS_ALLOW_DEVICE_SURFACE=1 python3 -m pytest tests/smoke -m device_surface
```

## Contract

Smoke tests should assert:

- exit code
- command ledger entries
- fake sysfs file changes
- fake `/tmp` flags
- fake config changes
- logs and `system-emit` calls

Any test that writes to real device paths belongs in a separate, explicitly
approved live-device suite, not in this harness.
