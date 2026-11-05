function Invoke-WeeklySoilAnalysisSyncJob {
    <#
    .SYNOPSIS
    週次の連携ジョブ。PlotRosterExport で区画一覧 CSV を出力し、その CSV で SoilAnalysisTargetSync を実行する。

    .DESCRIPTION
    どちらかの子ジョブが失敗した時点で止まり、例外を呼び出し元へ伝える（後続の子ジョブは動かさない）。
    結果の Outputs / Summary には、子ジョブの Outputs / Summary をジョブ名ごとに収める。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $ports = New-JobChainPorts -Context $Context
    Assert-JobChainPorts -Ports $ports

    $outcome = Invoke-WeeklySoilAnalysisSyncFlow -Ports $ports

    return New-JobResult -Job 'WeeklySoilAnalysisSync' -Outputs @{
        InputCsvPath = $outcome.InputCsvPath
        PlotRosterExport = $outcome.Export.Outputs
        SoilAnalysisTargetSync = $outcome.Sync.Outputs
    } -Summary @{
        PlotRosterExport = $outcome.Export.Summary
        SoilAnalysisTargetSync = $outcome.Sync.Summary
    }
}
