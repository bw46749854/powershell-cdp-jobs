# ジョブ設定（settings.psd1 の Jobs.PlotRosterExport）を、ジョブ開始時にまとめて検証して読む。

function Read-PlotRosterExportSettings {
    param([Parameter(Mandatory)][object]$Settings)

    $scope = 'Jobs.PlotRosterExport'
    $template = Read-JobSetting -Settings $Settings -Name 'OutputFileNameTemplate' -Kind Text -Scope $scope
    if ($template.IndexOf('{0}') -lt 0) {
        throw "設定 $scope.OutputFileNameTemplate には日付を入れる位置 {0} が必要です（例: plot_roster_{0}.csv）。"
    }

    return [pscustomobject]@{
        TempDirectory = Read-JobSetting -Settings $Settings -Name 'TempDirectory' -Kind Text -Scope $scope
        DownloadDirectory = Read-JobSetting -Settings $Settings -Name 'DownloadDirectory' -Kind Text -Scope $scope
        DownloadedFilePattern = Read-JobSetting -Settings $Settings -Name 'DownloadedFilePattern' -Kind Pattern -Scope $scope
        OutputFileNameTemplate = $template
        DownloadTimeoutSeconds = Read-JobSetting -Settings $Settings -Name 'DownloadTimeoutSeconds' -Kind Integer -Minimum 1 -Scope $scope
        DownloadStableSeconds = Read-JobSetting -Settings $Settings -Name 'DownloadStableSeconds' -Kind Integer -Minimum 0 -Scope $scope
        MenuTimeoutSeconds = Read-JobSetting -Settings $Settings -Name 'MenuTimeoutSeconds' -Kind Integer -Minimum 1 -Scope $scope
    }
}
