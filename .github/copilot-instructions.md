# Copilot Instructions — Azure DR Sandbox

## Project Overview

Azure DR Sandbox is an `azd`-powered lab environment for practicing Azure disaster recovery (DR). It deploys IaaS and/or PaaS resources across two Azure regions and provides portal-first labs using Azure Continuity Center and Recovery Services Vault.

## Architecture

- **Deployment modes:** `iaas`, `paas`, `all` (default `all`), controlled by `DR_DEPLOYMENT_MODE` env var.
- **Primary region:** `eastus2` (default). **Secondary region:** `westus2` (default).
- **IaaS path:** 2 Linux + 1 Windows VMs, protected by Azure Site Recovery (A2A).
- **PaaS path:** App Service + Azure SQL with geo-replication via failover groups.
- **IaC:** Bicep only — no Terraform, no ARM templates authored by hand.

## Repository Layout

```
azure.yaml                  # azd project definition + hook bindings
infra/
  main.bicep                # Mode-gated orchestrator (entry point)
  main.bicepparam           # Env-var-driven parameter file
  main.json                 # Pre-compiled ARM template (generated — do not hand-edit)
  hooks/
    preprovision.ps1        # Validates mode, regions, secrets before deploy
    postdeploy.ps1          # Runs ASR onboarding, surfaces PaaS outputs
    postdown.ps1            # Delegates to ASR cleanup on teardown
  modules/
    shared/                 # Networking (dual-region VNets), Recovery Services Vault
    iaas/                   # VM lab topology
    paas/                   # App Service + SQL failover group
scripts/
  asr/
    enable-replication.ps1  # Idempotent ASR A2A onboarding (7-step flow)
    cleanup-asr.ps1         # Full ASR teardown (protected items, mappings, fabrics, locks)
  scenarios/
    replication-group-procedure.ps1
    restore-procedure.ps1
docs/
  architecture.md           # Mode behavior + automation flow
  labs/                     # 10 portal-first lab exercises (01–10)
```

## Key Conventions

### Bicep
- All parameters flow from `azd env` → `main.bicepparam` → `main.bicep` → modules.
- Modules are conditionally deployed based on `deploymentMode` (`iaas`, `paas`, `all`).
- `main.json` is the compiled output of `main.bicep` — regenerate with `az bicep build -f infra/main.bicep` if the source changes. Do not edit it by hand.
- SQL uses **Entra ID-only authentication** (no SQL password auth) — required by MCAPS governance policy.
- Recovery Services Vault uses `identity.type: SystemAssigned` so ASR scripts can grant it storage roles.

### Scripts (PowerShell + Az CLI)
- All automation scripts use **PowerShell 7** and **Az CLI** (not Az PowerShell module).
- ASR scripts use the `site-recovery` Az CLI extension.
- Scripts must be idempotent — safe to re-run without errors.
- `enable-replication.ps1` flow: create fabrics → A2A containers → replication policy → container mapping → cache storage + RBAC → recovery RG → enable per-VM replication.
- `cleanup-asr.ps1` flow: disable protection → wait for removal → delete mappings → delete fabrics (force-purge) → remove locks → delete recovery RG.

### azd Hooks
- `preprovision` — validates env vars, detects signed-in user for SQL Entra admin.
- `postprovision` — enables ASR replication if `DR_ASR_AUTO_ENABLE=true`, prints PaaS outputs.
- `predown` / `postdown` — both invoke `cleanup-asr.ps1` to ensure ASR artifacts are removed before resource group deletion.

### Environment Variables
| Variable | Default | Purpose |
|---|---|---|
| `DR_DEPLOYMENT_MODE` | `all` | `iaas`, `paas`, or `all` |
| `DR_PREFIX` | `drsandbox` | Resource naming prefix |
| `AZURE_LOCATION` | `eastus2` | Primary region |
| `DR_SECONDARY_LOCATION` | `westus2` | Secondary / DR region |
| `DR_LINUX_VM_COUNT` | `2` | Number of Linux lab VMs (1–5) |
| `DR_DEPLOY_WINDOWS_VM` | `true` | Include a Windows VM |
| `DR_VM_ADMIN_USERNAME` | `azureuser` | VM admin user |
| `DR_VM_ADMIN_PASSWORD` | *(secret)* | VM admin password (set via `azd env set`) |
| `DR_ASR_AUTO_ENABLE` | `false` | Auto-enable ASR replication on deploy |
| `DR_APP_SERVICE_SKU` | `P0v3` | App Service plan SKU |

### Labs
- Labs are portal-first (Azure Portal / Continuity Center / Recovery Services Vault UI).
- Numbered 01–10 in `docs/labs/`. Follow sequentially.
- Labs reference resources deployed by `azd up` — they are not standalone.

## Design Decisions

- **No planned failover / failback automation** in v1 — labs cover this manually via portal.
- **No Terraform parity** — Bicep only.
- **No multi-subscription orchestration** — single subscription assumed.
- Cleanup automation fully removes ASR artifacts so `azd down` works cleanly without manual portal cleanup.

## Gotchas & Known Behaviors

- ASR fabric `bcdrState` takes ~2 min to become `Valid` after creation.
- `EnableDr` jobs take 15–30 min for initial replication to complete.
- ASR places `CanNotDelete` locks on replica disks in the recovery RG — cleanup must remove these locks before deleting the RG.
- A2A protection containers require `--provider-input '[{instance-type:A2A}]'` — without it, containers fail silently.
- The recovery resource group (`<rg>-asr-recovery`) must be in the **secondary** region (ASR error 150180).
