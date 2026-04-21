# Lab 08: PaaS Failover Validation

## Objective

Validate Azure SQL failover group behavior and app-tier readiness.

## Steps

1. Open SQL server (primary) > Failover groups.
2. Review current primary/secondary role assignment.
3. Perform a planned manual failover in portal.
4. Confirm partner role inversion and DNS endpoint continuity.
5. Validate secondary web app availability in target region.

## Expected Outcome

PaaS DR path is validated with SQL failover group and dual-region app footprint.
