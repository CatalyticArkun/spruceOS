# Development vs arkun-dev defect-risk analysis

## Diff scope overview
Compared `origin/Development..origin/arkun-dev` with emphasis on power/sleep/startup/autoresume/device scripts.

High-impact touched areas:
- Core lifecycle scripts: `runtime.sh`, `runtimeHelper.sh`, `principal.sh`, `sleep_helper.sh`, `power_button_watchdog_v2.sh`, `save_poweroff.sh`, `archiveUnpacker.sh`.
- Device behavior: `platform/device_functions/MiyooMini.sh`, `A30.sh`, `SmartProS.sh`, `trimui_a133p.sh`, and `platform/device.sh` defaults.
- New shared framework: `power_trace.sh` integrated through `helperFunctions.sh`.
- New diagnostics framework and tests (`spruce/scripts/diagnostics/*`, `tests/diagnostics/*`).

Interpretation: this is not a cosmetic branch; it changes the power-state model and startup sequencing contracts across multiple devices.

## Likely defects in Development that are fixed or reduced in arkun-dev

### B07 In-game shutdown conflict / short-press sleep after long-press shutdown (reduced)
**Why likely fixed:**
- `power_button_watchdog_v2.sh` now marks shutdown intent (`/tmp/power_shutdown_requested`) and emits `SHUTDOWN_BEGIN` at long-press detection before poweroff handoff.
- On key release, it suppresses sleep if shutdown is already pending.
- `sleep_helper.sh` entry now exits early when shutdown is pending.

**Risk delta:** strong reduction of “shutdown request accidentally routes back into sleep path” race.

### B02 Pseudo-sleep wake restore loop (reduced)
**Why likely fixed:**
- `sleep_helper.sh` now creates explicit pseudo-sleep ownership (`/tmp/power_watchdog_suspended`) and a post-wake rearm boundary (`/tmp/power_watchdog_rearm_after`).
- `power_button_watchdog_v2.sh` honors those markers and restarts event stream instead of continuing stale buffered events.
- `MiyooMini.sh` removed synthetic KEY_POWER injection during wake restore and now returns success consistently after optional CPU-governor reset.

**Risk delta:** substantial reduction in immediate re-sleep/wake-loop behavior, especially on Miyoo Mini pseudo-sleep devices.

### B06 Stale power-state markers after dirty restart (reduced)
**Why likely fixed:**
- `runtime.sh` now proactively clears stale `/tmp` power markers at startup (`power_watchdog_suspended`, `power_watchdog_rearm_after`, `sleep_helper_started`, `powerbtn*`, etc.).
- `sleep_helper.sh` now validates stale PID marker handling for `/tmp/sleep_helper_started`.

**Risk delta:** reduced chance that previous-session residue blocks normal button semantics on next boot.

### B04 Archive unpacker startup contamination (reduced)
**Why likely fixed:**
- `archiveUnpacker.sh` now logs startup context (`save_active`, `lastgame.lock`, run mode).
- During `save_active=true` boot, `preCmd` unpack runs foreground rather than background.

**Risk delta:** lower probability that background unpacking competes with autoresume/command launch at sensitive boot windows.

### B01 Sleep-on-boot and boot-state ambiguity (reduced, indirectly)
**Why likely fixed:**
- `runtime.sh` adds startup state snapshot logging for `save_active` and `lastgame.lock` and boot milestones.
- `power_trace.sh` introduces boot reconciliation for unfinished transitions and canonical `shutdown pending` predicate used by callers.

**Risk delta:** improved guardrails and observability around startup power transitions; helps prevent or at least identify false sleep/shutdown carryover at boot.

### B03 A30 in-game shutdown freeze (possibly reduced)
**Why likely fixed:**
- `save_poweroff.sh` adds `any_emu_is_running` gating and `dismiss_active_emu_menu_state` before emulator close attempts.
- This specifically addresses cases where in-game menu/input state can interfere with graceful exit.

**Risk delta:** moderate reduction expected on A30/RA-family shutdown freezes, but still dependent on emulator process detection and input routing reliability.

