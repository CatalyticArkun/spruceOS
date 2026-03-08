# MiyooMini-family pseudo-sleep issue 2: wake ownership investigation

## Updated root cause analysis (stock-OS-ownership hypothesis)

Current spruce behavior showed two concurrent owners of power-button semantics during pseudo-sleep:

1. `sleep_helper.sh` started its own `getevent` watcher on the power device and used that event to exit pseudo-sleep.
2. `power_button_watchdog_v2.sh` remained globally active and also interpreted post-wake power events as fresh short/long presses.
3. `device_exit_sleep()` on MiyooMini restarted vendor `/customer/app/keymon` and re-enabled input, which likely changes event timing and delivery as wake completes.

This means wake could be consumed by sleep-helper and still later be observed by watchdog as a new actionable press lifecycle, creating re-sleep.

## Which layer truly owns wake-button semantics

For MiyooMini-family pseudo-sleep, wake-button semantics should be treated as **OS/input-stack mediated + sleep-helper-owned during transition**, not globally watchdog-owned:

- Vendor `keymon` is explicitly stopped/started around sleep in device hooks.
- Input is explicitly re-enabled in `device_exit_sleep()`.
- These are signs that low-level wake/input lifecycle is not purely owned by spruce watchdog.

Conclusion: watchdog should not co-own wake-button event interpretation during pseudo-sleep transition.

## Proposed redesign (minimal, principled)

Implemented **Option A/B hybrid** with minimal watchdog-v2 redesign:

- Add explicit suspension ownership flag while pseudo-sleep is active:
  - `sleep_helper.sh` sets `/tmp/power_watchdog_suspended` when entering ownership.
- Add explicit rearm boundary after wake restore:
  - `sleep_helper.sh` writes `/tmp/power_watchdog_rearm_after` (epoch) after wake resume work.
- Watchdog now defers all power-button interpretation while either:
  - suspension flag exists, or
  - rearm boundary has not elapsed.

This removes one-shot post-wake event suppression heuristics and replaces them with lifecycle ownership boundaries.

## Before vs after ownership model

### Before
- Watchdog always active globally.
- Sleep-helper also watched power for pseudo-sleep wake.
- Wake handling depended on one-shot ignore windows and per-event suppression.

### After
- Sleep-helper is authoritative during pseudo-sleep + wake transition.
- Watchdog is hard-suspended from power interpretation during that window.
- Watchdog re-arms only after explicit post-resume boundary.
- Later intentional short/long presses are handled normally after rearm.

## Why deeper redesign is not currently required

A deeper architecture rewrite is not required yet because:

- The failure mode maps directly to co-ownership/race timing.
- Explicit suspend/rearm contract addresses ownership cleanly.
- No broad cross-platform changes were needed; this remains confined to pseudo-sleep flow and watchdog v2 behavior.

If this still fails on hardware, next escalation should be fully OS-delegated wake model where watchdog reacts only to post-resume state, not direct wake-button events.

## Hardware validation checklist

- [ ] Mini Plus V2 wake to MainUI.
- [ ] Mini Plus V2 wake to game.
- [ ] Mini Flip power wake.
- [ ] Mini Flip lid wake / lid+power interactions.
- [ ] Repeat sleep/wake cycle 20+ times without auto re-sleep.
- [ ] Immediate post-wake short press behavior:
  - [ ] first intentional short press after settle sleeps normally.
- [ ] Immediate post-wake long press behavior:
  - [ ] first intentional long press after settle shuts down normally.
- [ ] Confirm no regressions in non-pseudo-sleep platforms.
