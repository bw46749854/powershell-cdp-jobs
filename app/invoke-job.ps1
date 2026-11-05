<#
.SYNOPSIS
ジョブを1つ実行する入口。運用ではリポジトリ直下の .bat から、保守では直接呼び出す。

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File app\invoke-job.ps1 -JobName WeeklySoilAnalysisSync
.EXAMPLE
pwsh -File app/invoke-job.ps1 -JobName LastMonthPlantingDigest -SettingsPath ./my-settings.psd1

.NOTES
Windows PowerShell 5.1 で動くこと。PowerShell 7 専用の構文は使わない。
#>
param(
    [Parameter(Mandatory)][string]$JobName,
    [string]$SettingsPath = '',
    [string]$CatalogPath = ''
)

$ErrorActionPreference = 'Stop'

$appRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($appRoot)) { $appRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

Import-Module -Name (Join-Path $appRoot 'modules/JobHost/JobHost.psm1') -Force -DisableNameChecking

[void](Invoke-HostedJob -AppRoot $appRoot -JobName $JobName -SettingsPath $SettingsPath -CatalogPath $CatalogPath)
