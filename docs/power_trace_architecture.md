# Power Trace Architecture

## Core Model

Tracing is now a passive overlay implemented by `spruce/scripts/trace.sh`. The canonical emit contract is:

`system-emit <subsystem> <current state> <requested state> <source> <brief context>`

For sourced shell code, the equivalent helper is `system_emit "$subsystem" "$current_state" "$requested_state" "$source" "$context"`.

`spruce/scripts/trace.sh` is now only a passive recorder behind that emit contract. It does not validate transitions at runtime. `spruce/scripts/power_trace.sh` remains only as a legacy compatibility shim for older source paths.

## Storage Model

Every emit is written to:

- `Saves/spruce/trace/events.jsonl`
- `Saves/spruce/trace/summary.txt`

And mirrored into subsystem-local logs:

- `Saves/spruce/power/events.jsonl`
- `Saves/spruce/networking/events.jsonl`
- `Saves/spruce/audio/events.jsonl`
- `Saves/spruce/brightness/events.jsonl`

Each record stores:

- `subsystem`
- `current_state`
- `requested_state`
- `source`
- `context`
- monotonic and wall time
- boot/session id
- platform
- build

The global sequence counter lives in `Saves/spruce/trace/state.env`.

## Flow Ownership

Power flow is owned by the firmware/runtime scripts themselves:

- `power_mode.sh` owns lifecycle gating and shutdown/sleep ownership
- `runtime.sh`, `sleep_helper.sh`, `save_poweroff.sh`, `power_button_watchdog_v2.sh`, `principal.sh`, and `runtimeHelper.sh` emit observations
- the power trace layer only records those observations; state-machine validation is deferred to the tracker-local verifier in `spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh`

That separation is the main contract change in the bridge.

## Subsystem Coverage

### Power

Important milestones currently emit passive records for:

- boot start
- boot ready
- short-press sleep request and suppression
- sleep prepare / enter
- wake detect / resume
- shutdown request
- shutdown handoff
- reboot request
- shutdown/autoresume/boot-action suppression

### Networking

The framework now records:

- Wi-Fi enable/disable requests and completion
- DHCP/connectivity attempts
- connectivity verification / timeout / cancellation
- service orchestration in `networkservices.sh`

### Audio

The framework now records:

- volume changes through device `set_volume()` implementations
- wake restore / sleep mute context via caller-supplied source/context
- deliberate no-op ownership cases on Miyoo Mini variants

### Brightness

The framework now records:

- backlight changes through device `set_backlight()` implementations on supported targets

## Diagnostics Integration

Diagnostics now treat tracing as exported evidence, not control state:

- `diagnostics/runner.sh` captures `power`, `networking`, `audio`, and `brightness` trace artifacts
- telemetry still summarizes the power trace stream for boot/sleep/shutdown debugging
- `GEN-04-power-trace-health.sh` keeps the on-device check lightweight by validating passive record shape and summary presence only
- tracker-local state-machine verification is performed after export with `spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh`
- `collectors.d/10_runtime_state.sh` keeps `power_mode.state` and `/tmp` lifecycle markers for side-by-side review with exported traces

## Remaining Limits

- There is still no dedicated reboot-handoff milestone; reboot visibility stops at the request emit and resumes on the next boot.
- Trace quality is only as strong as the surrounding shell code’s source/context strings.
- Abrupt power loss can still drop the last few records because the layer intentionally does not add durable handoff state or recovery logic.
