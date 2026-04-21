# Lab 01: Environment Baseline

## Objective

Deploy the sandbox and confirm foundational resources exist.

## Steps

1. Confirm defaults from the dev container (`DR_DEPLOYMENT_MODE=iaas`, regions, prefix) or override any value — see the **Configure (optional)** section in the root [README](../../README.md).
2. Set required secrets (not defaulted):
   - `azd env set DR_VM_ADMIN_PASSWORD <password>`
   - SQL Entra ID admin is auto-detected from your signed-in `az` session.
3. Deploy:
   - `azd up`
4. In Azure Portal, open the resource group and verify:
   - Recovery Services Vault
   - Primary and secondary virtual networks
   - Linux and Windows lab VMs
   - If using `DR_DEPLOYMENT_MODE=all`, also verify App Service plans/web apps in both regions and SQL servers/failover group

## Expected Outcome

A DR lab baseline is deployed for the selected mode (IaaS by default; both stacks when mode is `all`).
