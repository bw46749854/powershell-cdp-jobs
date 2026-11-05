Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# PlantingRecordExport: 作付け台帳の区画一覧を上から順に開き、区画ごとの作付け記録 CSV を取得するジョブ。

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Settings.ps1',
    'Private/Records.ps1',
    'Private/Page.ps1',
    'Private/Ports.ps1',
    'Private/RecordTransaction.ps1',
    'Private/Flow.ps1',
    'Public/Invoke-PlantingRecordExportJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "PlantingRecordExport の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-PlantingRecordExportJob'
)
