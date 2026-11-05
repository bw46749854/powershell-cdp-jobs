Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# SoilAnalysisTargetSync: 区画一覧 CSV の判定に従い、温室コンソールの土壌分析対象チェックを ON / OFF に揃えるジョブ。

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Settings.ps1',
    'Private/RosterCsv.ps1',
    'Private/CalendarDate.ps1',
    'Private/Policy.ps1',
    'Private/Records.ps1',
    'Private/Plan.ps1',
    'Private/ScanState.ps1',
    'Private/Reconciliation.ps1',
    'Private/Ledger.ps1',
    'Private/Report.ps1',
    'Private/Page.ps1',
    'Private/Ports.ps1',
    'Private/Flow.Scan.ps1',
    'Private/Flow.ps1',
    'Public/Invoke-SoilAnalysisTargetSyncJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "SoilAnalysisTargetSync の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-SoilAnalysisTargetSyncJob'
)
