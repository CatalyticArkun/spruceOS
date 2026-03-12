# Power/Lifecycle Support Triage Notes (Phase 3)

## 1) Distinguish internal duplication vs external/stock-origin transition

### Internal duplication indicators
- `REQUEST_SUPPRESSED` with reasons such as:
  - `active_tx_same_kind`
  - `shutdown_pending_duplicate`
  - `singleflight_in_progress`
  - `singleflight_race_lost`
- Same `tx_kind` requested repeatedly while `pt_active_txid` is populated.

### External/stock-origin indicators
- `REQUEST_SUPPRESSED` with `external_transition_active`.
- External live observation marker path produces trace entries with:
  - `tx_origin="external"`
  - `tx_phase="EXEC"`
- Reconcile path with pending tx metadata showing `pending_tx_origin="external"`.

## 2) Expected user-controlled behavior vs regression

### Expected (healthy)
- Short press power: one sleep request (when lifecycle gates allow).
- Long press power: one shutdown request/handoff.
- No second duplicate request while shutdown is pending.
- Reboot option shown only when target `reboot_cmd()` capability is non-`None`.

### Potential regression signatures
- Prompt shown repeatedly from one long hold.
- Short press not dispatching sleep when gates are open.
- Reboot option shown on targets lacking reboot capability.
- Suppression reason missing when duplicate/external transition is blocked.

## 3) Where to inspect owner/tx/origin/suppression

### Files
- `/mnt/SDCARD/Saves/spruce/power/events.jsonl`
- `/mnt/SDCARD/Saves/spruce/power/summary.txt`
- `/mnt/SDCARD/Saves/spruce/power/state.env`
- `/mnt/SDCARD/Saves/spruce/power/pending.env`
- `/mnt/SDCARD/Saves/spruce/spruce.log`

### Fields to inspect in `events.jsonl`
- `txid`
- `tx_origin`
- `tx_requested_by`
- `tx_kind`
- `tx_phase`
- `trigger`
- `source`
- suppression reason via `trigger`/`notes` on `REQUEST_SUPPRESSED`

## 4) Signal patterns to recognize quickly

- **Same-kind duplicate suppression:** `REQUEST_SUPPRESSED` + `active_tx_same_kind`.
- **External active suppression:** `REQUEST_SUPPRESSED` + `external_transition_active`.
- **Recovered path after interruption:** reconcile emits recovered events and pending key is consumed once.

## 5) Volume responsiveness / volume-sync complaints

Phase 3 does not change volume ownership architecture. For complaints, first check:
- if power gating unexpectedly disabled input polling globally,
- whether target still emits volume-key events,
- whether UI display and system volume source (`SYSTEM_JSON`/platform mixer path) diverged.

Use existing diagnostics and target-specific logs before proposing architecture changes.

## 6) Quick rollback guidance

- Fast toggle: set `SPRUCE_WATCHDOG_OWNS_POWER_BUTTON=0` for legacy PyUI-owned raw power behavior (debug only).
- Safe rollback: revert Phase 1/2/phase-3-amend commits if target regression is confirmed.
- Keep rollback scoped; do not revert unrelated watchdog/sleep fixes.

