Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# ASR cleanup — discovery-driven removal of ALL ASR artifacts so the vault
# and resource groups can be deleted cleanly.
#
# Strategy:
#   0. Delete all recovery plans (block fabric deletion otherwise)
#   1. Cancel any in-progress ASR jobs
#   2. For EVERY fabric/container (not just known names):
#      a. Clean up pending test failovers
#      b. Disable replication (remove protected items)
#      c. Remove all container mappings (forward + reverse)
#   3. Wait for protected items to drain
#   4. Force-delete all fabrics
#   5. Delete all replication policies
#   6. Delete cache / ASR-created storage accounts
#   7. Discover + delete all ASR-associated resource groups (locks first)
#   8. Clean orphaned VMs, NICs, public IPs, NSGs, disks, snapshots
#   9. Reset SQL failover group if swapped
#
# Handles artifacts created by automation AND manual portal lab exercises.
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

function Wait-NoProtectedItems {
  param([string]$VaultName, [string]$Rg, [string]$FabricName, [string]$ContainerName, [int]$MaxMinutes = 10)
  $end = (Get-Date).AddMinutes($MaxMinutes)
  while ((Get-Date) -lt $end) {
    $remaining = az site-recovery protected-item list --vault-name $VaultName -g $Rg `
      --fabric-name $FabricName --protection-container $ContainerName `
      --query 'length(@)' -o tsv 2>$null
    if (-not $remaining -or $remaining -eq '0') { return $true }
    Write-Host "  Still $remaining protected item(s), waiting..."
    Start-Sleep -Seconds 15
  }
  Write-Warning "Protected items not fully removed within $MaxMinutes minutes."
  return $false
}

# Helper: delete orphaned ASR/failover resources in a resource group
function Remove-OrphanedResources {
  param([string]$ResourceGroup, [switch]$All)

  $rgExists = az group show -n $ResourceGroup --query name -o tsv 2>$null
  if (-not $rgExists) { return }

  # Build JMESPath filter: in ASR RGs delete everything, in main RG match by name
  if ($All) { $filter = "[].id" }
  else { $filter = "[?contains(name,'failover') || contains(name,'asr') || contains(name,'-test')].id" }

  # VMs first (they hold NICs/disks)
  $vmIds = az vm list -g $ResourceGroup --query $filter -o tsv 2>$null
  foreach ($id in $vmIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting VM: $id"
    az vm delete --ids $id --yes --no-wait 2>$null
  }

  # Public IPs (ASR clones them during failover)
  $pipIds = az network public-ip list -g $ResourceGroup --query $filter -o tsv 2>$null
  foreach ($id in $pipIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting Public IP: $id"
    az network public-ip delete --ids $id 2>$null
  }

  # NICs
  $nicIds = az network nic list -g $ResourceGroup --query $filter -o tsv 2>$null
  foreach ($id in $nicIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting NIC: $id"
    az network nic delete --ids $id 2>$null
  }

  # NSGs (ASR clones them for failover VMs)
  $nsgIds = az network nsg list -g $ResourceGroup --query $filter -o tsv 2>$null
  foreach ($id in $nsgIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting NSG: $id"
    az network nsg delete --ids $id 2>$null
  }

  # Managed disks
  $diskFilter = if ($All) { "[].id" } else {
    "[?contains(name,'failover') || contains(name,'asr') || contains(name,'-test') || contains(name,'ASRReplica') || contains(name,'replica')].id"
  }
  $diskIds = az disk list -g $ResourceGroup --query $diskFilter -o tsv 2>$null
  foreach ($id in $diskIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting disk: $id"
    az disk delete --ids $id --yes --no-wait 2>$null
  }

  # Snapshots (ASR recovery points)
  $snapIds = az snapshot list -g $ResourceGroup --query "[].id" -o tsv 2>$null
  foreach ($id in $snapIds) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Host "    Deleting snapshot: $id"
    az snapshot delete --ids $id --no-wait 2>$null
  }
}

$envMap    = Get-AzdEnvMap
$rg        = if ($envMap.ContainsKey('AZURE_RESOURCE_GROUP'))  { $envMap['AZURE_RESOURCE_GROUP'] }  else { '' }
$prefix    = if ($envMap.ContainsKey('DR_PREFIX'))             { $envMap['DR_PREFIX'] }             else { 'drsandbox' }
$primary   = if ($envMap.ContainsKey('AZURE_LOCATION'))        { $envMap['AZURE_LOCATION'] }        else { 'eastus2' }
$secondary = if ($envMap.ContainsKey('DR_SECONDARY_LOCATION')) { $envMap['DR_SECONDARY_LOCATION'] } else { 'westus2' }
$mode      = if ($envMap.ContainsKey('DR_DEPLOYMENT_MODE'))    { $envMap['DR_DEPLOYMENT_MODE'] }    else { 'all' }

