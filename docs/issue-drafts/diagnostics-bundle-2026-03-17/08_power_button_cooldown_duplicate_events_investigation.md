# Power-button cooldown duplicate-event behavior (investigation)

## Summary
Cooldown window logs show repeated down/up events with identical timing markers.

## Evidence (timestamps)
- `spruce2.log` around `04:53:55`: repeated `power_key_down/up` during cooldown with same `LAST_POWER_DOWN`.
- `spruce1.log` around `04:55:35`: similar repeated cooldown event pairs.

## Confidence
`likely` behavior anomaly; root cause remains unconfirmed from current logs alone.

## Suggested next debugging step
Capture raw input sequence from `getevent` with per-event IDs and correlate with watchdog cooldown logic transitions.

## Labels (suggested)
`input` `power-button` `watchdog` `investigation`
