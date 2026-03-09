# Using Power Transition Traces

## Where traces are collected

Primary files:
- `Saves/spruce/power/events.jsonl` (raw structured trace stream)
- `Saves/spruce/power/summary.txt` (human-readable transition timeline)
- `Saves/spruce/power/state.env` (current tracker state)
- `Saves/spruce/power/pending.env` (cross-boot pending transition marker)

Diagnostics bundle integration:
- `diag/runs/<run>/raw/power_trace.events.jsonl`
- `diag/runs/<run>/summary/power_trace.summary.txt`
- telemetry includes count + recent summary snippets.

## How to retrieve traces

From the device shell:

```sh
tail -n 120 /mnt/SDCARD/Saves/spruce/power/events.jsonl
tail -n 120 /mnt/SDCARD/Saves/spruce/power/summary.txt
cat /mnt/SDCARD/Saves/spruce/power/state.env
```

From diagnostics:

```sh
/mnt/SDCARD/spruce/scripts/diagnostics/runner.sh
```

Then inspect run artifacts under `Saves/spruce/diag/runs/<run_id>/`.

## How to read traces

Recommended quick workflow:
1. Find the correlation id and boot session id around the failure window.
2. Compare `intended_state` vs `observed_state` and actual event order.
3. Check for `INVALID_TRANSITION`, `TRANSITION_ABORTED`, `TRANSITION_TIMEOUT`, `POWER_ERROR`, `UNKNOWN_TRANSITION`.
4. Read target capability notes in `notes` to understand missing hardware signals.

## Common failure signatures

- **Resume misclassified as cold boot**
  - Boot begins with unresolved pending `SLEEP` and `UNKNOWN_TRANSITION` during reconciliation.
- **Sleep entered but never resumed cleanly**
  - `SLEEP_ENTER_COMPLETE` present but no `WAKE_RESUME_COMPLETE`; next boot reports reconciliation anomalies.
- **Double-triggered shutdown/sleep**
  - Duplicate intent events followed by `INVALID_TRANSITION`.
- **RTC timeout path drift**
  - `TRANSITION_TIMEOUT` with `idle_timeout` reason followed by poweroff path.

## Engineering tips

- Always correlate with `spruce.log` and `activity.jsonl` for app-level context.
- Compare the same sequence across targets; capability notes make target divergence explicit.
- For devices lacking a signal, trust the `notes` field over assumptions.
