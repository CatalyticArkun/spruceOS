# Phase 3 Rollout Checklist (Power/Lifecycle Hardening)

This checklist assumes Phases 1–2 are already landed.

## Global invariants
- Raw power owner: `power_button_watchdog_v2.sh` (canonical).
- PyUI power watcher default: disabled when `SPRUCE_WATCHDOG_OWNS_POWER_BUTTON=1`.
- PyUI raw power semantics default: disabled when `SPRUCE_WATCHDOG_OWNS_POWER_BUTTON=1`.
- Prompt power actions route via backend request script: `spruce/scripts/power_request.sh`.
- Prompt reboot option should only be offered when `reboot_cmd()` is available.

## Per-target checklist

| Target | Canonical raw power owner | PyUI power watcher default | PyUI raw power semantics default | Expected short press | Expected long press | Reboot prompt expected? | Volume notes | Rollback toggle/path | Target-specific validation still needed |
|---|---|---|---|---|---|---|---|---|---|
| SmartPro | watchdog | off | off | sleep request (gate-permitting) | shutdown request | yes (target supports reboot) | no phase-3 changes | set `SPRUCE_WATCHDOG_OWNS_POWER_BUTTON=0` to re-enable legacy PyUI power path | confirm field logs under repeated presses |
| Brick | watchdog | off | off | sleep request (gate-permitting) | shutdown request | yes | no phase-3 changes | env toggle above + revert Phase1/2 commits | verify no duplicate prompts in long-hold |
| Pixel2 | watchdog | off | off | sleep request (gate-permitting) | shutdown request | yes | no phase-3 changes | env toggle above + revert commits | verify systemd path handoff remains clear |
| MiyooMini | watchdog | off (shared-node watcher volume-filtered) | off | sleep request (gate-permitting) | shutdown request | variant-dependent (guarded by `reboot_cmd()`) | shared node filtered to vol keys (114/115) in PyUI watcher | env toggle above + revert commits | confirm OG/Plus/Flip variant reboot prompt behavior |
| A30 | watchdog | off | off | sleep request (gate-permitting) | shutdown request | no (`reboot_cmd()` currently `None`) | no phase-3 changes | env toggle above + revert commits | validate that reboot option is absent in prompt |
| SmartProS | watchdog | off | off | sleep request (gate-permitting) | shutdown request | yes | no phase-3 changes | env toggle above + revert commits | verify same-node suppression remains stable |
| Flip | watchdog | off via shared defaults | off | sleep request (gate-permitting) | shutdown request | variant-dependent (guarded by `reboot_cmd()`) | no phase-3 changes | env toggle above + revert commits | confirm variant reboot capability mapping |

## Runtime validation commands
```sh
# quick power trace context
 tail -n 80 /mnt/SDCARD/Saves/spruce/power/events.jsonl
 tail -n 80 /mnt/SDCARD/Saves/spruce/power/summary.txt
 cat /mnt/SDCARD/Saves/spruce/power/state.env
```

```sh
# verify watchdog ownership default in PyUI launch environment
rg -n 'SPRUCE_WATCHDOG_OWNS_POWER_BUTTON' /mnt/SDCARD/App/PyUI/launch.sh
```

