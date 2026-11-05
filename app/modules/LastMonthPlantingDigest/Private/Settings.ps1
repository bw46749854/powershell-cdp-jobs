# ジョブ設定（settings.psd1 の Jobs.LastMonthPlantingDigest）を、ジョブ開始時にまとめて検証して読む。
# TargetDirectory は月次の連携ジョブ（MonthlyPlantingReport）から、その回の保存先ディレクトリで上書きされる。
# 単独で実行するときは設定の TargetDirectory を使う（手動の再処理・確認用）。

function Read-PlantingDigestSettings {
    param([Parameter(Mandatory)][object]$Settings)

    $scope = 'Jobs.LastMonthPlantingDigest'
    $headers = @(Read-JobSetting -Settings $Settings -Name 'RequiredHeaders' -Kind TextList -Scope $scope)
    foreach ($meaningful in @($script:CropHeader, $script:VarietyHeader, $script:PlantedHeader)) {
        if ($headers -cnotcontains $meaningful) {
            throw "設定 $scope.RequiredHeaders には「$meaningful」が必要です（出力 CSV の列の元になるため）。"
        }
    }

    $pattern = Read-JobSetting -Settings $Settings -Name 'FileNamePattern' -Kind Pattern -Scope $scope
    if (([regex]::new($pattern)).GetGroupNumbers().Count -lt 2) {
        throw "設定 $scope.FileNamePattern には区画コードを取り出すグループ（ ）が必要です。"
    }

    return [pscustomobject]@{
        TargetDirectory = Read-JobSetting -Settings $Settings -Name 'TargetDirectory' -Kind Text -Scope $scope
        OutputCsvFileName = Read-JobSetting -Settings $Settings -Name 'OutputCsvFileName' -Kind Text -Scope $scope
        FailureCsvFileName = Read-JobSetting -Settings $Settings -Name 'FailureCsvFileName' -Kind Text -Scope $scope
        FileNamePattern = $pattern
        RequiredHeaders = $headers
    }
}
