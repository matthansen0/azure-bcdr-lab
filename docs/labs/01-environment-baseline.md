# Lab 01: Environment Baseline

## Objective

Deploy the sandbox and confirm foundational resources exist.

## Steps

1. Confirm defaults from the dev container (`DR_DEPLOYMENT_MODE=all`, regions, prefix) or override any value — see the **Configure (optional)** section in the root [README](../../README.md).
2. Set required secrets (not defaulted):
   - `azd env set DR_VM_ADMIN_PASSWORD <password>`
   - SQL Entra ID admin is auto-detected from your signed-in `az` session.
3. Deploy:
   - `azd up`
4. In Azure Portal, open the resource group and verify:
   - Recovery Services Vault
   - Primary and secondary virtual networks
   - Linux and Windows lab VMs
   - App Service plans and web apps in both regions
   - SQL servers and failover group

## Expected Outcome

A complete DR lab baseline is deployed with both IaaS and PaaS stacks.
