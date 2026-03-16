# Diagnostics Bundle Changelog

## 0.7.0
- Activated `device_checks.d` in `runner.sh`, telemetry, summaries, and bundles so device-specific results are now first-class outputs (`device_check_results.txt`).
- Split generic health checks onto `GEN-*` IDs to avoid collisions with tracker issue IDs and kept `GEN-04` as an on-device record-shape check while moving the state-machine verifier into tracker-local tooling.
- Added issue-backed read-only detectors for `A-03`, `A-04`, `A-08`, `A-13`, `A-16`, `B-13`, `P-06`, `P-07`, and `P-08`.
- Added `collectors.d/10_runtime_state.sh` to snapshot launch/power markers, flags, and focused `SYSTEM_JSON` state for shell-level postmortems.

## 0.6.0
- Replaced compatibility-named collection stages with SpruceOS-native collectors (`run_collectors.sh` + `collectors.d/*`).
- Renamed baseline category internals to remove upstream naming remnants (`baseline_checks.d`, `baseline_check_results.txt`).
- Added consolidated summary outputs: `summary/report.txt`, `summary/findings.jsonl`, and `summary/run_manifest.json`.
- Included verifier results in telemetry event and expanded telemetry bundle contents.
- Added uptime/clock sanity propagation across identity, telemetry, and distilled outputs.

## 0.5.0
- Merged overlapping memory diagnostics from baseline memory check into the spruce-native allocator pressure check (now `GEN-02-mma-alloc.sh`).
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
