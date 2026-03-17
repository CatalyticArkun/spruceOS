# Diagnostics Bundle Deep Analysis (Original Bundle)

Source bundle: `H:\Saves\spruce.zip` extracted to `docs/diag-input/spruce_zip_2026-03-17/`.

## Session Timeline Reconstruction

- Session A (first boot): `spruce4.log` `04:49:57` -> `04:52:08`.
  - `first_boot` path active, Unpacker runs in background, firstboot script runs, PyUI starts, realtime listener starts, Wi-Fi starts, update checks start.
  - Reboot happens while Unpacker still logging unpack progress.
- Session B (first reboot): `spruce3.log` `04:52:17` -> `04:52:55`.
  - Unpacker finalization pass (`overlays_640x480`) completes quickly.
  - Ends with shutdown via power path.
- Session C (later boot + sleep/wake + shutdown): `spruce2.log` `04:53:10` -> `04:54:16`.
- Session D (later boot + emulator + sleep/wake + shutdown): `spruce1.log` `04:54:29` -> `04:55:56`.
- Session E (later boot): `spruce.log` `04:56:08` onward.

## Evidence-Separated Findings

Legend:
- status: `confirmed` | `likely` | `unconfirmed`
- file ownership references are likely ownership, not root-cause proof.

### 1) Audio diagnostic emit coverage incomplete across session boundaries
- status: confirmed
- evidence:
  - `audio/summary.txt`: repeated `INCONSISTENT_END no audio state recorded this session` at `04:52:04`, `04:52:52`.
  - `audio/summary.txt`: repeated `INCONSISTENT_START no audio state persisted from previous session` at `04:52:17`, `04:53:10`.
  - Actual audio emits only appear around sleep/wake in later sessions (`04:53:46/04:53:53`, `04:55:25/04:55:33`).
- why sequence matters: boot/shutdown sessions can complete without any audio state emission, causing continuity gaps between sessions.
- likely owner: `spruce/scripts/runtime.sh`, `spruce/scripts/sleep_helper.sh`, `spruce/scripts/save_poweroff.sh`, platform volume apply paths.
- confidence upgrade/downgrade: upgrade not needed; downgrade only if additional hidden audio emits exist outside captured logs.
- issue grouping: standalone issue.

### 2) Brightness diagnostic emit coverage effectively absent
- status: confirmed
- evidence:
  - `brightness/summary.txt`: no `BL_*` state events in any captured session.
  - Repeated `INCONSISTENT_START` and `INCONSISTENT_END` markers (`04:52:04`, `04:52:18`, `04:52:53`, `04:53:11`, `04:54:14`, `04:54:30`, `04:55:39`, `04:56:09`).
- why sequence matters: subsystem never establishes baseline state in session logs.
- likely owner: brightness apply/persistence callsites in platform device functions and lifecycle scripts.
- confidence upgrade/downgrade: upgrade not needed; downgrade only if brightness state is emitted to a different subsystem/log path.
- issue grouping: standalone issue.

### 3) `/appconfigs/system.json` read/write invalid or non-atomic state
- status: confirmed
- evidence:
  - `pyui.4.log` repeated watcher-triggered parse errors:
    - `04:53:32` through `04:53:42` and later `04:54:00` through `04:54:03`.
    - error: `JSON parse failed ... Extra data: line 17 column 2`.
