Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# LastMonthPlantingDigest: 区画ごとの作付け記録 CSV から、先月に定植した作付けを1つの CSV に集めるジョブ。

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Records.ps1',
    'Private/Settings.ps1',
    'Private/TextDecoding.ps1',
    'Private/DelimitedText.ps1',
    'Private/Policy.ps1',
    'Private/FileDigest.ps1',
    'Private/Ports.ps1',
    'Private/Flow.ps1',
    'Public/Invoke-LastMonthPlantingDigestJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "LastMonthPlantingDigest の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-LastMonthPlantingDigestJob'
)
