Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# JobChains: 既存のジョブを決まった順に実行し、前のジョブの成果物を次のジョブへ渡す連携ジョブ。
#
#   WeeklySoilAnalysisSync : PlotRosterExport → SoilAnalysisTargetSync
#   MonthlyPlantingReport  : PlantingRecordExport → LastMonthPlantingDigest
#
# 画面操作・CSV の解析・業務判定は持たない（それぞれの子ジョブの責務）。
# 子ジョブは Jobs サービス経由で、単独実行と同じ入口（設定・ジョブ定義・Context の組み立て）を通して起動する。

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Ports.ps1',
    'Private/ChainSteps.ps1',
    'Private/Weekly.ps1',
    'Private/Monthly.ps1',
    'Public/Invoke-WeeklySoilAnalysisSyncJob.ps1',
    'Public/Invoke-MonthlyPlantingReportJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "JobChains の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-WeeklySoilAnalysisSyncJob',
    'Invoke-MonthlyPlantingReportJob'
)
