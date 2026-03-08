# Power-State Debug Integration Merge Notes

## 1) Branch comparison summary

Base branch: `origin/dev-arkun`
Integration branch: `merge/power-state-debug-integration`

### Commits unique vs `dev-arkun`
- `origin/dev-arkun-codex` introduces diagnostics hardening and aggregation improvements (plus SCUMMVM payload updates).
- `origin/codex/design-power-state-debugging-framework` introduces structured `power_trace` instrumentation, transition hooks in runtime/power paths, device capability hooks, and diagnostics ingestion of trace artifacts.

### High-focus overlap areas
- Diagnostics/logging framework: `spruce/scripts/diagnostics/*` (runner, telemetry, curation/collectors).
- Sleep/suspend: `spruce/scripts/sleep_helper.sh`.
- Wake/resume/startup: `spruce/scripts/runtime.sh`, `spruce/scripts/runtimeHelper.sh`, `spruce/scripts/power_button_watchdog_v2.sh`.
- Shutdown/reboot: `spruce/scripts/save_poweroff.sh`.
- Target-specific device logic: `spruce/scripts/platform/device.sh` and device function files (`A30`, `MiyooMini`, `trimui_a133p`).

## 2) Overlapping file matrix (targeted)

| File | dev-arkun-codex | power-state branch | Category |
|---|---|---|---|
| `spruce/scripts/diagnostics/runner.sh` | broader diagnostics phase flow | adds power-trace capture step | Behavioral + observability |
| `spruce/scripts/diagnostics/write_telemetry.sh` | robust result aggregation | adds power trace fields | Observability |
| `spruce/scripts/runtime.sh` | diagnostics startup behavior | `BOOT_BEGIN`/`BOOT_COMPLETE` + reconcile | Behavioral + observability |
| `spruce/scripts/helperFunctions.sh` | baseline global helpers | global `power_trace.sh` import | Infrastructure |
| `spruce/scripts/sleep_helper.sh` | existing sleep/wake flow | detailed sleep/wake transition emits + failure handling | High-risk behavioral |
| `spruce/scripts/save_poweroff.sh` | existing staged shutdown | transition emits + duplicate/exception observability | High-risk behavioral |
| `spruce/scripts/power_button_watchdog_v2.sh` | short/long press behavior | trace emits for short sleep/long shutdown | High-risk behavioral |
| `spruce/scripts/platform/device*.sh` | existing target hooks | additive `device_power_trace_*` hooks | Infrastructure |

## 3) Predicted/actual conflicts

### Safe merge
- Docs additions: `docs/power_trace_architecture.md`, `docs/power_trace_usage.md`.
- New tracing implementation: `spruce/scripts/power_trace.sh`.
- Most target capability hook additions in platform files.

### Textual conflicts (actual)
- `spruce/scripts/diagnostics/runner.sh`
- `spruce/scripts/diagnostics/write_telemetry.sh`
- `tests/diagnostics/test_runner.sh`

### Behavioral conflicts
- Diagnostics execution graph drift between branches in `runner.sh`.
- Telemetry aggregation implementation drift in `write_telemetry.sh`.

### High-risk infrastructure conflicts
- None as hard textual conflicts in `sleep_helper.sh` / `save_poweroff.sh`; however these are high-risk due to control-flow sensitivity and were reviewed before accepting merged behavior.

## 4) Recommended merge order

1. Base: `dev-arkun`
2. Merge: `dev-arkun-codex`
3. Merge: `codex/design-power-state-debugging-framework`

This order was applied.

## 5) Integration workflow used

1. `git checkout -B merge/power-state-debug-integration origin/dev-arkun`
2. `git merge --no-ff --no-commit origin/dev-arkun-codex` (resolved diagnostics add/add conflicts with codex branch versions)
3. Commit merge.
4. `git merge --no-ff --no-commit origin/codex/design-power-state-debugging-framework`
5. Resolve diagnostics conflicts first (`runner.sh`, `write_telemetry.sh`, tests), then review high-risk power files one-by-one.
6. Commit merge.

