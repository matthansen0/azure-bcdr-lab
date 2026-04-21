# Architecture

## Goals

- Provide a repeatable DR sandbox with azd automation.
- Support deployment modes `iaas`, `paas`, and `all`.
- Keep exercises portal-first and operations-oriented.
- Ensure teardown handles ASR cleanup without generated one-off scripts.

## High-Level Topology

- Primary region resource group hosts source resources.
- Secondary region resources are paired for DR scenarios.
- A Recovery Services Vault is deployed in the **secondary (recovery) region** to
  support cross-region ASR replication.
- IaaS mode deploys 2 Linux + 1 Windows source VMs by default.
- PaaS mode deploys App Service in both regions and Azure SQL failover group.

## Mode Behavior

### iaas

- Deploys:
  - Primary and secondary VNets/subnets
  - Recovery Services Vault
  - Lab VMs
- Automation:
  - ASR enablement helper on post-provision
  - ASR cleanup on pre-down and post-down

### paas

- Deploys:
  - App Service plans in primary + secondary regions
  - Web apps in primary + secondary regions
  - Azure SQL primary + secondary servers
  - Geo-secondary DB + failover group

### all

- Deploys both IaaS and PaaS stacks.

## Automation Flow

1. `preprovision.ps1`
   - Validates `DR_DEPLOYMENT_MODE` and required secrets
   - Ensures primary and secondary regions differ
   - Installs the `site-recovery` CLI extension
2. `postdeploy.ps1` (azd `postprovision`)
   - Runs `scripts/asr/enable-replication.ps1` for `iaas` / `all`
   - Surfaces PaaS outputs (web app, SQL failover group) for the labs
3. `postdown.ps1` (azd `predown` **and** `postdown`)
   - Runs `scripts/asr/cleanup-asr.ps1` before and after resource deletion
   - Removes ASR protected items, container/network mappings, and fabrics so no generated cleanup script is required

## Security and Operations Notes

- Passwords are supplied through azd environment variables.
- No credentials are hardcoded in repository files.
- SQL and App Service enforce TLS minimum 1.2.
- Labs include explicit operational checks in Continuity Center and RSV.
