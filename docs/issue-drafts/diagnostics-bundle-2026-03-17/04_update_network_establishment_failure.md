# Update checker fails to establish network

## Summary
Update checks repeatedly fail after retries despite Wi-Fi bring-up attempts.

## Expected behavior
Update checker should either establish network readiness or fail with actionable cause tied to network layer state.

## Actual behavior
Retries exhaust with `Failed to establish network connection after 3 attempts`.

## Evidence (timestamps)
- `spruce2.log`:
  - `04:53:33` attempt 1
  - `04:53:53` attempt 2
  - `04:54:13` failed after 3 attempts
- `spruce1.log`:
  - `04:54:51` attempt 1
  - `04:55:11` attempt 2
  - `04:55:32` failed after 3 attempts
- Wi-Fi logs present (`WiFi turned on`) in same sessions.

## Impact
Update subsystem remains unavailable in active sessions; could hide actionable update paths.

## Likely owning subsystem
- update checker readiness gating
- Wi-Fi/network service readiness signaling

## Suggested next debugging step
Capture per-attempt network diagnostics (IP, route, DNS, supplicant status) and correlate with update checker retry state machine.

## Labels (suggested)
`update` `networking` `diagnostics`
