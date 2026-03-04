# spruceOS Diagnostics Engineer Manual

## Workflow: Diagnose New Issue
1. Create `spruce/flags/RUN_STARTTIME_DIAGNOSTICS.lock` (or non-`.lock` variant) to enable automatic diagnostics.
2. Boot device; runner auto-executes Phase A once per boot and once after PyUI reaches main menu control.
3. Collect artifacts from `Saves/spruce/diag/latest/`.
4. Inspect `summary/telemetry_event.json`, `results/check_results.txt`, and `curated/signature_counts.txt` first.
5. If WARN/FAIL appears, review `summary/recommended_flags.txt` and selectively add flags under `spruce/flags/`.

## Create a New Check
- Add POSIX shell file under `spruce/scripts/diagnostics/checks.d/` for spruce-native checks.
- Add Mustard parity checks under `spruce/scripts/diagnostics/mustard_checks.d/` to keep categories isolated.
- Must be read-only, low-I/O, and output a machine RESULT line:
  `RESULT id=<ID> verdict=<PASS|INFO|WARN|FAIL> severity=<P0..P4> confidence=<low|medium|high> evidence=<token>`.

## Confirm via Verifier
- Add verifier in `verifiers.d/` with explicit `RUN_TEST_<ID>.lock` gate.
- Never auto-run verifiers without matching flag.
- For Mustard-like network reachability checks, use `RUN_TEST_V-02.lock` (pings external DNS and resolvers).

## Retire Checks
- Move legacy check into `retired_checks.d/`.
- These are disabled unless `ENABLE_RETIRED_CHECKS.lock` is present.

## Token-efficient AI Escalation
- Share only telemetry bundle by default (`latest/telemetry_latest.tgz`).
- Escalate to upload bundle only when deterministic signatures are insufficient.

## MustardOS Check Parity
- Added baseline parity checks inspired by the MustardOS System Diagnostics flow:
  - `S-01-sd-mount.sh` (SD mount present and RW/RO status)
  - `S-02-sd-free-space.sh` (SD free-space thresholds)
- `S-03` memory-threshold logic was merged into spruce-native `M-15-mma-alloc.sh` to avoid duplicate memory diagnostics across categories.
- Mustard-style system data collection is implemented in `collect_mustard_compat.sh`; continue extending with additional parity checks as needed.
