# Brightness diagnostic emit lifecycle coverage gap

## Summary
Brightness emits are absent across sessions; only lifecycle/inconsistency markers are present.

## Expected behavior
Brightness should emit `BL_*` state transitions from authoritative apply points and preserve continuity across sessions.

## Actual behavior
- No concrete `BL_*` emits observed in the bundle.
- Repeated `INCONSISTENT_START/END` for brightness.

## Evidence (timestamps)
- `brightness/summary.txt`: repeated inconsistency lifecycle markers at `04:52:04`, `04:52:18`, `04:52:53`, `04:53:11`, `04:54:14`, `04:54:30`, `04:55:39`, `04:56:09`.
- No `current=BL_* requested=BL_*` entries observed.

## Impact
Brightness diagnostics cannot establish session continuity or validate brightness behavior.

## Likely owning subsystem
- brightness apply/persist code in platform device functions
- lifecycle wrappers in runtime/sleep/shutdown scripts

## Suggested next debugging step
Instrument/startup and shutdown fallback brightness baseline emits and verify at least one `BL_*` state per completed session.

## Labels (suggested)
`diagnostics` `brightness` `lifecycle` `state-machine`