$vaultName = "$prefix-rsv"
$cacheAcctName = ($prefix -replace '[^a-z0-9]','') + 'cache'
if ($cacheAcctName.Length -gt 24) { $cacheAcctName = $cacheAcctName.Substring(0, 24) }

if ([string]::IsNullOrWhiteSpace($rg)) {
  Write-Host 'No AZURE_RESOURCE_GROUP in azd env. Skipping ASR cleanup.'
  exit 0
}

az extension add --name site-recovery --upgrade --only-show-errors | Out-Null

# Collect ASR-associated resource groups throughout the script
$asrRgs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$asrRgs.Add("$rg-asr-recovery")

$vaultExists = az resource show --name $vaultName -g $rg --resource-type 'Microsoft.RecoveryServices/vaults' --query name -o tsv 2>$null
if (-not $vaultExists) {
  Write-Host "Vault $vaultName not found. Skipping vault-level cleanup."
} else {

Write-Host "Cleaning ASR artifacts in vault $vaultName..."

# ---- 0. Delete all recovery plans ----
Write-Host "`n--- Removing recovery plans ---"
$plans = az site-recovery recovery-plan list --vault-name $vaultName -g $rg `
  --query "[].name" -o tsv 2>$null
foreach ($plan in $plans) {
  if ([string]::IsNullOrWhiteSpace($plan)) { continue }
  Write-Host "  Deleting recovery plan: $plan"
  az site-recovery recovery-plan delete --vault-name $vaultName -g $rg -n $plan 2>$null
}

# ---- 1. Cancel in-progress ASR jobs ----
Write-Host "`n--- Cancelling in-progress ASR jobs ---"
$activeJobs = az site-recovery job list --vault-name $vaultName -g $rg `
  --query "[?properties.state=='InProgress' || properties.state=='NotStarted'].name" -o tsv 2>$null
foreach ($job in $activeJobs) {
  if ([string]::IsNullOrWhiteSpace($job)) { continue }
  Write-Host "  Cancelling job: $job"
  az site-recovery job cancel --vault-name $vaultName -g $rg -n $job 2>$null
}

# ---- 2. Discover ALL fabrics and clean protected items + mappings ----
Write-Host "`n--- Discovering all fabrics ---"
$allFabrics = az site-recovery fabric list --vault-name $vaultName -g $rg `
  --query "[].name" -o tsv 2>$null

foreach ($fabric in $allFabrics) {
  if ([string]::IsNullOrWhiteSpace($fabric)) { continue }
  Write-Host "`n  Fabric: $fabric"

  $containers = az site-recovery protection-container list --vault-name $vaultName -g $rg `
    --fabric-name $fabric --query "[].name" -o tsv 2>$null

  foreach ($container in $containers) {
    if ([string]::IsNullOrWhiteSpace($container)) { continue }
    Write-Host "    Container: $container"

    # List all protected items with state details
    $items = az site-recovery protected-item list --vault-name $vaultName -g $rg `
      --fabric-name $fabric --protection-container $container `
      --query "[].{name:name, testFailoverState:properties.testFailoverState, recoveryRgId:properties.providerSpecificDetails.recoveryResourceGroupId}" `
      -o json 2>$null | ConvertFrom-Json

    foreach ($item in $items) {
      if (-not $item -or [string]::IsNullOrWhiteSpace($item.name)) { continue }
      $itemName = $item.name

      # Collect recovery RG reference
      if ($item.recoveryRgId) {
        $rgName = ($item.recoveryRgId -split '/')[-1]
        if ($rgName -ne $rg) { [void]$asrRgs.Add($rgName) }
      }

      # If a test failover is pending, clean it up first
      if ($item.testFailoverState -and $item.testFailoverState -notin @('None', 'TestFailoverCleanupCompleted', '')) {
        Write-Host "      Cleaning test failover for: $itemName (state: $($item.testFailoverState))"
        az site-recovery protected-item test-failover-cleanup --vault-name $vaultName -g $rg `
          --fabric-name $fabric --protection-container $container -n $itemName `
          --comments 'Automated cleanup during azd down' 2>$null
        Start-Sleep -Seconds 10
      }

      Write-Host "      Disabling replication: $itemName"
      az site-recovery protected-item remove --vault-name $vaultName -g $rg `
        --fabric-name $fabric --protection-container $container -n $itemName `
        --no-wait 2>$null
    }

    # Wait for items to drain in this container
    if ($items) {
      Write-Host "      Waiting for protected items to drain..."
      Wait-NoProtectedItems -VaultName $vaultName -Rg $rg -FabricName $fabric -ContainerName $container -MaxMinutes 10
    }

    # Remove ALL mappings on this container (forward and reverse)
    $mappings = az site-recovery protection-container mapping list --vault-name $vaultName -g $rg `
      --fabric-name $fabric --protection-container $container `
      --query "[].name" -o tsv 2>$null
    foreach ($m in $mappings) {
      if ([string]::IsNullOrWhiteSpace($m)) { continue }
      Write-Host "      Removing mapping: $m"
      az site-recovery protection-container mapping remove --vault-name $vaultName -g $rg `
        --fabric-name $fabric --protection-container $container -n $m 2>$null
    }
  }
}

# ---- 3. Force-delete ALL fabrics ----
Write-Host "`n--- Force-deleting all fabrics ---"
foreach ($fabric in $allFabrics) {
  if ([string]::IsNullOrWhiteSpace($fabric)) { continue }
  Write-Host "  Deleting fabric: $fabric"
  az site-recovery fabric delete --vault-name $vaultName -g $rg -n $fabric --no-wait 2>$null
}

# ---- 4. Delete all replication policies ----
Write-Host "`n--- Removing all replication policies ---"
$policies = az site-recovery policy list --vault-name $vaultName -g $rg `
  --query "[].name" -o tsv 2>$null
foreach ($p in $policies) {
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  Write-Host "  Deleting policy: $p"
  az site-recovery policy delete --vault-name $vaultName -g $rg -n $p 2>$null
}

# ---- 5. Delete cache and ASR-created storage accounts ----
Write-Host "`n--- Removing ASR storage accounts ---"
az storage account delete -n $cacheAcctName -g $rg --yes 2>$null
# ASR portal-created cache accounts often contain 'cache' in the name
$storageAccts = az storage account list -g $rg --query "[?contains(name,'cache')].name" -o tsv 2>$null
foreach ($sa in $storageAccts) {
  if ([string]::IsNullOrWhiteSpace($sa) -or $sa -eq $cacheAcctName) { continue }
  Write-Host "  Deleting storage account: $sa"
  az storage account delete -n $sa -g $rg --yes 2>$null
}

} # end vault-exists block

# ---- 6. Discover + delete ASR-associated resource groups ----
Write-Host "`n--- Discovering ASR resource groups ---"
# Add RGs found by naming convention (test failover / portal-created)
$candidateRgs = az group list `
  --query "[?contains(name, '$rg') && (contains(name, 'asr') || contains(name, 'recovery') || contains(name, '-test'))].name" `
  -o tsv 2>$null
foreach ($c in $candidateRgs) {
  if (-not [string]::IsNullOrWhiteSpace($c) -and $c -ne $rg) { [void]$asrRgs.Add($c) }
}

Write-Host "  Candidate ASR RGs ($($asrRgs.Count)): $($asrRgs -join ', ')"

foreach ($asrRg in $asrRgs) {
  $rgExists = az group show -n $asrRg --query name -o tsv 2>$null
  if (-not $rgExists) {
    Write-Host "  $asrRg not found, skipping."
    continue
  }

  # Remove ALL locks (ASR places CanNotDelete on replica disks)
  $lockIds = az lock list -g $asrRg --query "[].id" -o tsv 2>$null
  foreach ($lockId in $lockIds) {
    if ([string]::IsNullOrWhiteSpace($lockId)) { continue }
    Write-Host "  Removing lock in ${asrRg}: $lockId"
    az lock delete --ids $lockId 2>$null
  }

  Write-Host "  Deleting resource group: $asrRg"
  az group delete -n $asrRg --yes --no-wait 2>$null
}

# ---- 7. Clean orphaned ASR/failover resources in the main resource group ----
Write-Host "`n--- Cleaning orphaned ASR/failover resources in $rg ---"
Remove-OrphanedResources -ResourceGroup $rg

# Also sweep any ASR RGs that haven't finished deleting yet
foreach ($asrRg in $asrRgs) {
  $rgStillExists = az group show -n $asrRg --query name -o tsv 2>$null
  if (-not $rgStillExists) { continue }
  Write-Host "`n--- Cleaning leftover resources in $asrRg ---"
  Remove-OrphanedResources -ResourceGroup $asrRg -All
}

# ---- 8. Reset SQL failover group if in swapped state ----
if ($mode -eq 'paas' -or $mode -eq 'all') {
  Write-Host "`n--- Checking SQL failover group state ---"
  $sqlPrimary = "$prefix-sql-$primary"
  $fgName = "$prefix-sqlfg"
  $fgState = az sql failover-group show -g $rg -s $sqlPrimary -n $fgName `
    --query 'replicationRole' -o tsv 2>$null
  if ($fgState -eq 'Secondary') {
    Write-Host "  SQL failover group is swapped — failing back to $sqlPrimary..."
    az sql failover-group set-primary -g $rg -s $sqlPrimary -n $fgName 2>$null
    Write-Host "  SQL failover group reset."
  } elseif ($fgState) {
    Write-Host "  SQL failover group role: $fgState (no action needed)."
  } else {
    Write-Host "  SQL failover group not found or not accessible."
  }
}

Write-Host "`nASR cleanup pass completed."
Write-Host 'If operations are still in progress, rerun this script or wait and retry azd down.'
