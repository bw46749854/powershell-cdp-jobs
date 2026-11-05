# ジョブ設定（settings.psd1 の Jobs.SoilAnalysisTargetSync）を、ジョブ開始時にまとめて検証して読む。
# InputCsvPath は週次の連携ジョブ（WeeklySoilAnalysisSync）から、直前に出力した区画一覧 CSV で上書きされる。

function Read-SoilAnalysisSyncSettings {
    param([Parameter(Mandatory)][object]$Settings)

    $scope = 'Jobs.SoilAnalysisTargetSync'
    return [pscustomobject]@{
        InputCsvPath = Read-JobSetting -Settings $Settings -Name 'InputCsvPath' -Kind Text -Scope $scope
        OutputDirectory = Read-JobSetting -Settings $Settings -Name 'OutputDirectory' -Kind Text -Scope $scope
        CsvErrorFileName = Read-JobSetting -Settings $Settings -Name 'CsvErrorFileName' -Kind Text -Scope $scope
        FailureCsvFileName = Read-JobSetting -Settings $Settings -Name 'FailureCsvFileName' -Kind Text -Scope $scope
        DaysThreshold = Read-JobSetting -Settings $Settings -Name 'DaysThreshold' -Kind Integer -Minimum 1 -Scope $scope
        MaxScanLoops = Read-JobSetting -Settings $Settings -Name 'MaxScanLoops' -Kind Integer -Minimum 1 -Scope $scope
        StallLimit = Read-JobSetting -Settings $Settings -Name 'StallLimit' -Kind Integer -Minimum 1 -Scope $scope
    }
}
