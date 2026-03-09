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

Evaluation of trigger strength:
- Current evidence indicates the **observable regression trigger** is the orchestration narrowing from all-mode to pre_cmd on normal boot.
- Restoring broader lane draining on normal boot would likely eliminate the repeated-eligibility symptom in most cases by converging startup queues every boot.
- This does not remove latent design debt (lane mismatch + staging bug), but it reduces user-visible persistence loops while those defects are corrected.

### Alternative Remediation Strategy: Restore Development-Style Lane Draining

Development-era normal boot drained startup lanes aggressively (`RUN_MODE=all`), which both masked lane-contract fragility and ensured practical convergence of queued archives.

Potential benefits of restoring this behavior:
- Simpler operational model: one normal-boot path drains all startup lanes.
- Lower risk of stranded archives when staging/lane metadata is imperfect.
- Avoids adding install-policy complexity inside `archiveUnpacker.sh`.
- Likely resolves xmb.7z persistence/re-eligibility symptom quickly.

Potential downsides:
- More boot-time extraction work, even when only preCmd content is strictly required.
- More frequent archive scanning may increase startup cost on slow SD cards.
- On resource-constrained devices, broader extraction attempts can increase transient runtime pressure.

Overall assessment:
- As a containment/stabilization move, reverting normal boot toward Development-style all-lane draining is low-risk architecturally and keeps policy in orchestration, not in unpacker internals.

## Regression Trigger vs Latent Design Debt

- **Why the system worked before:**
  - Development’s normal boot used all-mode, which drained multiple lanes every boot and masked lane-contract weaknesses.
- **What changed to expose the issue:**
  - arkun-dev narrowed normal boot to `pre_cmd`, so only one lane is drained by default; latent lane mismatches and staging errors became externally visible as repeated eligibility.
- **Why unpacker is not root cause:**
  - `archiveUnpacker.sh` executes queue extraction for requested lanes/modes. It does not decide archive lifecycle ownership or lane policy and should not become archive-name policy logic.

## Extraction Reliability on MiyooMini-Class Devices

MiyooMini-family hardware operates with tight RAM margins, and this materially affects extraction reliability:

- `7zr x` can fail or be interrupted under memory pressure, especially when multiple startup tasks overlap.
- Persistent `.7z.extracting` files may therefore represent interrupted extraction/recovery state, not only lane-policy defects.
- Development’s broader all-lane draining may have masked some of this by retrying and converging queues more often across boots.

Interpretation:
- Memory pressure is a **secondary contributing factor** and an amplifier of persistence behavior.
- Current evidence does **not** prove memory pressure is the primary root cause of the branch regression; orchestration narrowing remains the leading trigger.

## Ownership by layer

Per architectural rule (`archiveUnpacker.sh` is an execution engine, not an install-policy engine):

1. **Producer / staging layer (primary ownership)**
   - Owns correct lane selection at production/staging time.
   - Owns archive lifecycle intent and lane contract clarity for each artifact class.
   - Must fix `unstage_archive` lane selection bug.

2. **Caller / orchestration layer (primary ownership for runtime behavior)**
   - Owns boot lifecycle sequencing and guarantees that required lanes are drained at the right times.
   - Owns the decision to drain all lanes (`RUN_MODE=all`) vs narrowed drains (`RUN_MODE=pre_cmd`) per boot phase.
   - Must ensure narrowing does not strand startup-critical work.

3. **`archiveUnpacker.sh` (execution engine ownership)**
   - Scans mode-selected queues, performs extraction, and handles `.7z`/`.7z.extracting` recovery.
   - Coordinates unpack concurrency safely.
   - Should remain generic and queue-driven.
   - Should not embed archive-specific install policy or artifact ownership rules.

## Immediate containment fix

Two viable containment paths:

### Option A — Restore Development-style behavior (preferred stabilization path)

1. Change normal boot back to all-lane drain (`archiveUnpacker.sh` default/all mode).
2. Keep firstboot/recovery all-mode behavior intact.
3. Pair with staging typo fix and improved logging.