### B05 Boot stall / black screen (partially reduced via instrumentation and ordering clarity)
**Why likely fixed:**
- `runtime.sh` and `principal.sh` include explicit milestone logging around unpack gates and PyUI launch boundaries.
- `archiveUnpacker.sh` adds more deterministic logging and mode tracing.

**Risk delta:** primarily better diagnosis and some ordering hardening; not a guaranteed functional fix for all black-screen causes.

## Likely defects introduced or more likely in arkun-dev vs Development

### New cross-script coupling risk: power flow now depends on power_trace availability/consistency
- Many critical decisions now hinge on `power_trace_shutdown_pending` and state files.
- `helperFunctions.sh` does provide no-op fallbacks when script missing, but mixed deployments (partial updates) can still create semantic drift:
  - devices with old scripts + new callers,
  - stale/corrupted `state.env` or `pending.env` influencing suppression behavior.

**Net new risk:** medium; branch adds robustness when coherent, but increases state-machine complexity and file-based coupling.

### Potential over-suppression risk around watchdog rearm windows (pseudo-sleep devices)
- `sleep_helper.sh` enforces a 3-second rearm boundary after wake.
- `power_button_watchdog_v2.sh` suppresses events until that boundary.

**Failure mode:** legitimate rapid post-wake power press may be ignored, perceived as missed input or delayed shutdown/sleep response.

### Boot reconciliation may misclassify edge cases after hard resets
- `power_trace_boot_reconcile_pending()` infers recovered transitions from pending markers.
- If pending markers persist unexpectedly (filesystem timing/dirty writes), startup can emit recovered events and alter state assumptions.

**Failure mode:** diagnostic/state model may say “recovered shutdown/reboot/wake” when user experienced different path, potentially affecting suppression predicates.

### Shutdown-path behavioral divergence due to new emulator gating
- `save_poweroff.sh` now only runs graceful/forceful emulator shutdown sequence if `any_emu_is_running` detects tracked process names.

**Failure mode:** unlisted emulator wrappers/process names could bypass graceful-close path, altering autosave expectations vs Development behavior.

### MiyooMini watchdog migration to v2 may expose device-variant regressions
- `MiyooMini.sh` replaces prior per-script startup watchdog suite with `launch_common_startup_watchdogs_v2` and variant-based lid selection.

**Failure mode:** if any variant-specific assumptions in legacy stack were implicitly required, some Mini models may see behavior shifts (button timing, lid interaction, or missing legacy helper side-effects).

## Thematic scoring against requested goals

### 1) Current behavior risk comparison
- **Development:** higher risk of race-driven sleep/shutdown conflicts and stale marker effects; lower complexity.
- **arkun-dev:** lower risk on known power races (especially pseudo-sleep/wake and shutdown conflict), but higher systemic complexity and state-coupling risk.

### 2) Likely-defect focus (not raw diff)
Primary likely fixed/reduced: B02, B04, B06, B07; probable partial improvement B01/B03/B05.
Primary introduced/increased: power_trace coupling complexity, rearm suppression edge cases, process-name detection gaps.

### 3) Priority area summary
- **Power/sleep/wake/shutdown:** materially reworked, likely net positive with complexity tradeoff.
- **Boot/startup/unpacker:** stronger sequencing + observability; less contamination risk.
- **Autoresume/lastgame.lock/save_active:** safer boot handling and better trace context.
- **Watchdog changes:** explicit ownership contract added (good), with possible short window suppressions.
- **Device-specific (MiyooMini/A30):** Mini pseudo-sleep path likely safer; A30 shutdown freeze likely reduced but not eliminated.

### 4) Enhancement themes
- **E01 Unified power state:** largely implemented via `power_trace.sh` + shared predicate use.
- **E02 Startup archive/resume validation:** improved via context logging and foreground preCmd when `save_active=true`.
- **E03 Unified input ownership marker:** implemented with `/tmp/power_watchdog_suspended` + rearm contract.
- **E04 Boot milestone timing profiler:** partial implementation via milestone logs and trace events.
- **E05 Human readability diagnostics:** significantly improved through structured power trace and docs/tests.

## Bottom line
If choosing between branches for users impacted by sleep/wake/shutdown races, `arkun-dev` is likely safer. If choosing for minimum behavioral change and lower subsystem complexity risk, `Development` is simpler but likely retains known race defects.
