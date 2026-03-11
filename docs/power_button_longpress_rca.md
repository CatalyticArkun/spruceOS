# Power-button long-press misclassification investigation (focused RCA)

## High-confidence behavior in current code
- `power_button_watchdog_v2.sh` classifies long press via a background `sleep 2` timer started on `key down` (`B_POWER 1`).
- If `/tmp/powerbtn` still exists when that timer expires, it emits `SHUTDOWN_BEGIN`, sets `/tmp/power_shutdown_requested`, and calls `invoke_save_poweroff_singleflight`.
- Short press is effectively "release before long-timer path runs": on `key up` (`B_POWER 0`), if `/tmp/powerbtn` exists and shutdown is not already pending, it invokes `sleep_helper.sh watchdog_short_press`.

## Most likely failure mechanism for the observed sequence

### Re-arm/suspend interaction can shift long-press start time late
The watchdog has an ownership gate:
- if `/tmp/power_watchdog_suspended` exists (sleep_helper owns events), or
- if `now < /tmp/power_watchdog_rearm_after` (post-wake rearm window),

it calls `reset_power_button_state` (removing `/tmp/powerbtn`, killing hold timer) and **breaks** the event loop, then outer loop sleeps 1 second before restarting `getevent`.

If a user starts holding power during/near that suppression window, the effective `power_key_down` may be recognized only after rearm/restart (or from a later repeat event), so the 2-second hold timer starts late. A physically long hold can then still release before the delayed 2-second timer matures, and key-up takes the short-press path (`sleep_helper.sh`), matching the reported first-hold behavior.

## Other plausible causes (lower confidence)
1. **Event-stream restart blind spot**: `break` + outer `sleep 1` introduces a no-listener gap; if down/up are split around this gap, classification can degrade to no-long-press and potentially short-path on later seen release.
2. **Late/irregular key-repeat dependence**: if the original `key down` was suppressed and no repeat arrives after rearm, timer never starts from true hold onset.
3. **Lid/sleep co-trigger timing**: `lid_watchdog_v2.sh` can invoke `sleep_helper.sh` independently on lid-close; this can produce similar "session disrupted first, shutdown later" user-perceived sequencing if close/open events are near the button press.

## Not supported strongly by current code
- `powerbtn_cancelled` interference appears unlikely in current tree because no active producer sets `/tmp/powerbtn_cancelled`.
- Duplicate shutdown path races are guarded by singleflight lockdir; they are more likely to suppress duplicates than cause short-press reroute.

## Smallest safe fix proposal
- In `power_button_watchdog_v2.sh`, when `watchdog_suspended_or_not_rearmed` is true, **do not `break` the read loop**; `continue` instead.
- Keep state-reset only when suspension ownership changes, but avoid forcing per-event stream teardown + 1s restart latency.

Rationale: this is the least invasive change that directly removes the self-inflicted listener gap and reduces delayed keydown recognition, without redesigning sleep ownership contract.

## Stronger hardening follow-ups
1. Record monotonic press timestamp on first observed `key down` and classify on release by measured duration (timer remains shutdown trigger, duration check is tie-break).
2. Add explicit marker "power_down_seen_during_rearm" and suppress immediate short-press path after rearm unless a fresh unsuppressed down/up pair is observed.
3. Add trace points around suppression/rearm (`SUPPRESSED_DOWN`, `SUPPRESSED_UP`, `REARM_CLEARED`) for field log correlation.
