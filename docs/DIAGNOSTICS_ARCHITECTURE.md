# Diagnostics + Telemetry Architecture

## Layout
- `spruce/scripts/diagnostics/runner.sh` orchestrates phase execution and resume state.
- `checks.d/` for shared always-on read-only detectors. Generic health checks use `GEN-*`; direct tracker issue checks keep the tracker ID.
- `device_checks.d/` for device/script-specific read-only detectors executed in the main runner.
- `baseline_checks.d/` for upstream-derived baseline checks kept in a dedicated category.
- `collectors.d/` + `run_collectors.sh` for broad baseline snapshot collection into `raw/<collector_name>/` (adapted from upstream open-source handheld diagnostics patterns).
- `verifiers.d/` for side-effect tests gated by flags.
- `retired_checks.d/` optional legacy detectors.
- `curate_logs.sh` + `patterns.conf` produce deterministic signature extracts.

## Runner Stages
1. `01_identity`
2. `02_collectors`
3. `03_curation`
4. `04_checks`
5. `05_device_checks`
6. `06_baseline_checks`
7. `07_verifiers`
8. `08_power_trace` (captures passive subsystem trace exports for `power`, `networking`, `audio`, and `brightness`)

## Startup Integration
- Runner is invoked from `spruce/scripts/runtime.sh` in background only when `RUN_STARTTIME_DIAGNOSTICS(.lock)` is set.
- PyUI also triggers one post-main-menu diagnostics round via `request_post_menu_run.sh` once per boot (same gate flag required).
- No user CLI args required; control is via `spruce/flags/*.lock`.

## Resume + Checkpointing
- Persistent state is in `Saves/spruce/diag/state/current_run.state`.
- Step markers (`state/*.done`) guarantee idempotent step boundaries.
- Phase B heavy exports checkpoint copy index and continue after reboot.

## Artifacts
- Full: `runs/<run_id>/bundles/upload_bundle.tgz`.
- Small: `runs/<run_id>/bundles/telemetry_bundle.tgz`.
- Stable latest pointers copied into `diag/latest/`.
- Device-specific results land in `results/device_check_results.txt` and are included in telemetry + run summaries.

## Coverage Model
- Generic system health coverage currently uses:
  - `GEN-01` kernel oops markers
  - `GEN-02` allocator pressure / MMA failures
  - `GEN-03` PyUI exception markers
  - `GEN-04` passive power-trace record-shape and summary-presence validation
- Issue-backed read-only coverage currently exists for `A-03`, `A-04`, `A-08`, `A-13`, `A-16`, `B-13`, `P-06`, `P-07`, and `P-08`.
- Hardware/runtime-dependent issues that need live hardware behavior or side effects are still expected to use DEEPROOT guidance plus targeted verifiers/tests instead of always-on checks.

## Stabilization Collection
- `collectors.d/10_runtime_state.sh` snapshots:
  - `spruce/flags/*`
  - `/tmp` power and launch markers such as `cmd_to_run.sh`, `power_mode.state`, and shutdown markers
  - the canonical `power_mode.state` control-plane snapshot
  - exported trace artifacts intended for follow-up analysis by the tracker-local verifier at `spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh`
  - focused `SYSTEM_JSON` fields when available
