# Agent Prompt Reference

## Diff-first Review Prompt
"Read telemetry_event.json and check_results.txt first. Explain only WARN/FAIL deltas and signature count increases since last run."

## Triage Prompt
"Given signature counts and RESULT lines, classify likely root cause, confidence, and minimal next flag-gated verifier to run."

## Check Design Prompt
"Design a new low-I/O detector check with deterministic evidence token and stable RESULT schema compliance."
