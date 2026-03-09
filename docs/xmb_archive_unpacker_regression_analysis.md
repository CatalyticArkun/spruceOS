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
   - In `RUN_MODE=all`, when `save_active=false`, it launches a separate worker: `archiveUnpacker.sh --silent pre_cmd &`.

### `archiveUnpacker.sh` modes and scan scope

- `RUN_MODE=all`: scans `Themes`, `archives/preMenu`, and then preCmd handling.
- `RUN_MODE=pre_cmd`: scans `archives/preCmd` only.
- In arkun-dev, archive eligibility includes both `*.7z` and `*.7z.extracting` for all-mode quick-check and per-directory scans.

## Branch comparison

### 1) Behavior in Development

- Normal boots invoke `archiveUnpacker.sh` with default mode, so `preMenu` and theme archives are always eligible every boot.
- `archiveUnpacker.sh` iterates `*.7z` only (no `.7z.extracting` recovery path).
- In all-mode and `save_active=false`, preCmd work is backgrounded from within the all-mode flow.
- Historically, the staged model included archives such as `xmb.7z` in the preCmd lane, and that remained workable because normal boot still ran all-mode and therefore drained all startup lanes.

### 2) Behavior in arkun-dev

- Normal boots invoke only `archiveUnpacker.sh pre_cmd`; `preMenu` and `Themes` are not scanned on normal boot.
- `archiveUnpacker.sh` adds `.7z.extracting` recovery + rename-to-`.extracting` before extract.
- In all-mode and `save_active=false`, preCmd now runs via separate `--silent pre_cmd` invocation.
- Firstboot verification treats leftover startup archives (`preMenu`, `Themes`, RA assets) as firstboot-incomplete and can force recovery path.

### 3) Latent bugs and design debt present before the regression trigger

- `runtimeHelper.sh::unstage_archive()` uses `TARGET_FOLDER` instead of `TARGET` when deciding if destination should remain `preCmd`.
- Because `TARGET_FOLDER` is unset, the condition is true and destination is forced to `preMenu`.
- Separately, there is historical lane/content design debt around startup-critical content placement and lane semantics (including historical `xmb.7z` placement in preCmd), which previously did not fail visibly while normal boot drained all lanes.

These are pre-existing issues that increase fragility, but they are not by themselves the branch regression trigger.

## Regression cause

The observed xmb.7z regression is a three-part interaction across layers:

1. **Historical design assumption / lane-content mismatch risk**
   - `xmb.7z` historically lived in `preCmd` in the staged model, reflecting older lifecycle assumptions.
2. **Caller orchestration change in arkun-dev**
   - Normal boot changed from `RUN_MODE=all` to `RUN_MODE=pre_cmd`, narrowing which lanes are drained during standard startup.
3. **Latent staging bug**
   - `unstage_archive()` lane selection typo (`TARGET_FOLDER` vs `TARGET`) can misroute intended preCmd artifacts to preMenu.

How this exposes the regression:
- Under Development, all-mode normal boot masked lane fragility by draining preMenu/themes alongside preCmd every startup.
- Under arkun-dev, pre_cmd-only normal boot no longer drains startup lanes broadly; any lane mismatch or misrouting leaves archives resident longer and repeatedly eligible when an all-mode caller later runs (firstboot/recovery, ThemeGarden exit, or manual all-mode invocation).
- `.7z.extracting` recovery and silent pre_cmd worker changes affect retry/recovery mechanics, but they are not the root install-policy defect.

## Regression Trigger vs Latent Design Debt

- **Why the system worked before:**
  - Development’s normal boot used all-mode, which drained multiple lanes every boot and masked lane-contract weaknesses.
- **What changed to expose the issue:**
  - arkun-dev narrowed normal boot to `pre_cmd`, so only one lane is drained by default; latent lane mismatches and staging errors became externally visible as repeated eligibility.
- **Why unpacker is not root cause:**
  - `archiveUnpacker.sh` executes queue extraction for requested lanes/modes. It does not decide archive lifecycle ownership or lane policy and should not become archive-name policy logic.

