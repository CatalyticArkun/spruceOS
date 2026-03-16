#!/bin/sh

# Legacy compatibility shim. The trace framework now lives entirely in
# trace.sh; sourcing this file should behave the same for older callers.

TRACE_CORE_SCRIPT="${TRACE_CORE_SCRIPT:-/mnt/SDCARD/spruce/scripts/trace.sh}"

if [ -f "$TRACE_CORE_SCRIPT" ]; then
    # shellcheck disable=SC1090
    . "$TRACE_CORE_SCRIPT"
else
    power_trace_emit() { return 0; }
    power_trace_boot_reconcile_pending() { return 0; }
    power_trace_shutdown_pending() { return 1; }
    power_trace_recent_json() { return 0; }
fi
