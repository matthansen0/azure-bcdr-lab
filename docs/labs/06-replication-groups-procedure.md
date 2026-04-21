# Lab 06: Replication Groups Procedure

## Objective

Practice sequencing for group-based recovery execution.

## Steps

1. Start all source VMs if needed:
   - `pwsh ./scripts/scenarios/replication-group-procedure.ps1`
2. In Recovery Services Vault, create a Recovery Plan with groups:
   - Group 1: infrastructure VM(s)
   - Group 2: app VM(s)
   - Group 3: supporting workloads
3. Add manual action gates between groups.
4. Document startup order and dependencies.

## Expected Outcome

A repeatable recovery plan exists with explicit sequencing and operator checkpoints.
