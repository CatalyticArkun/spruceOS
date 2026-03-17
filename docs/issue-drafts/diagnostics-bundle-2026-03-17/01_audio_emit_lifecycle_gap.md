# Audio diagnostic emit lifecycle coverage gap

## Summary
Audio state emission is missing across boot/shutdown session boundaries. Captured emits are concentrated around sleep/wake paths.

## Expected behavior
Audio should emit an authoritative state baseline and maintain continuity across boot, runtime, sleep/wake, and shutdown lifecycle boundaries.

## Actual behavior
- `INCONSISTENT_END` and `INCONSISTENT_START` are repeatedly emitted for audio around session boundaries.
- Concrete `VOL_*` transitions are seen only during sleep/wake flows.

## Evidence (timestamps)
- `audio/summary.txt`:
  - `04:52:04` `INCONSISTENT_END` no audio state recorded this session
  - `04:52:17` `INCONSISTENT_START` no audio state persisted from previous session
  - `04:52:52` `INCONSISTENT_END` no audio state recorded this session
  - `04:53:10` `INCONSISTENT_START` no audio state persisted from previous session
  - sleep/wake emits: `04:53:46` `UNKNOWN -> VOL_0`, `04:53:53` `VOL_0 -> VOL_0`; `04:55:25` `UNKNOWN -> VOL_0`, `04:55:33` `VOL_0 -> VOL_1`

## Impact
Diagnostics framework flags session-level audio coverage as inconsistent, reducing trust in cross-session continuity diagnostics.

## Likely owning subsystem
- `spruce/scripts/runtime.sh`
- `spruce/scripts/sleep_helper.sh`
- `spruce/scripts/save_poweroff.sh`
- device-specific volume apply/persist paths

## Suggested next debugging step
Trace and assert one authoritative audio baseline emit at startup and one fallback emit before finalize when no audio state exists in-session.

## Labels (suggested)
`diagnostics` `audio` `lifecycle` `state-machine`
