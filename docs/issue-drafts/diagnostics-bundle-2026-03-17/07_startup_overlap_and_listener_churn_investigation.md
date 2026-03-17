# Startup overlap + realtime listener churn (investigation)

## Summary
First boot and later sessions show overlapping startup tasks and frequent realtime listener start/kill cycles. This is likely contributing to startup fragility, but direct causality for other failures is not yet proven.

## Key observations
- `spruce4.log` first boot overlap:
  - unpacker, firstboot, PyUI startup, Wi-Fi bring-up, update checks all active in same window.
- repeated realtime listener lifecycle churn:
  - start -> detect -> kill -> restart patterns across `spruce4.log`, `spruce3.log`, `spruce1.log`, and corresponding `pyui` logs.

## Confidence
`likely` for contribution to fragility, `unconfirmed` for direct causation of update/network or config parse failures.

## Suggested next debugging step
Instrument startup task boundaries and lock/contention metrics to map race windows against failure timestamps.

## Labels (suggested)
`startup-ordering` `realtime-listener` `investigation`
