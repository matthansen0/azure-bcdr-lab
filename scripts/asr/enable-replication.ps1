Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# ASR A2A replication onboarding
#
# Steps:
#   1. Create source + target fabrics (one per Azure region)
#   2. Create protection containers inside each fabric
#   3. Create an A2A replication policy
#   4. Map source container -> target container with that policy
#   5. Create a cache storage account in the source region
#   6. Create a recovery resource group in the secondary region
#   7. Enable replication (protected-item create) for every VM
# ---------------------------------------------------------------------------

function Get-AzdEnvMap {
  $envMap = @{}
  $lines = azd env get-values 2>$null
  foreach ($line in $lines) {
    if ($line -match '^([^=]+)="?(.*)"?$') {
      $envMap[$matches[1]] = $matches[2].Trim('"')
    }
  }
  return $envMap
}

function Wait-FabricReady {
  param([string]$VaultName, [string]$Rg, [string]$FabricName, [int]$MaxMinutes = 10)
  $end = (Get-Date).AddMinutes($MaxMinutes)
  while ((Get-Date) -lt $end) {
    $state = az site-recovery fabric show --vault-name $VaultName -g $Rg -n $FabricName --query 'properties.bcdrState' -o tsv 2>$null
    if ($state -eq 'Valid') { return }
    Write-Host "  Waiting for fabric $FabricName to be ready (state: $state)..."
    Start-Sleep -Seconds 15
  }
  Write-Warning "Fabric $FabricName did not become ready within $MaxMinutes minutes."
}

# ---- Pull env values ----
$envMap = Get-AzdEnvMap
$rg        = if ($envMap.ContainsKey('AZURE_RESOURCE_GROUP'))   { $envMap['AZURE_RESOURCE_GROUP'] }   else { throw 'AZURE_RESOURCE_GROUP not found.' }
$prefix    = if ($envMap.ContainsKey('DR_PREFIX'))              { $envMap['DR_PREFIX'] }              else { 'drsandbox' }
$primary   = if ($envMap.ContainsKey('AZURE_LOCATION'))         { $envMap['AZURE_LOCATION'] }         else { 'eastus2' }
$secondary = if ($envMap.ContainsKey('DR_SECONDARY_LOCATION'))  { $envMap['DR_SECONDARY_LOCATION'] }  else { 'westus2' }

$vaultName = "$prefix-rsv"
$subId     = (az account show --query id -o tsv)

az extension add --name site-recovery --upgrade --only-show-errors | Out-Null

# Verify vault
$vaultExists = az resource show --name $vaultName -g $rg --resource-type 'Microsoft.RecoveryServices/vaults' --query name -o tsv 2>$null
if (-not $vaultExists) { throw "Recovery Services vault $vaultName not found in $rg." }

# Verify VMs
$vms = az vm list -g $rg --query "[].{id:id, name:name}" -o json | ConvertFrom-Json
if (-not $vms -or $vms.Count -eq 0) {
  Write-Host 'No VMs found. Skipping ASR onboarding.'
  exit 0
}
Write-Host "Found $($vms.Count) VM(s) to protect."

# ---- Naming convention ----
$srcFabric      = "$primary-fabric"
$tgtFabric      = "$secondary-fabric"
$srcContainer   = "$primary-container"
$tgtContainer   = "$secondary-container"
$policyName     = "$prefix-a2a-policy"
$mappingName    = "$primary-to-$secondary-mapping"
$cacheAcctName  = ($prefix -replace '[^a-z0-9]','') + 'cache'
if ($cacheAcctName.Length -gt 24) { $cacheAcctName = $cacheAcctName.Substring(0, 24) }
$linuxReplGroup  = 'linux-repl-group'

# ---- 1. Fabrics ----
Write-Host "`n=== Step 1: Fabrics ==="

$existingFabric = az site-recovery fabric show --vault-name $vaultName -g $rg -n $srcFabric --query name -o tsv 2>$null
if (-not $existingFabric) {
  Write-Host "Creating source fabric ($srcFabric)..."
  az site-recovery fabric create --vault-name $vaultName -g $rg -n $srcFabric `
    --custom-details "{azure:{location:$primary}}" --no-wait
} else {
  Write-Host "Source fabric $srcFabric already exists."
}

$existingFabric = az site-recovery fabric show --vault-name $vaultName -g $rg -n $tgtFabric --query name -o tsv 2>$null
if (-not $existingFabric) {
  Write-Host "Creating target fabric ($tgtFabric)..."
  az site-recovery fabric create --vault-name $vaultName -g $rg -n $tgtFabric `
    --custom-details "{azure:{location:$secondary}}" --no-wait
} else {
  Write-Host "Target fabric $tgtFabric already exists."
}

