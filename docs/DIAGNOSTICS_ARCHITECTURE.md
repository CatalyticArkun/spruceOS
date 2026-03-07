# Diagnostics + Telemetry Architecture

## Layout
- `spruce/scripts/diagnostics/runner.sh` orchestrates phase execution and resume state.
- `checks.d/` for spruce-native always-on read-only detectors.
- `baseline_checks.d/` for upstream-derived baseline checks kept in a dedicated category.
- `collectors.d/` + `run_collectors.sh` for broad baseline snapshot collection into `raw/<collector_name>/` (adapted from upstream open-source handheld diagnostics patterns).
- `verifiers.d/` for side-effect tests gated by flags.
- `retired_checks.d/` optional legacy detectors.
- `curate_logs.sh` + `patterns.conf` produce deterministic signature extracts.

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
