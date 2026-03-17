# `/appconfigs/system.json` parse storm and invalid-read window

## Summary
Watcher-triggered reads repeatedly observe invalid JSON (`Extra data`) during config change windows.

## Expected behavior
`system.json` updates should be atomic from reader perspective; watcher callbacks should parse valid JSON.

## Actual behavior
Repeated parse failures during watcher detections, indicating non-atomic write or conflicting writers/readers.

## Evidence (timestamps)
- `pyui.4.log`:
  - `04:53:32` to `04:53:42`: repeated `/appconfigs/system.json detection changed` + `JSON parse failed ... Extra data: line 17 column 2`
  - repeated again at `04:54:00` to `04:54:03`

## Impact
Runtime config application can become ambiguous or stale; dependent subsystems may process inconsistent state.

## Likely owning subsystem
- config writer paths touching `system.json`
- PyUI file watcher + parse fallback layer

## Suggested next debugging step
Audit writer paths for temp-write + atomic rename discipline and correlate writer timestamps to watcher parse failures.

## Labels (suggested)
`config` `pyui` `diagnostics` `race-condition`
