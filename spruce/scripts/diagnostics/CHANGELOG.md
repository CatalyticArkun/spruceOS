# Diagnostics Bundle Changelog

## 0.6.0
- Replaced compatibility-named collection stages with SpruceOS-native collectors (`run_collectors.sh` + `collectors.d/*`).
- Renamed baseline category internals to remove upstream naming remnants (`baseline_checks.d`, `baseline_check_results.txt`).
- Added consolidated summary outputs: `summary/report.txt`, `summary/findings.jsonl`, and `summary/run_manifest.json`.
- Included verifier results in telemetry event and expanded telemetry bundle contents.
- Added uptime/clock sanity propagation across identity, telemetry, and distilled outputs.

## 0.5.0
- Merged overlapping memory diagnostics from baseline memory check into spruce-native `M-15-mma-alloc.sh`.
- Removed duplicate baseline memory check script to avoid category overlap while keeping mount/space checks separate.

## 0.4.0
- Split derived baseline checks into dedicated category and runner stage.
- Kept spruce-native checks in `checks.d` without overlap; telemetry includes both check categories.

## 0.3.0
- Added broad baseline diagnostics snapshot collection (system/cpu+mem/network/filesystem/process/battery) into run artifacts.
- Added flag-gated verifier `V-02` for network ping validation (`RUN_TEST_V-02.lock`).

## 0.2.0
- Added baseline checks for SD mount state and SD free space.

## 0.1.0
- Initial automation-first diagnostics runner with phase A/B execution.
