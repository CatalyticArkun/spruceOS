# Boot/Unpack sequencing investigation (`arkun-dev` vs `main`)

## Scope and method

Compared these files between `arkun/main` and `arkun/arkun-dev`:
- `spruce/scripts/runtime.sh`
- `spruce/scripts/archiveUnpacker.sh`
- `spruce/scripts/firstboot.sh`
- `spruce/scripts/principal.sh`
- `spruce/scripts/helperFunctions.sh`

Reference commands used:
- `git diff arkun/main..arkun/arkun-dev -- <files>`
- `git show arkun/main:<file>`
- `nl -ba <file>`

---

## 1) Hypothesis Check

### Primary hypothesis
`arkun-dev` regressed first-boot/recovery unpack gating and allows UI/boot progression before required unpack phases.

**Result: not established as a branch regression relative to `main`**.

Why:
1. `runtime.sh` still launches first-boot/recovery unpack in background and runs `firstboot.sh` in foreground (same high-level pattern as `main`). In `arkun-dev`, this remains explicitly true. 【F:spruce/scripts/runtime.sh†L131-L147】
2. `principal.sh` in `arkun-dev` still gates on `pre_menu_unpacking` before PyUI and on `pre_cmd_unpacking` before command/game handling (same behavior contract as `main`, with extra logging only). 【F:spruce/scripts/principal.sh†L36-L55】
3. `finish_unpacking()` semantics are unchanged between branches (same check, same wait loop, same `silentUnpacker` removal). 【F:spruce/scripts/helperFunctions.sh†L172-L183】
4. `firstboot.sh` in `arkun-dev` is *stricter* than `main`: it now waits for both `pre_menu_unpacking` and `pre_cmd_unpacking`, whereas `main` only waited for `pre_menu_unpacking`. 【F:spruce/scripts/firstboot.sh†L60-L84】

### Secondary hypothesis
Active-save resume path may no longer force pre-cmd unpack completion before resume.

**Result: falsified for the code paths examined**.

`archiveUnpacker.sh` in `arkun-dev` still runs preCmd unpack synchronously when `save_active=true`; only `save_active=false` uses background pre-cmd worker. 【F:spruce/scripts/archiveUnpacker.sh†L139-L149】

---

## 2) Log Interpretation (against supplied trace statements)

Given trace statements (from request):
- `save_active=false`
- `lastgame_lock=missing`
- first-boot/recovery path
- `archiveUnpacker.sh --silent` in background
- `firstboot.sh` foreground
- `Auto Resume skipped (no save_active flag)`

This sequence matches `runtime.sh` first-boot/recovery branch in `arkun-dev`:
- first-boot/recovery path condition and background `archiveUnpacker.sh --silent` launch. 【F:spruce/scripts/runtime.sh†L131-L139】
- foreground `firstboot.sh` launch/completion logging. 【F:spruce/scripts/runtime.sh†L140-L143】
- `Auto Resume skipped` when `save_active` is not set. 【F:spruce/scripts/runtime.sh†L164-L169】
- startup snapshot logs include `save_active` and `lastgame_lock` states, matching the described trace vocabulary. 【F:spruce/scripts/runtime.sh†L35-L51】

What this trace **does not establish** by itself:
- whether ongoing extraction was `pre_menu` (must gate PyUI) vs `pre_cmd` (allowed to continue until before command launch).
- whether a `save_active=true` resume path was exercised (it was not).

---

## 3) `main` Intended Behavior

Intended staged gating model (as implemented in `main`) is:
- First boot: `runtime.sh` starts `archiveUnpacker.sh --silent &`, then runs `firstboot.sh` foreground. (verified from branch comparison).
- `principal.sh` blocks on `pre_menu_unpacking` before PyUI and blocks on `pre_cmd_unpacking` before command/game launch. (same gating points retained in `arkun-dev`; see current file). 【F:spruce/scripts/principal.sh†L36-L55】
- `finish_unpacking()` waits on lock file if present. 【F:spruce/scripts/helperFunctions.sh†L172-L183】
- `archiveUnpacker.sh` runs preCmd synchronously when `save_active=true`, background when false. This same policy remains in `arkun-dev`. 【F:spruce/scripts/archiveUnpacker.sh†L143-L149】

---

## 4) `arkun-dev` Actual Behavior

