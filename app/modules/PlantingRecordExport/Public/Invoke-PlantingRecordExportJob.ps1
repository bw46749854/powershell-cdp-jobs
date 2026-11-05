function Invoke-PlantingRecordExportJob {
    <#
    .SYNOPSIS
    作付け台帳の区画一覧を上から順に処理し、区画ごとの作付け記録 CSV を「planting_YYYYMMDD_<区画コード>.csv」で保存する。

    .DESCRIPTION
    区画ごとの失敗は失敗一覧 CSV に残し、全区画を処理し終えてから異常終了する。
    月次の連携ジョブ（MonthlyPlantingReport）は、保存先（DownloadDirectory）を LastMonthPlantingDigest の入力にする。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-PlantingExportSettings -Settings $Context.Settings
    $ports = New-PlantingExportPorts -Context $Context
    Assert-PlantingExportPorts -Ports $ports

    $outcome = Invoke-PlantingExportFlow -Ports $ports -Settings $settings

    return New-JobResult -Job 'PlantingRecordExport' -Outputs @{
        DownloadDirectory = $settings.DownloadDirectory
        ExportedCsvPaths = @($outcome.Successes | ForEach-Object { $_.CsvPath })
        FailurePath = $outcome.FailurePath
    } -Summary @{
        Total = $outcome.Total
        Processed = $outcome.Traversal.VisitedCount
        Succeeded = @($outcome.Successes).Count
    }
}
