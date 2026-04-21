# Lab 07: Restore Procedures

## Objective

Execute a practical restore runbook: start VM, run script, validate state.

## Steps

1. Start critical VM set and check power state:
   - `pwsh ./scripts/scenarios/restore-procedure.ps1`
2. Open portal and validate VM state is Running.
3. Validate network and identity dependencies.
4. Record restore timeline and blockers in your runbook notes.

## Expected Outcome

You can consistently restore critical compute in the expected sequence.