Changes found in investigated files:
- Added first-boot state machine markers: `first_boot_*_in_progress`, `*_complete`, `*_complete_verified`, with recovery verification logic in `runtime.sh`. 【F:spruce/scripts/runtime.sh†L80-L129】
- Added more startup diagnostics/logging in `runtime.sh` and `archiveUnpacker.sh` (state snapshot, lane logs, mode logs). 【F:spruce/scripts/runtime.sh†L35-L56】【F:spruce/scripts/archiveUnpacker.sh†L23-L47】
- `archiveUnpacker.sh` now supports `.7z.extracting` recovery and rename-before-extract flow. 【F:spruce/scripts/archiveUnpacker.sh†L64-L113】
- `firstboot.sh` now waits on **both** `pre_menu_unpacking` and `pre_cmd_unpacking`; this is stricter gating than before. 【F:spruce/scripts/firstboot.sh†L60-L84】
- `principal.sh` gating points unchanged in behavior; logging added around the same waits. 【F:spruce/scripts/principal.sh†L37-L55】
- `helperFunctions.sh` `finish_unpacking()` unchanged; power-trace helpers added near script init only. 【F:spruce/scripts/helperFunctions.sh†L38-L44】【F:spruce/scripts/helperFunctions.sh†L172-L183】

---

## 5) Behavioral Diff (directly tied to requested checks)

1. **First-boot detection**: changed from single `first_boot_${PLATFORM}` check to a marker-based lifecycle with recovery verification. 【F:spruce/scripts/runtime.sh†L80-L131】
2. **Unpacker invocation mode**: no narrowing in `runtime.sh` on `arkun-dev`; normal path still invokes default/all foreground, first-boot still `--silent` background. 【F:spruce/scripts/runtime.sh†L137-L147】
3. **Lock/flag naming/storage**: new first-boot lifecycle flags added; unpack locks still `pre_menu_unpacking`/`pre_cmd_unpacking` and still include `/tmp` support via `flag_add --tmp`/`flag_check`. 【F:spruce/scripts/runtime.sh†L80-L83】【F:spruce/scripts/helperFunctions.sh†L188-L206】
4. **`finish_unpacking()` semantics**: unchanged. 【F:spruce/scripts/helperFunctions.sh†L172-L183】
5. **`pre_menu_unpacking` gating before PyUI**: present and unchanged in location/intent. 【F:spruce/scripts/principal.sh†L36-L40】
6. **`pre_cmd_unpacking` gating before command/game launch**: present and unchanged in location/intent. 【F:spruce/scripts/principal.sh†L52-L55】
7. **`save_active` handling during unpack**: still synchronous preCmd for `save_active=true`; background preCmd worker only for false. 【F:spruce/scripts/archiveUnpacker.sh†L143-L149】

---

## 6) Root Cause Candidate

Based on repository evidence in the requested files, there is **no clear branch regression point** showing that `arkun-dev` removed required unpack gates relative to `main`.

If the observed trace shows UI progression while extraction continues, the likely interpretations (code-consistent) are:
- extraction was in `pre_cmd` lane with `save_active=false` (intentionally background until command-launch gate). 【F:spruce/scripts/archiveUnpacker.sh†L147-L149】【F:spruce/scripts/principal.sh†L52-L55】
- or a pre-existing timing window where a gate only waits if lock exists at check time (`finish_unpacking` pattern unchanged from `main`). 【F:spruce/scripts/helperFunctions.sh†L172-L183】

This second item is a behavioral risk pattern, but not a demonstrated `arkun-dev`-only regression from this diff set.

---

## 7) Confidence / Gaps

Confidence: **medium-high** for code-diff conclusions in the five requested scripts.

Gaps:
1. No concrete attached log file was present in-repo for line-by-line lane attribution (`pre_menu` vs `pre_cmd`) from the supplied trace narrative.
2. Resume-path validation here is static (code path review), not device-executed runtime trace with `save_active=true` + real `lastgame.lock` boot.
3. Investigation intentionally excludes proposing a fix.

Final determinations:
- **Primary hypothesis** (first-boot/recovery unpack gate regression in `arkun-dev`): **not confirmed** from repository diff evidence.
- **Secondary hypothesis** (`save_active=true` resume not forcing pre-cmd completion): **not supported** by code; synchronous pre-cmd path is still present.
