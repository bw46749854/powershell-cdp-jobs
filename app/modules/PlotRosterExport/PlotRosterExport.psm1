Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# PlotRosterExport: 温室コンソールの区画一覧を CSV 出力し、保存名を付けて保存するジョブ。

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Settings.ps1',
    'Private/Naming.ps1',
    'Private/Page.ps1',
    'Private/Ports.ps1',
    'Private/Flow.ps1',
    'Public/Invoke-PlotRosterExportJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "PlotRosterExport の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-PlotRosterExportJob'
)