## Ownership by layer

Per architectural rule (`archiveUnpacker.sh` is an execution engine, not an install-policy engine):

1. **Producer / staging layer (primary ownership)**
   - Owns correct lane selection at production/staging time.
   - Owns archive lifecycle intent and lane contract clarity for each artifact class.
   - Must fix `unstage_archive` lane selection bug.

2. **Caller / orchestration layer (primary ownership for runtime behavior)**
   - Owns boot lifecycle sequencing and guarantees that required lanes are drained at the right times.
   - Must ensure narrowing from all-mode to pre_cmd-only does not strand startup-critical work.

3. **`archiveUnpacker.sh` (execution engine ownership)**
   - Scans mode-selected queues, performs extraction, and handles `.7z`/`.7z.extracting` recovery.
   - Should remain generic and queue-driven.
   - Should not embed archive-specific install policy or lane-ownership rules.

## Immediate containment fix

Low-risk containment to stop repeated xmb.7z eligibility quickly:

1. Fix `runtimeHelper.sh::unstage_archive()` typo (`TARGET_FOLDER` -> `TARGET`) so requested `preCmd` target is respected.
2. Optionally add one-time startup relocation for clearly misrouted artifacts discovered in the wrong lane.
3. Improve logging around lane decisions, relocation, and mode execution to make field diagnosis deterministic.

Containment must remain outside unpacker install policy (no archive-name-specific behavior inside `archiveUnpacker.sh`).

## Correct architectural fix

Long-term fix should be split across staging and orchestration, with unpacker kept as engine:

### Producer staging

- Make lane assignment explicit and validated.
- Enforce lane contract invariants for startup-critical vs command-critical artifacts.
- Fail loudly (or quarantine) on invalid lane metadata rather than silently defaulting.

### Caller orchestration

- Define and enforce lifecycle drain contract per boot phase.
- If normal boot remains pre_cmd-only, add explicit orchestration for startup-lane reconciliation at controlled lifecycle points.
- Add orphan-lane detection/telemetry so stranded archives are surfaced before user-visible loops.

### Unpacker

- Keep mode-based scan boundaries and `.extracting` recovery.
- Optionally expose better status signaling for callers.
- Do not add archive-specific install policy logic.

## Concrete patch plan

1. **Fix staging bug** in `runtimeHelper.sh` (`TARGET_FOLDER` -> `TARGET`).
2. **Add regression tests** (shell tests) for `unstage_archive` target behavior:
   - passing `preCmd` stages into `archives/preCmd`.
   - invalid/empty target behavior is explicit and tested.
3. **Add orchestration guardrails** in runtime:
   - detect/telemetry for unexpected residual startup-lane archives when boot path is pre_cmd-only.
   - optional one-time relocation for known wrong-lane artifacts.
4. **Define lane contract documentation** (artifact class -> lane -> required drain phase).
5. **Audit non-runtime all-mode callers** (ThemeGarden and other explicit all-mode invocations) to confirm they are intentional and lifecycle-safe.

## Validation plan

1. Unit-style shell tests for `unstage_archive` target behavior.
2. Integration boot simulations with temp dirs:
   - stage `xmb.7z` under historical preCmd assumptions and verify expected behavior under each boot mode.
   - verify wrong-lane staged archives are detected and handled by orchestration guardrails.
   - simulate interrupted extract (`.7z.extracting`) and ensure recovery is single-pass and convergent.
3. Branch-mode parity checks:
   - Development-style all-mode normal boot behavior.
   - arkun-dev pre_cmd-only normal boot behavior with lane contract enforcement.
4. Verify firstboot completion markers are not invalidated by avoidable lane-orchestration mismatches.
5. Repeatability test:
   - run normal boot twice,
   - run ThemeGarden exit hook,
   - confirm no repeated xmb.7z eligibility unless extraction genuinely failed.
6. Log verification:
   - confirm clear entries for lane assignment, relocation (if applied), caller mode, and unpacker recovery decisions.
