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

if ($mode -eq 'iaas' -or $mode -eq 'all') {
  $autoEnable = if ($envMap.ContainsKey('DR_ASR_AUTO_ENABLE')) { $envMap['DR_ASR_AUTO_ENABLE'] } else { 'false' }
  if ($autoEnable -eq 'true') {
    Write-Host 'DR_ASR_AUTO_ENABLE=true — running automated ASR onboarding...'
    & "$PSScriptRoot\..\..\scripts\asr\enable-replication.ps1"
  } else {
    Write-Host 'IaaS resources deployed. ASR onboarding is manual (portal-first) by default.'
    Write-Host 'Start with docs/labs/02-continuity-center-orientation.md then docs/labs/03-asr-enable-and-verify.md.'
    Write-Host 'To automate ASR onboarding: azd env set DR_ASR_AUTO_ENABLE true && azd up'
  }
}

if ($mode -eq 'paas' -or $mode -eq 'all') {
  $webAppName = if ($envMap.ContainsKey('PAASWEBAPPPRIMARYNAME')) { $envMap['PAASWEBAPPPRIMARYNAME'] } else { '' }
  $failoverGroup = if ($envMap.ContainsKey('PAASSQLFAILOVERGROUPNAME')) { $envMap['PAASSQLFAILOVERGROUPNAME'] } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($webAppName)) {
    Write-Host "PaaS web app (primary): $webAppName"
  }
  if (-not [string]::IsNullOrWhiteSpace($failoverGroup)) {
    Write-Host "SQL failover group: $failoverGroup"
  }
  Write-Host 'Use docs/labs/08-paas-failover-validation.md for portal-first PaaS DR validation.'
}

Write-Host 'Postdeploy hook completed.'