## 6) File-level conflict guidance and decisions

### `spruce/scripts/diagnostics/runner.sh`
- Decision: keep `dev-arkun-codex` flow as base; graft in power-trace capture (`capture_power_traces`) and include trace artifacts in telemetry bundle.
- Rationale: preserves broader diagnostics behavior while adding observability.

### `spruce/scripts/diagnostics/write_telemetry.sh`
- Decision: keep `dev-arkun-codex` telemetry aggregation; add power fields:
  - `power_trace_event_count`
  - `power_trace_recent_summary`
- Rationale: preserves robust parsing/escaping and broader results set.

### `spruce/scripts/runtime.sh`
- Decision: retain startup behavior from base and include `power_trace_boot_reconcile_pending`, `BOOT_BEGIN`, `BOOT_COMPLETE` events.

### `spruce/scripts/helperFunctions.sh`
- Decision: keep global `power_trace.sh` import.
- Safety note: import is side-effect-light and function-defining; file now exists in tree and is expected by multiple call sites.

### `spruce/scripts/sleep_helper.sh`
- Decision: keep power-state branch behavioral base.
- Explicitly preserved/reviewed: pseudo-sleep timeout escalation, real sleep path, wake detection, resume ordering, and transition abort/error telemetry.

### `spruce/scripts/save_poweroff.sh`
- Decision: keep power-state branch behavioral base.
- Explicitly preserved/reviewed: duplicate-entry guard, stage-2 handoff path, SD unmount/system-handled shutdown path, and error tracing on stage2 missing.

### `spruce/scripts/power_button_watchdog_v2.sh`
- Decision: keep power-state branch behavior with trace emits.
- Verified intent: short-press routes to sleep; long-press routes to shutdown.

### `spruce/scripts/platform/device*.sh`
- Decision: keep additive `device_power_trace_capabilities` / `device_power_trace_notes` hooks only.
- No runtime semantic overrides beyond metadata exposure.

## 7) Diagnostics framework validation summary

- Integrates with existing diagnostics runner/telemetry without replacing codex aggregation flow.
- Multi-target compatibility maintained via additive device capability hooks and default fallbacks.
- Sleep/wake/shutdown/startup transitions now emit structured events consumed by diagnostics artifacts and telemetry fields.

## 8) Post-merge cleanup recommendations

- Consider deduplicating transition emit strings via helper wrappers for common paths (sleep entry/wake/resume/shutdown).
- Audit for redundant emits in both watchdog and sleep helper to avoid double-counting in edge timing races.
- Normalize naming of result files (`baseline_check_results` vs legacy device-check naming) across tests/docs.
- Consider centralizing bundle include lists to avoid drift between upload/telemetry bundles.
- Follow-up (non-blocking): `run_device_checks.sh` and `device_check_results.txt` are partially integrated scaffolding. They are functional but not wired into `runner.sh` or telemetry ingestion; summary wildcard logic may still observe them if run manually. Recommended follow-up is to either fully integrate device checks into runner/telemetry/summary contracts, or remove/deprecate the path to avoid taxonomy drift.

## 9) Validation checklist

### Automated checks completed
- [x] Diagnostics runner test script
- [x] Power trace unit-style test script

### Manual/device validation still required
- [ ] cold boot
- [ ] shutdown
- [ ] reboot
- [ ] startup after shutdown
- [ ] sleep entry
- [ ] wake
- [ ] repeated sleep/wake cycles
- [ ] short-press sleep
- [ ] long-press shutdown
- [ ] timer wake / idle timeout escalation
- [ ] multiple device targets (A30, MiyooMini, trimui_a133p at minimum)
- [ ] diagnostic output completeness (trace artifacts + telemetry fields)

## 10) Assumptions and unresolved risks

- Assumes global `power_trace.sh` sourcing remains safe in all startup contexts.
- Device-specific sleep implementations may still differ in timer-wake semantics and require on-hardware confirmation.
- Transition order is best-effort around asynchronous shutdown paths; some traces can be missing on abrupt power loss.
