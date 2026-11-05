function Invoke-MonthlyPlantingReportJob {
    <#
    .SYNOPSIS
    月次の連携ジョブ。実行ごとのディレクトリへ PlantingRecordExport で作付け記録 CSV を保存し、
    そのディレクトリを LastMonthPlantingDigest で集計する。

    .DESCRIPTION
    どちらかの子ジョブが失敗した時点、または保存された成果物 CSV が1件もない時点で止まり、例外を呼び出し元へ伝える。
    結果の Outputs / Summary には、実行ディレクトリと、子ジョブの Outputs / Summary をジョブ名ごとに収める。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-MonthlyPlantingReportSettings -Settings $Context.Settings
    $ports = New-JobChainPorts -Context $Context
    Assert-JobChainPorts -Ports $ports

    $outcome = Invoke-MonthlyPlantingReportFlow -Ports $ports -Settings $settings

    return New-JobResult -Job 'MonthlyPlantingReport' -Outputs @{
        RunDirectory = $outcome.Run.RunDirectory
        TempDirectory = $outcome.Run.TempDirectory
        DownloadDirectory = $outcome.Run.DownloadDirectory
        ExportedCsvPaths = $outcome.ExportedCsvPaths
        PlantingRecordExport = $outcome.Export.Outputs
        LastMonthPlantingDigest = $outcome.Digest.Outputs
    } -Summary @{
        RunStamp = $outcome.Run.Stamp
        PlantingRecordExport = $outcome.Export.Summary
        LastMonthPlantingDigest = $outcome.Digest.Summary
    }
}
