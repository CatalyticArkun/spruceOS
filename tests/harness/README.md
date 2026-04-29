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

This harness branch must also never be used as a pull-request source branch.
Do not open PRs from `catalyticarkun/spruceos-harness` into `Development`,
`main`, `upstream/Development`, or any `spruceUI/spruceOS` branch. If harness
work needs review later, create a separate review branch and cherry-pick the
approved commits there.

This checkout uses a local `core.hooksPath=.githooks` setting and a pre-push hook
that rejects pushes to `upstream` or to the canonical `spruceUI/spruceOS` URL.
The hook also rejects pull-request style refs from this branch. The local
`upstream` push URL should remain set to a disabled placeholder.

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

Harness coverage report:

```sh
python3 tests/harness/report.py --format markdown
python3 tests/harness/report.py --format json
```

## Contract

Smoke tests should assert:

- exit code
- command ledger entries
- fake sysfs file changes
- fake `/tmp` flags
- fake config changes
- logs and `system-emit` calls

Current smoke coverage includes platform detection, Wi-Fi contracts, network
service start/stop behavior, archive unpacking, stage2 poweroff, standard
emulator launch, and layer gates.

Any test that writes to real device paths belongs in a separate, explicitly
approved live-device suite, not in this harness.