- why sequence matters: repeated parse failures on change-detection indicate intermediate invalid contents or write contention.
- likely owner: system config writer paths and watcher/read-side coordination.
- confidence upgrade/downgrade: upgrade with write-side tracing around the same timestamps.
- issue grouping: standalone issue; also parent for parse-storm observation (#8).

### 4) Update check fails to establish network in tested sessions
- status: confirmed
- evidence:
  - `spruce2.log`: `04:53:33` attempt 1, `04:53:53` attempt 2, `04:54:13` failed after 3 attempts.
  - `spruce1.log`: `04:54:51` attempt 1, `04:55:11` attempt 2, `04:55:32` failed after 3 attempts.
  - Wi-Fi startup logs appear (`WiFi turned on`) but no successful update network establishment.
- why sequence matters: update subsystem repeatedly fails despite interface bring-up attempts.
- likely owner: update checker + Wi-Fi readiness gating.
- confidence upgrade/downgrade: upgrade with network stack probes (wpa/route/DNS) captured during attempts.
- issue grouping: standalone issue.

### 5) PyUI persisted state file missing on some boots
- status: likely
- evidence:
  - `pyui.5.log` and `pyui.4.log`: `State file not found: /mnt/SDCARD/Saves/pyui-state.json, using defaults.`
  - Later logs (`pyui.2.log`) do not show this line, indicating intermittent presence.
- why sequence matters: missing state at startup can alter initial UI/default behavior.
- likely owner: PyUI state persistence and startup ordering.
- confidence upgrade/downgrade: upgrade with explicit file create/write/read lifecycle logs.
- issue grouping: standalone issue or linked sub-issue under startup stability.

### 6) `archiveUnpacker` does not completely finish on first boot
- status: confirmed
- evidence:
  - `spruce4.log`: first boot starts Unpacker at `04:49:59` and continues unpacking entries up to `04:51:59`.
  - Reboot occurs at `04:52:08` without `Unpacker: Finished running` in this session.
  - `spruce3.log`: follow-up session completes `overlays_640x480` and logs `Unpacker: Finished running` at `04:52:38`.
- why sequence matters: first boot exits before full unpack completion; completion spills into next boot.
- likely owner: first_boot orchestration and unpacker lifecycle handling.
- confidence upgrade/downgrade: upgrade with unpack queue state marker per reboot boundary.
- issue grouping: standalone issue.

### 7) First boot heavily overlapped startup window
- status: confirmed
- evidence (same session `spruce4.log`):
  - Unpacker start `04:49:59`
  - realtime listener start `04:50:00`
  - Wi-Fi on `04:50:00`
  - PyUI start `04:50:02`
  - firstboot start `04:50:45`
  - update checks begin `04:51:43`
- why sequence matters: multiple heavy startup actors compete in same early window.
- likely owner: runtime startup ordering and gating.
- confidence upgrade/downgrade: upgrade with per-task startup gate telemetry.
- issue grouping: observation cluster; best grouped under unpack/startup orchestration issue(s).

### 8) Settings/config activity associated with repeated `system.json` parse storm
- status: confirmed
- evidence:
  - `pyui.4.log` shows alternating `watch_file ... detection changed` and parse failures in tight loops.
- why sequence matters: repeated watcher triggers + parse failures strongly indicate write/read race or non-atomic write pattern.
- likely owner: config writer + watcher contract.
- confidence upgrade/downgrade: upgrade with writer-side temp-file and rename logging.
- issue grouping: child evidence under issue #3.

### 9) Audio emits mainly in sleep/wake path, not boot/shutdown path
- status: confirmed
- evidence:
  - `audio/summary.txt` contains concrete `VOL_*` transitions only at sleep/wake timestamps.
  - boot/shutdown boundaries otherwise show lifecycle inconsistencies or finalize markers.
- why sequence matters: confirms coverage lane is localized to sleep helper.
- likely owner: missing lifecycle emits in boot/shutdown producers.
- confidence upgrade/downgrade: upgrade not needed.
- issue grouping: child evidence under issue #1.

### 10) Brightness has no observed successful state emission anywhere
- status: confirmed
- evidence:
  - `brightness/summary.txt` only lifecycle/inconsistency markers; no `BL_*` transitions.
- why sequence matters: total absence across multiple sessions points to systemic producer gap.
- likely owner: brightness emit producer callsites.
- confidence upgrade/downgrade: upgrade not needed.
- issue grouping: child evidence under issue #2.

### 11) Power transitions internally consistent (reference subsystem)
- status: confirmed
- evidence:
  - `power/summary.txt` shows coherent boot -> running, running <-> sleep, running -> off/reboot, finalize cycles without analogous coverage gaps.
- why sequence matters: validates framework is working when producer coverage exists.
- likely owner: N/A (reference baseline).
- confidence upgrade/downgrade: maintain as control/reference.
- issue grouping: not an issue; keep as comparison section.

### 12) Update checks colliding with unstable startup/first-boot work
- status: unconfirmed (but plausible)
- evidence:
  - Temporal overlap exists (`spruce4.log`), but logs do not directly show causal blocking by unpacker/firstboot.
- additional evidence needed:
  - network service state transitions + update checker internal readiness decisions in same window.
- grouping: keep as unconfirmed follow-up under issue #4.

### 13) Power-button cooldown may produce duplicate input events
- status: likely
- evidence:
  - `spruce2.log` and `spruce1.log` show repeated `power_key_down/up` during cooldown with identical timestamps/markers.
- why sequence matters: duplicate cooldown events can increase fragility of sleep/power transitions.
- additional evidence needed: raw input event trace correlation (`getevent` raw capture with sequence ids).
- grouping: follow-up issue or subsection under power button watchdog reliability.

### 14) Realtime message listener churn may contribute to fragile startup
- status: likely
- evidence:
  - frequent start/detect/kill/restart cycles across sessions in `spruce*.log` and `pyui.2.log` listener lifecycle.
- why sequence matters: churn overlaps with startup actions; could amplify race windows.
- additional evidence needed: resource/lock contention telemetry and failure correlation.
- grouping: follow-up investigation issue, possibly under startup orchestration.

### 15) Missing `pyui-state.json` causing more than harmless defaults
- status: unconfirmed
- evidence:
  - missing-file events are present, but no direct behavioral regression was proven in these logs.
- additional evidence needed: side-by-side boot behavior with/without state file plus UI path diffs.
- grouping: keep as unconfirmed investigation note, linked to issue #5.

## Recommended Issue Grouping From This Bundle

File now (confirmed):
- Audio emit lifecycle coverage gap (#1 + #9)
- Brightness emit lifecycle coverage gap (#2 + #10)
- `system.json` invalid/non-atomic write/parse storm (#3 + #8)
- Update network establishment failure (#4)
- First-boot unpack completion gap (#6)

Track as investigation (not yet root-cause-confirmed):
- Startup overlap/race-window hardening (#7, #12, #14)
- Power-button cooldown duplicate-event behavior (#13)
- PyUI state-file intermittency impact (#5, #15)

## Blocker Status

Previous repo-path blocker is now resolved for analysis input: the original bundle is present and analyzed from `docs/diag-input/spruce_zip_2026-03-17/`.