Rationale:
- Fastest route to convergence.
- Lowest risk of introducing new policy logic.
- Aligns with proven historical behavior.

### Option B — Keep `pre_cmd` narrowing but strengthen orchestration

1. Retain `archiveUnpacker.sh pre_cmd` on normal boot.
2. Add explicit orchestration windows that drain startup lanes (`Themes`/`preMenu`) at controlled lifecycle points.
3. Add startup lane-residue detection and deterministic remediation.

Rationale:
- Preserves reduced normal-boot scope.
- Requires tighter orchestration contracts and higher lifecycle complexity.

Common requirements for either option:
- Fix `runtimeHelper.sh::unstage_archive()` typo (`TARGET_FOLDER` -> `TARGET`).
- Improve logging for lane decisions, `.7z.extracting` recovery, and extraction failures.
- Do not implement archive-name-specific install policy in `archiveUnpacker.sh`.

## Correct architectural fix

Long-term fix should be split across staging and orchestration, with unpacker kept as engine:

### Producer staging

- Make lane assignment explicit and validated.
- Enforce lane contract invariants for startup-critical vs command-critical artifacts.
- Fail loudly (or quarantine) on invalid lane metadata rather than silently defaulting.

### Caller orchestration

- Define and enforce lifecycle drain contract per boot phase.
- Choose and document a stable strategy:
  - either Development-style all-lane normal boot,
  - or narrowed normal boot with explicit scheduled startup-lane drains.
- Add orphan-lane detection/telemetry so stranded archives are surfaced before user-visible loops.

### Unpacker

- Keep mode-based scan boundaries and `.extracting` recovery.
- Improve diagnostics and status signaling for callers.
- Do not add archive-specific install policy logic.

## Concrete patch plan

1. **Fix staging bug** in `runtimeHelper.sh` (`TARGET_FOLDER` -> `TARGET`).
2. **Evaluate normal-boot invocation strategy**:
   - Candidate revert to Development-style:
     - `archiveUnpacker.sh`
   - Instead of narrowed mode:
     - `archiveUnpacker.sh pre_cmd`
3. **If pre_cmd narrowing is retained**:
   - add orchestration guardrails that explicitly drain startup lanes at defined lifecycle points,
   - add residual-lane detection and deterministic remediation.
4. **Improve extraction diagnostics**:
   - log `.7z.extracting` detection and recovery path clearly,
   - log extraction failure causes distinctly from eligibility/scan decisions,
   - preserve clear mode/caller provenance in logs.
5. **Add regression tests** for lane assignment and orchestration behavior:
   - preCmd target correctness,
   - startup-lane convergence across selected normal-boot strategy.

## Validation plan

1. Unit-style shell tests for `unstage_archive` target behavior.
2. Boot-path matrix tests:
   - Development-style normal boot (`RUN_MODE=all`).
   - arkun-dev style normal boot (`RUN_MODE=pre_cmd`).
   - firstboot/recovery all-mode behavior.
3. MiyooMini-class low-memory scenarios:
   - induce constrained-memory extraction conditions,
   - verify failure logging, retry behavior, and eventual convergence.
4. `.7z.extracting` recovery convergence tests:
   - simulate interrupted extraction,
   - verify recovery converges and does not loop indefinitely.
5. Repeated-cycle tests:
   - multiple consecutive boots,
   - ThemeGarden exit all-mode invocation,
   - confirm no persistent xmb.7z re-eligibility absent real extraction failure.
6. Lane-integrity tests:
   - verify staging bugs do not strand artifacts in the wrong lane after fix,
   - verify orchestration drains required lanes per selected strategy.
7. Log verification:
   - confirm clear records for lane assignment, caller mode, extraction start/fail/success, and recovery decisions.

## Uncertainty note

Current evidence indicates the primary regression trigger is the normal-boot orchestration change in arkun-dev (`all` -> `pre_cmd`).

However, low-memory extraction failures on MiyooMini-class hardware and latent staging bugs can amplify persistence symptoms. Validation should explicitly monitor both factors while evaluating containment choice (Option A vs Option B).