# Wait for both fabrics
Write-Host "Waiting for fabrics to provision..."
Wait-FabricReady -VaultName $vaultName -Rg $rg -FabricName $srcFabric
Wait-FabricReady -VaultName $vaultName -Rg $rg -FabricName $tgtFabric
Write-Host "Fabrics ready."

# ---- 2. Protection containers ----
Write-Host "`n=== Step 2: Protection containers ==="

$existingContainer = az site-recovery protection-container show --vault-name $vaultName -g $rg --fabric-name $srcFabric -n $srcContainer --query name -o tsv 2>$null
if (-not $existingContainer) {
  Write-Host "Creating source container ($srcContainer)..."
  az site-recovery protection-container create --vault-name $vaultName -g $rg --fabric-name $srcFabric -n $srcContainer `
    --provider-input '[{instance-type:A2A}]'
} else {
  Write-Host "Source container $srcContainer already exists."
}

$existingContainer = az site-recovery protection-container show --vault-name $vaultName -g $rg --fabric-name $tgtFabric -n $tgtContainer --query name -o tsv 2>$null
if (-not $existingContainer) {
  Write-Host "Creating target container ($tgtContainer)..."
  az site-recovery protection-container create --vault-name $vaultName -g $rg --fabric-name $tgtFabric -n $tgtContainer `
    --provider-input '[{instance-type:A2A}]'
} else {
  Write-Host "Target container $tgtContainer already exists."
}

# Get container IDs
$srcContainerId = az site-recovery protection-container show --vault-name $vaultName -g $rg --fabric-name $srcFabric -n $srcContainer --query id -o tsv
$tgtContainerId = az site-recovery protection-container show --vault-name $vaultName -g $rg --fabric-name $tgtFabric -n $tgtContainer --query id -o tsv

# ---- 3. Replication policy ----
Write-Host "`n=== Step 3: Replication policy ==="

