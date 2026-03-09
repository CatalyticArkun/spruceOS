# xmb.7z archiveUnpacker regression investigation (Development vs arkun-dev)

## Call graph

### Direct callers of `archiveUnpacker.sh`

1. `spruce/scripts/runtime.sh`
   - **Development**
     - first boot path: `archiveUnpacker.sh --silent &` (implies `RUN_MODE=all`).
     - normal boot path: `archiveUnpacker.sh` (default `RUN_MODE=all`).
   - **arkun-dev**
     - first boot / recovery path: `archiveUnpacker.sh --silent &` (still `RUN_MODE=all`).
     - normal boot path: `archiveUnpacker.sh pre_cmd` (explicit `RUN_MODE=pre_cmd`).

2. `App/ThemeGarden/launch.sh`
   - Calls `archiveUnpacker.sh` with no args after ThemeGarden exits (default `RUN_MODE=all`).

3. `archiveUnpacker.sh` self-call
   - In `RUN_MODE=all`, when `save_active=false`, it now launches a separate worker: `archiveUnpacker.sh --silent pre_cmd &`.

### `archiveUnpacker.sh` modes and scan scope

- `RUN_MODE=all`: scans `Themes`, `archives/preMenu`, and then preCmd handling.
- `RUN_MODE=pre_cmd`: scans `archives/preCmd` only.
- In arkun-dev, archive eligibility includes both `*.7z` and `*.7z.extracting` for all-mode quick-check and per-directory scans.

## Branch comparison

## 1) Behavior in Development

- Normal boots invoke `archiveUnpacker.sh` with default mode, so `preMenu` and theme archives are always eligible every boot.
- `archiveUnpacker.sh` only iterates `*.7z` (no `.7z.extracting` recovery path).
- In all-mode and `save_active=false`, preCmd work is backgrounded within same process function call.

## 2) Behavior in arkun-dev

- Normal boots invoke only `archiveUnpacker.sh pre_cmd`; `preMenu` and `Themes` are not scanned on normal boot.
- `archiveUnpacker.sh` adds `.7z.extracting` recovery + rename-to-`.extracting` before extract.
- In all-mode and `save_active=false`, preCmd now runs via separate `--silent pre_cmd` invocation.
- Firstboot verification now treats leftover startup archives (`preMenu`, `Themes`, RA assets) as firstboot-incomplete and can force recovery path.

## 3) Latent bug present in Development too

- `runtimeHelper.sh::unstage_archive()` uses `TARGET_FOLDER` instead of `TARGET` when deciding if destination should remain `preCmd`.
- Because `TARGET_FOLDER` is unset, condition is true and destination is forced to `preMenu`.
- Therefore archives intended for preCmd are silently misrouted to preMenu in both branches.

This is a **pre-existing producer-staging bug** (not introduced by arkun-dev).

## Regression cause

The xmb.7z regression is a lifecycle/orchestration interaction, not a single unpacker defect.

1. **Pre-existing mis-staging bug** routes some intended preCmd archives into `archives/preMenu`.
2. **arkun-dev runtime change** switched normal boot unpacking from `all` to `pre_cmd` only.
3. Result: misplaced `preMenu` archives are no longer consumed in normal boot, so they persist.
4. Persisting archives become repeatedly eligible whenever an all-mode caller runs (`firstboot` recovery path, ThemeGarden exit, manual all-mode runs).
5. arkun-dev firstboot verification now invalidates completion when startup dirs still contain archives, which can re-trigger recovery and re-exposure loops.

### `.7z.extracting` recovery and silent pre_cmd effects

- `.7z.extracting` recovery did **not** create the core regression, but it increases persistence visibility: interrupted extracts remain eligible in all-mode checks and scans.
- Silent pre_cmd worker split also did **not** create the core regression; it changes execution mechanics for preCmd only.
- The main trigger is caller orchestration narrowing normal-boot coverage (`all` -> `pre_cmd`) while producer mis-staging still feeds `preMenu`.

## Ownership by layer

Per architectural rule (unpacker is execution engine, not install-policy engine):

1. **Producer staging (primary owner)**
   - Must stage each archive to correct lane (`preMenu` vs `preCmd`) deterministically.
   - Fix `unstage_archive` target-selection bug.

2. **Caller orchestration (secondary owner)**
   - Runtime must ensure startup-critical lanes are eventually drained in expected lifecycle windows.
   - If normal boot intentionally limits to `pre_cmd`, orchestration needs explicit reconciliation for startup lanes to prevent orphaned preMenu archives.

3. **Unpacker eligibility (supporting owner)**
   - Keep `.7z.extracting` recovery for robustness.
   - Eligibility should stay mechanical and mode-scoped; avoid embedding policy-specific lane rules in unpacker.

## Immediate containment fix

Low-risk containment to stop repeated xmb.7z eligibility quickly:

1. Fix `runtimeHelper.sh::unstage_archive()` typo (`TARGET_FOLDER` -> `TARGET`) so requested `preCmd` target is respected.
2. Add one-time migration in startup orchestration (runtime helper) to move known preCmd-owned archives accidentally left in `preMenu` into `preCmd`.
3. Add logging for lane corrections so field logs clearly show migration decisions.

This contains the loop without turning unpacker into policy logic.

## Correct architectural fix

Split fix across producer + orchestration; keep unpacker as engine.

### Producer staging

- Make staging metadata explicit (archive + intended lane), validated before move.
- Fail/alert on unknown lane instead of silent fallback to preMenu.

### Caller orchestration

- Define lifecycle contract:
  - startup-critical lanes consumed during firstboot/recovery,
  - command-critical lanes consumed before command launch,
  - orphan detection for archives present in a lane not scheduled for current boot phase.
- If normal boot remains `pre_cmd` only, add cheap orphan detector that logs and optionally schedules safe deferred all-mode drain at controlled point.

### Unpacker

- Keep mode-based scan boundaries and `.extracting` recovery.
- Optionally return structured status (or marker files) for caller observability, but avoid policy branching by archive name/ownership.

## Concrete patch plan

1. **Fix mis-staging bug** in `runtimeHelper.sh`.
2. **Add regression tests** (shell tests) for `unstage_archive`:
   - passing `preCmd` stages into `archives/preCmd`.
   - default/invalid lane goes to `preMenu` only by explicit rule.
3. **Add startup orphan check** in runtime:
   - detect preCmd-owned archive patterns in `preMenu` and relocate/log.
4. **Add lifecycle test matrix**:
   - Development-style all-mode boot,
   - arkun-dev pre_cmd-only normal boot,
   - firstboot recovery with leftover startup archives,
   - interrupted `.7z.extracting` recovery.
5. **Audit non-runtime callers** (ThemeGarden) to ensure post-app all-mode run is intentional and safe.

## Validation plan

1. Unit-style shell tests for `unstage_archive` target behavior.
2. Integration boot simulations with temp dirs:
   - stage `xmb.7z` as preCmd-owned; verify it reaches preCmd and is consumed in `pre_cmd` mode.
   - simulate interrupted extract (`.7z.extracting`) and ensure one successful recovery removes archive.
3. Verify firstboot completion markers are not invalidated by mis-staged preCmd artifacts.
4. Verify repeated eligibility is gone:
   - run runtime normal boot twice,
   - run ThemeGarden exit hook,
   - confirm no residual `xmb.7z` / `.extracting` in startup lanes unless extract genuinely failed.
5. Log verification:
   - confirm clear entries for stage lane decision, relocation, and unpack mode execution.
