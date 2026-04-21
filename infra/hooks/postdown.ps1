Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host 'Running ASR-aware cleanup before/after azd down...'
& "$PSScriptRoot\..\..\scripts\asr\cleanup-asr.ps1"
Write-Host 'Postdown cleanup completed.'