$existingPolicy = az site-recovery policy show --vault-name $vaultName -g $rg -n $policyName --query name -o tsv 2>$null
if (-not $existingPolicy) {
  Write-Host "Creating A2A replication policy ($policyName)..."
  az site-recovery policy create --vault-name $vaultName -g $rg -n $policyName `
    --provider-input '{a2a:{multi-vm-sync-status:Enable,recovery-point-history:1440}}'
} else {
  Write-Host "Policy $policyName already exists."
}

$policyId = az site-recovery policy show --vault-name $vaultName -g $rg -n $policyName --query id -o tsv

# ---- 4. Container mapping ----
Write-Host "`n=== Step 4: Container mapping ==="

$existingMapping = az site-recovery protection-container mapping show --vault-name $vaultName -g $rg --fabric-name $srcFabric --protection-container $srcContainer -n $mappingName --query name -o tsv 2>$null
if (-not $existingMapping) {
  Write-Host "Creating container mapping ($mappingName)..."
  az site-recovery protection-container mapping create --vault-name $vaultName -g $rg `
    --fabric-name $srcFabric --protection-container $srcContainer -n $mappingName `
    --policy-id $policyId --target-container $tgtContainerId `
    --provider-input '{a2a:{agent-auto-update-status:Disabled}}'
} else {
  Write-Host "Container mapping $mappingName already exists."
}

# ---- 5. Cache storage account ----
Write-Host "`n=== Step 5: Cache storage account ==="

$cacheExists = az storage account show -n $cacheAcctName -g $rg --query name -o tsv 2>$null
if (-not $cacheExists) {
  Write-Host "Creating cache storage account ($cacheAcctName) in $primary..."
  az storage account create -n $cacheAcctName -g $rg -l $primary --sku Standard_LRS --kind StorageV2 --only-show-errors -o none
} else {
  Write-Host "Cache storage $cacheAcctName already exists."
}
$cacheAcctId = az storage account show -n $cacheAcctName -g $rg --query id -o tsv

# Grant vault MSI access to cache storage (required when shared-key access is disabled)
$vaultMsiId = az resource show --name $vaultName -g $rg --resource-type 'Microsoft.RecoveryServices/vaults' --query 'identity.principalId' -o tsv 2>$null
if ($vaultMsiId) {
  Write-Host "Granting vault MSI ($vaultMsiId) roles on cache storage..."
  foreach ($role in @('Contributor', 'Storage Blob Data Contributor')) {
    $existing = az role assignment list --assignee $vaultMsiId --role $role --scope $cacheAcctId --query '[0].id' -o tsv 2>$null
    if (-not $existing) {
      az role assignment create --assignee-object-id $vaultMsiId --role $role --scope $cacheAcctId --assignee-principal-type ServicePrincipal -o none
      Write-Host "  Assigned $role"
    } else {
      Write-Host "  $role already assigned"
    }
  }
} else {
  Write-Warning "Vault does not have a system-assigned managed identity. Cache storage access may fail."
}

# ---- 6. Recovery resource group ----
Write-Host "`n=== Step 6: Recovery resource group ==="

$recoveryRgName = "$rg-asr-recovery"
$existingRecoveryRg = az group show -n $recoveryRgName --query name -o tsv 2>$null
if (-not $existingRecoveryRg) {
  Write-Host "Creating recovery resource group ($recoveryRgName) in $secondary..."
  az group create -n $recoveryRgName -l $secondary -o none
} else {
  Write-Host "Recovery resource group $recoveryRgName already exists."
}

# ---- 7. Enable replication for each VM ----
Write-Host "`n=== Step 7: Enable replication ==="

$recoveryVnetId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$prefix-vnet-$secondary"
$recoveryRgId   = "/subscriptions/$subId/resourceGroups/$recoveryRgName"

foreach ($vm in $vms) {
  $vmName = $vm.name
  $vmId   = $vm.id

  # Check if already protected
  $existing = az site-recovery protected-item show --vault-name $vaultName -g $rg `
    --fabric-name $srcFabric --protection-container $srcContainer -n $vmName `
    --query name -o tsv 2>$null
  if ($existing) {
    Write-Host "VM $vmName is already protected. Skipping."
    continue
  }

  # Check for in-progress EnableDr job to avoid duplicate submissions
  $pendingJob = az site-recovery job list --vault-name $vaultName -g $rg `
    --query "[?properties.scenarioName=='EnableDr' && properties.targetObjectName=='$vmName' && properties.state=='InProgress'].name | [0]" -o tsv 2>$null
  if ($pendingJob) {
    Write-Host "VM $vmName has an EnableDr job already in progress ($pendingJob). Skipping."
    continue
  }

  # Get VM disk info
  $vmDetail = az vm show --ids $vmId -o json | ConvertFrom-Json
  $osDiskId = $vmDetail.storageProfile.osDisk.managedDisk.id

  $diskList = @()
  $diskList += @{
    'disk-id'                                   = $osDiskId
    'primary-staging-azure-storage-account-id'  = $cacheAcctId
    'recovery-resource-group-id'                = $recoveryRgId
  }

  foreach ($dd in $vmDetail.storageProfile.dataDisks) {
    $diskList += @{
      'disk-id'                                   = $dd.managedDisk.id
      'primary-staging-azure-storage-account-id'  = $cacheAcctId
      'recovery-resource-group-id'                = $recoveryRgId
    }
  }

  $a2aDetails = @{
      'fabric-object-id'          = $vmId
      'recovery-azure-network-id' = $recoveryVnetId
      'recovery-container-id'     = $tgtContainerId
      'recovery-resource-group-id'= $recoveryRgId
      'vm-managed-disks'          = $diskList
  }

  # Add Linux VMs to a shared replication group for multi-VM consistency
  if ($vmDetail.storageProfile.osDisk.osType -eq 'Linux') {
    $a2aDetails['multi-vm-group-name'] = $linuxReplGroup
    Write-Host "  Adding $vmName to replication group '$linuxReplGroup'"
  }

  $providerJson = @{ 'a2a' = $a2aDetails } | ConvertTo-Json -Depth 5 -Compress

  Write-Host "Enabling replication for $vmName (no-wait)..."
  az site-recovery protected-item create --vault-name $vaultName -g $rg `
    --fabric-name $srcFabric --protection-container $srcContainer -n $vmName `
    --policy-id $policyId --provider-details $providerJson --no-wait
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "  Failed to submit replication for $vmName (exit code $LASTEXITCODE)"
  }
}

Write-Host "`n=== ASR replication onboarding complete ==="
Write-Host 'Replication jobs are running. Monitor progress in:'
Write-Host "  - Azure Continuity Center > Protected items"
Write-Host "  - Recovery Services vault > Replicated items"
Write-Host "  - az site-recovery protected-item list --vault-name $vaultName -g $rg -o table"
