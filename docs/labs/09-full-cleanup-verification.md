# Lab 09: Full Cleanup Verification

## Objective

Verify full environment teardown including ASR-linked resources.

## Steps

1. Run teardown:
   - `azd down --force --purge`
2. Validate no lingering ASR artifacts:
   - `pwsh ./scripts/asr/cleanup-asr.ps1`
3. In portal, confirm deletion of:
   - Recovery Services Vault artifacts
   - VM failover remnants
   - PaaS secondary resources
4. If any resources remain in deleting state, wait and rerun checks.

## Expected Outcome

The environment reaches a clean state without manual generated cleanup scripts.
