function Invoke-PlotRosterExportJob {
    <#
    .SYNOPSIS
    温室コンソールの区画一覧（全区画（既定））を CSV 出力し、保存先に「plot_roster_MMdd.csv」の形で保存する。

    .DESCRIPTION
    Outputs.ExportedCsvPath に保存した CSV のパスを返す。週次の連携ジョブ（WeeklySoilAnalysisSync）は
    この CSV を SoilAnalysisTargetSync の入力にする。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-PlotRosterExportSettings -Settings $Context.Settings
    $ports = New-PlotRosterExportPorts -Context $Context
    Assert-PlotRosterExportPorts -Ports $ports

    $outcome = Invoke-PlotRosterExportFlow -Ports $ports -Settings $settings

    return New-JobResult -Job 'PlotRosterExport' -Outputs @{
        DownloadedCsvPath = $outcome.DownloadedCsvPath
        ExportedCsvPath = $outcome.ExportedCsvPath
    }
}
