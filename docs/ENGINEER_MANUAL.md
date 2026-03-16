# spruceOS Diagnostics Engineer Manual

## Workflow: Diagnose New Issue
1. Create `spruce/flags/RUN_STARTTIME_DIAGNOSTICS.lock` (or non-`.lock` variant) to enable automatic diagnostics.
2. Boot device; runner auto-executes Phase A once per boot and once after PyUI reaches main menu control.
3. Collect artifacts from `Saves/spruce/diag/latest/`.
4. Inspect `summary/telemetry_event.json`, `summary/report.txt`, `summary/findings.jsonl`, and `curated/signature_counts.txt` first.
5. If WARN/FAIL appears, review `summary/recommended_flags.txt` and selectively add flags under `spruce/flags/`.

## Create a New Check
- Add POSIX shell file under `spruce/scripts/diagnostics/checks.d/` for shared health checks or shared source regressions.
- Add device-specific assertions under `spruce/scripts/diagnostics/device_checks.d/`; these now run automatically and write `results/device_check_results.txt`.
- Add baseline parity checks under `spruce/scripts/diagnostics/baseline_checks.d/` to keep categories isolated.
- Must be read-only, low-I/O, and output a machine RESULT line:
  `RESULT id=<ID> verdict=<PASS|INFO|WARN|FAIL> severity=<P0..P4> confidence=<low|medium|high> evidence=<token>`.
- Use the real tracker issue ID when the detector maps 1:1 to `issues_and_fixes.md`.
- Use `GEN-*` only for generic health detectors that are not a tracker issue.

## Current Issue-backed Coverage
- Read-only shell/source coverage is now present for `A-03`, `A-04`, `A-08`, `A-13`, `A-16`, `B-13`, `P-06`, `P-07`, and `P-08`.
- Open issues that still need hardware or runtime-specific validation include examples such as `P-01`, `M-08`, `A-17`, `SP-09`, and `SP-10`.

## State Collection
- `collectors.d/10_runtime_state.sh` is the first stop when debugging launch/power races; it records flags, `/tmp` lifecycle markers, `power_mode.state`, and focused `SYSTEM_JSON` fields.
- after collecting a run, use `spruceOS_tracker/tracker_local/scripts/verify_system_emit_logs.sh` against the exported log root or run directory for state-machine consistency review.
- Passive subsystem traces live separately under `Saves/spruce/{power,networking,audio,brightness}/` and are bundled by the diagnostics runner.

## Confirm via Verifier
- Add verifier in `verifiers.d/` with explicit `RUN_TEST_<ID>.lock` gate.
- Never auto-run verifiers without matching flag.
- For network reachability confirmation, use `RUN_TEST_V-02.lock`.

## Retire Checks
- Move legacy check into `retired_checks.d/`.
- These are disabled unless `ENABLE_RETIRED_CHECKS.lock` is present.

## Token-efficient AI Escalation
- Share only telemetry bundle by default (`latest/telemetry_latest.tgz`).
- Escalate to upload bundle only when deterministic signatures are insufficient.
