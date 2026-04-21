Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [Parameter(Mandatory = $false)]
  [string]$ResourceGroup,
  [Parameter(Mandatory = $false)]
  [string]$VaultName
)

if (-not $ResourceGroup -or -not $VaultName) {
  $lines = azd env get-values
  $envMap = @{}
  foreach ($line in $lines) {
    if ($line -match '^([^=]+)="?(.*)"?$') {
      $envMap[$matches[1]] = $matches[2].Trim('"')
    }
  }
  if (-not $ResourceGroup) { $ResourceGroup = $envMap['AZURE_RESOURCE_GROUP'] }
  if (-not $VaultName) {
    $prefix = if ($envMap.ContainsKey('DR_PREFIX')) { $envMap['DR_PREFIX'] } else { 'drsandbox' }
    $VaultName = "$prefix-rsv"
  }
}

Write-Host "Step 1: Start source VMs if stopped"
$vmNames = az vm list -g $ResourceGroup --query "[].name" -o tsv
foreach ($vm in $vmNames) {
  az vm start -g $ResourceGroup -n $vm --only-show-errors | Out-Null
}

Write-Host "Step 2: Show ASR protected items"
az site-recovery protected-item list --resource-group $ResourceGroup --vault-name $VaultName -o table

Write-Host "Step 3: Prompt operator to create/validate recovery plans in portal"
Write-Host "Open Recovery Services Vault > Site Recovery > Recovery Plans"
