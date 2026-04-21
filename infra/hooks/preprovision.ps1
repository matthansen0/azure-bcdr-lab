Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$envMap = Get-AzdEnvMap
$mode = if ($envMap.ContainsKey('DR_DEPLOYMENT_MODE')) { $envMap['DR_DEPLOYMENT_MODE'] } else { 'all' }

if ($mode -notin @('iaas', 'paas', 'all')) {
  throw "DR_DEPLOYMENT_MODE must be one of iaas, paas, all. Current value: $mode"
}

if (($mode -eq 'iaas' -or $mode -eq 'all') -and (-not $envMap.ContainsKey('DR_VM_ADMIN_PASSWORD') -or [string]::IsNullOrWhiteSpace($envMap['DR_VM_ADMIN_PASSWORD']))) {
  Write-Warning 'DR_VM_ADMIN_PASSWORD is empty. VM deployment will fail.'
}

# Auto-detect Entra ID admin for SQL if not already set
if ($mode -eq 'paas' -or $mode -eq 'all') {
  if (-not $envMap.ContainsKey('DR_SQL_AAD_ADMIN_OID') -or [string]::IsNullOrWhiteSpace($envMap['DR_SQL_AAD_ADMIN_OID'])) {
    Write-Host 'DR_SQL_AAD_ADMIN_OID not set — detecting from signed-in user...'
    $userJson = az ad signed-in-user show -o json 2>$null | ConvertFrom-Json
    if ($userJson) {
      azd env set DR_SQL_AAD_ADMIN_NAME $userJson.userPrincipalName
      azd env set DR_SQL_AAD_ADMIN_OID $userJson.id
      $tenantId = az account show --query tenantId -o tsv
      azd env set DR_SQL_AAD_ADMIN_TENANT $tenantId
      Write-Host "Set SQL Entra admin to $($userJson.userPrincipalName) ($($userJson.id))"
    } else {
      throw 'Cannot detect signed-in user for SQL Entra admin. Set DR_SQL_AAD_ADMIN_OID manually.'
    }
  }
}

$primary = if ($envMap.ContainsKey('AZURE_LOCATION')) { $envMap['AZURE_LOCATION'] } else { 'eastus2' }
$secondary = if ($envMap.ContainsKey('DR_SECONDARY_LOCATION')) { $envMap['DR_SECONDARY_LOCATION'] } else { 'westus2' }
if ($primary -eq $secondary) {
  throw 'AZURE_LOCATION and DR_SECONDARY_LOCATION must be different regions.'
}

az extension add --name site-recovery --upgrade --only-show-errors | Out-Null
Write-Host "Preprovision checks completed. mode=$mode primary=$primary secondary=$secondary"
