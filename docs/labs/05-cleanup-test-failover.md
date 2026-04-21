# Lab 05: Cleanup Test Failover

## Objective

Clean up test failover artifacts from portal and script paths.

## Steps

1. In Recovery Services Vault, choose Clean up test failover for the VM.
2. Confirm test resources are removed from compute/network views.
3. Run:
   - `pwsh ./scripts/asr/cleanup-asr.ps1`
4. Re-run the same command once more to validate idempotency.

## Expected Outcome

No stale test failover artifacts remain.
