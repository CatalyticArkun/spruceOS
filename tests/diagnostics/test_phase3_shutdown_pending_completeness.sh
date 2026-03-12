#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

"$ROOT/tests/diagnostics/test_power_button_watchdog_v2_shutdown_pending.sh"
"$ROOT/tests/diagnostics/test_principal_shutdown_pending_launch_gate_contract.sh"
"$ROOT/tests/diagnostics/test_runtimehelper_autoresume_shutdown_gate_contract.sh"
"$ROOT/tests/diagnostics/test_runtimehelper_boot_action_shutdown_gate_contract.sh"
"$ROOT/tests/diagnostics/test_sleep_helper_lifecycle_gate.sh"

echo "test_phase3_shutdown_pending_completeness: PASS"
