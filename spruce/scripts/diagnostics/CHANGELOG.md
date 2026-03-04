# Diagnostics Bundle Changelog

## 0.5.0
- Merged overlapping memory diagnostics from Mustard check `S-03` into spruce-native `M-15-mma-alloc.sh`.
- Removed duplicate Mustard memory check script to avoid category overlap while keeping Mustard mount/space checks separate.

## 0.4.0
- Split Mustard-derived checks into dedicated category `mustard_checks.d` and runner stage (`run_mustard_checks.sh`).
- Kept spruce-native checks in `checks.d` without overlap; telemetry now includes both check categories.

## 0.3.0
- Added `collect_mustard_compat.sh` to capture MustardOS-style diagnostics snapshots (system/cpu+mem/network/filesystem/process/battery) into run artifacts.
- Added flag-gated verifier `V-02` for Mustard-style network ping validation (`RUN_TEST_V-02.lock`).
- Runner now includes the Mustard compatibility snapshot step before curation/check execution.

## 0.2.0
- Added MustardOS parity-inspired baseline checks for SD mount state, SD free space, and available memory.
- Kept checks read-only and RESULT-schema compliant for low-I/O automation workflows.

## 0.1.0
- Initial automation-first diagnostics runner with phase A/B execution.
- Added curated logging, checks/verifiers, telemetry event generation, and bundling.
- Added SD-based diagnostics self-update workflow.
