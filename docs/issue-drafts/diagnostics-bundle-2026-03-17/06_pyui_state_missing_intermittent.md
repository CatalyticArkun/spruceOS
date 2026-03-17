# PyUI state file missing intermittently on boot

## Summary
`pyui-state.json` is missing on some boots and defaults are used.

## Expected behavior
PyUI state file should exist and load consistently unless intentionally reset.

## Actual behavior
Some sessions log missing state-file fallback to defaults.

## Evidence (timestamps)
- `pyui.5.log` `04:52:45` state file not found
- `pyui.4.log` `04:53:25` state file not found
- later sessions do not always repeat this exact warning

## Impact
Potential startup default-path behavior drift between boots.

## Likely owning subsystem
- PyUI state persistence/read path

## Suggested next debugging step
Add explicit create/write/read audit for `pyui-state.json` across boot/shutdown and verify file durability.

## Labels (suggested)
`pyui` `state-persistence` `startup`
