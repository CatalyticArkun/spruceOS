# Using Power Traces

## Where traces live

Primary files:

- `Saves/spruce/trace/events.jsonl`
- `Saves/spruce/trace/summary.txt`
- `Saves/spruce/power/events.jsonl`
- `Saves/spruce/power/summary.txt`

Related subsystem logs:

- `Saves/spruce/networking/events.jsonl`
- `Saves/spruce/audio/events.jsonl`
- `Saves/spruce/brightness/events.jsonl`

Diagnostics bundle integration:

- `diag/runs/<run>/raw/power_trace.events.jsonl`
- `diag/runs/<run>/summary/power_trace.summary.txt`
- `diag/runs/<run>/raw/networking_trace.events.jsonl`
- `diag/runs/<run>/summary/networking_trace.summary.txt`
- `diag/runs/<run>/raw/audio_trace.events.jsonl`
- `diag/runs/<run>/summary/audio_trace.summary.txt`
- `diag/runs/<run>/raw/brightness_trace.events.jsonl`
- `diag/runs/<run>/summary/brightness_trace.summary.txt`

## Emit contract

Canonical CLI form:

```sh
system-emit <subsystem> <current_state> <requested_state> <source> <brief_context>
```

Shell helper form:

```sh
system_emit "<subsystem>" "<current_state>" "<requested_state>" "<source>" "<brief_context>"
```

Legacy callers may still use `power_trace_emit`, `network_trace_emit`, `audio_trace_emit`, and `brightness_trace_emit`, but those wrappers now live in `trace.sh` and just forward into the same recorder.

Example:

```sh
system_emit "power" "RUNNING" "OFF" "save_poweroff.sh:startup" "shutdown path requested"
```

## Retrieving traces

From the device shell:

```sh
tail -n 120 /mnt/SDCARD/Saves/spruce/power/events.jsonl
tail -n 120 /mnt/SDCARD/Saves/spruce/power/summary.txt
tail -n 120 /mnt/SDCARD/Saves/spruce/networking/summary.txt
```

From diagnostics:

```sh
/mnt/SDCARD/spruce/scripts/diagnostics/runner.sh
```

Then inspect `Saves/spruce/diag/runs/<run_id>/`.

Tracker-local verification:

```sh
sh spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh <path-to-log-root-or-run-dir>
```

## Reading traces

Recommended workflow:

1. Start with `power/summary.txt` around the failure window.
2. Confirm the same records exist in `trace/events.jsonl` if you need a cross-subsystem timeline.
3. Compare `current_state` vs `requested_state`.
4. Use `source` to find the script/function that observed the milestone.
5. Use `context` to understand why the milestone was emitted.
6. Correlate with `spruce.log`, `activity.jsonl`, and `raw/10_runtime_state/markers.txt`.

## Common signatures

- Shutdown fence closed while app launch still exists:
  `power current=RUNNING requested=RUNNING ... context=command launch suppressed because shutdown is pending`
- Sleep request denied by lifecycle gate:
  `power current=RUNNING requested=SLEEPING ... context=sleep request suppressed`
- Wi-Fi path stuck before service bring-up:
  `networking current=ENABLED requested=CONNECTED ... context=wifi connection timed out`
- Audio/brightness side effects around sleep:
  `audio current=VOL_x requested=VOL_0 ...`
  `brightness current=BL_x requested=BL_y ...`

## Engineering notes

- The trace layer is intentionally best-effort and passive. Missing events are possible on abrupt power loss.
- Use `power_mode.state` and `/tmp` markers for control-plane truth; use exported traces plus the tracker-local verifier output for observation order and inconsistency review.
- State-machine verification now happens in `spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh`, so trace recording remains a thin overlay on the live firmware flow and the verifier is not shipped in the bridge payload.
