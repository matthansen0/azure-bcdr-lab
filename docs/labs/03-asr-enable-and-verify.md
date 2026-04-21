# Lab 03: ASR Enable and Verify

## Objective

Enable or validate VM replication with ASR and verify status.

## Steps

1. Open Recovery Services Vault > Site Recovery > Replicated items.
2. Confirm each source VM appears as protected or ready for protection.
3. If protection is missing, complete portal-based onboarding for the VM.
4. Validate:
   - Replication health = Healthy
   - RPO values are being reported
5. Run:
   - `pwsh ./scripts/scenarios/replication-group-procedure.ps1`

## Expected Outcome

All target VMs are replication-enabled and visible in both vault and continuity views.
