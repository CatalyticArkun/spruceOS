# Power Transition Trace Architecture

## Event model

Spruce now emits structured power-transition events into a bounded JSONL stream (`Saves/spruce/power/events.jsonl`) through `spruce/scripts/power_trace.sh`.

Implemented event types:
- `BOOT_BEGIN`
- `BOOT_COMPLETE`
- `SHUTDOWN_BEGIN`
- `SHUTDOWN_HANDOFF`
- `SHUTDOWN_COMPLETE`
- `REBOOT_BEGIN`
- `SLEEP_PREPARE_BEGIN`
- `SLEEP_PREPARE_COMPLETE`
- `SLEEP_REQUESTED`
- `SLEEP_ENTER_BEGIN`
- `SLEEP_ENTER_COMPLETE`
- `WAKE_DETECTED`
- `WAKE_RESUME_BEGIN`
- `WAKE_RESUME_COMPLETE`
- `TRANSITION_ABORTED`
- `TRANSITION_TIMEOUT`
- `INVALID_TRANSITION`
- `POWER_ERROR`
- `UNKNOWN_TRANSITION`

Each event stores monotonic and wall time, boot/session ID, correlation ID, target platform, build version, intended/observed state fields, trigger context, source function/module, timeout/error fields, and target capability notes.


`SHUTDOWN_HANDOFF`
Indicates SpruceOS completed its shutdown tasks and handed control
to the platform shutdown mechanism. The device may still still be
in the process of powering off.

## State model

`power_trace.sh` tracks:
- requested state
- intended state
- observed state
- completed state
- last known state
- active transition correlation id

State is persisted in `Saves/spruce/power/state.env` so interrupted sessions remain diagnosable. Pending transitions are tracked in `pending.env` and reconciled on next boot.

### Resilience behavior
- Unsupported events are rewritten to `UNKNOWN_TRANSITION`.
- Invalid event ordering auto-emits `INVALID_TRANSITION`.
- Interrupted transitions are surfaced via `TRANSITION_ABORTED` / `POWER_ERROR` / boot reconciliation (`UNKNOWN_TRANSITION`, inferred `SHUTDOWN_COMPLETE`).
- All storage is bounded via ring trimming (`events.jsonl` and `summary.txt`).

## Common vs target-specific layers

### Common layer
- `spruce/scripts/power_trace.sh` is the unified schema, correlation logic, transition validation, and ring storage layer.
- Emission points currently integrated in:
  - `runtime.sh` (boot begin/complete + pending reconciliation)
  - `save_poweroff.sh` (shutdown/reboot begin + duplicate/incomplete handling)
  - `sleep_helper.sh` (sleep prepare/request/entry/wake/resume/error/timeout)
  - `power_button_watchdog_v2.sh` (sleep and long-press shutdown intents)
  - `runtimeHelper.sh` (autoresume lifecycle markers)

### Target adapters
Target differences are exposed via adapter hooks:
- `device_power_trace_capabilities`
- `device_power_trace_notes`

Default no-op implementations are in `platform/device.sh`, with current overrides in:
- `platform/device_functions/MiyooMini.sh`
- `platform/device_functions/A30.sh`
- `platform/device_functions/trimui_a133p.sh`

This preserves visibility into platform capability gaps instead of hiding them.

## Diagnostics export path

Power traces are integrated into the diagnostics pipeline:
- `diagnostics/runner.sh` copies power trace raw and summary artifacts into run outputs.
- `diagnostics/write_telemetry.sh` now includes power trace event count and recent summary lines in telemetry payload.

## Failure handling and limitations

- `SHUTDOWN_COMPLETE` cannot always be observed directly on all targets; when unavailable it is inferred on next boot using pending-transition reconciliation.
- Wake source is only as accurate as target capabilities/signals.
- On devices without reliable RTC/lid/PM signals, traces include explicit capability notes to avoid false certainty.
