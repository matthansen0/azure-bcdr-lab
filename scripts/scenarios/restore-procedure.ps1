Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [Parameter(Mandatory = $false)]
  [string]$ResourceGroup
)

if (-not $ResourceGroup) {
  $lines = azd env get-values
  foreach ($line in $lines) {
    if ($line -match '^AZURE_RESOURCE_GROUP="?(.*)"?$') {
      $ResourceGroup = $matches[1].Trim('"')
    }
  }
}

if (-not $ResourceGroup) {
  throw 'Unable to discover AZURE_RESOURCE_GROUP from azd environment.'
}

Write-Host 'Restore runbook sequence:'
Write-Host '1) Start critical VMs'
$criticalVms = az vm list -g $ResourceGroup --query "[?contains(name, 'linux-1') || contains(name, 'win-1')].name" -o tsv
foreach ($vm in $criticalVms) {
  Write-Host "Starting $vm"
  az vm start -g $ResourceGroup -n $vm --only-show-errors | Out-Null
}

Write-Host '2) Execute synthetic readiness checks'
foreach ($vm in $criticalVms) {
  $state = az vm get-instance-view -g $ResourceGroup -n $vm --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
  Write-Host "$vm => $state"
}

Write-Host '3) Complete restore checklist in docs/labs/07-restore-procedures.md'
