# ジョブ設定（settings.psd1 の Jobs.PlantingRecordExport）を、ジョブ開始時にまとめて検証して読む。
# TempDirectory / DownloadDirectory は月次の連携ジョブ（MonthlyPlantingReport）から、実行ごとの専用ディレクトリで上書きされる。

function Read-PlantingExportSettings {
    param([Parameter(Mandatory)][object]$Settings)

    $scope = 'Jobs.PlantingRecordExport'
    return [pscustomobject]@{
        TempDirectory = Read-JobSetting -Settings $Settings -Name 'TempDirectory' -Kind Text -Scope $scope
        DownloadDirectory = Read-JobSetting -Settings $Settings -Name 'DownloadDirectory' -Kind Text -Scope $scope
        DownloadFilePrefix = Read-JobSetting -Settings $Settings -Name 'DownloadFilePrefix' -Kind Text -Scope $scope
        FailureCsvFileName = Read-JobSetting -Settings $Settings -Name 'FailureCsvFileName' -Kind Text -Scope $scope
        DownloadTimeoutSeconds = Read-JobSetting -Settings $Settings -Name 'DownloadTimeoutSeconds' -Kind Integer -Minimum 1 -Scope $scope
        DownloadStableSeconds = Read-JobSetting -Settings $Settings -Name 'DownloadStableSeconds' -Kind Integer -Minimum 0 -Scope $scope
        DetailCloseWaitSeconds = Read-JobSetting -Settings $Settings -Name 'DetailCloseWaitSeconds' -Kind Integer -Minimum 1 -Scope $scope
        MaxScanLoops = Read-JobSetting -Settings $Settings -Name 'MaxScanLoops' -Kind Integer -Minimum 1 -Scope $scope
        StallLimit = Read-JobSetting -Settings $Settings -Name 'StallLimit' -Kind Integer -Minimum 1 -Scope $scope
    }
}
