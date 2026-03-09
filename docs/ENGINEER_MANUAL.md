# spruceOS Diagnostics Engineer Manual

## Workflow: Diagnose New Issue
1. Create `spruce/flags/RUN_STARTTIME_DIAGNOSTICS.lock` (or non-`.lock` variant) to enable automatic diagnostics.
2. Boot device; runner auto-executes Phase A once per boot and once after PyUI reaches main menu control.
3. Collect artifacts from `Saves/spruce/diag/latest/`.
4. Inspect `summary/telemetry_event.json`, `summary/report.txt`, `summary/findings.jsonl`, and `curated/signature_counts.txt` first.
5. If WARN/FAIL appears, review `summary/recommended_flags.txt` and selectively add flags under `spruce/flags/`.

## Create a New Check
- Add POSIX shell file under `spruce/scripts/diagnostics/checks.d/` for spruce-native checks.
- Add baseline parity checks under `spruce/scripts/diagnostics/baseline_checks.d/` to keep categories isolated.
- Must be read-only, low-I/O, and output a machine RESULT line:
  `RESULT id=<ID> verdict=<PASS|INFO|WARN|FAIL> severity=<P0..P4> confidence=<low|medium|high> evidence=<token>`.

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
