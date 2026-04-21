# Lab 04: Test Failover Exercise

## Objective

Perform a non-disruptive ASR test failover for one VM.

## Steps

1. In Recovery Services Vault, open the replicated item for a Linux VM.
2. Choose Test failover.
3. Select the test-failover subnet in the secondary region.
4. Monitor job completion in Site Recovery jobs.
5. Validate that the test VM starts in the isolated network.

## Expected Outcome

A test failover VM is created in the target region without affecting production/source VMs.
