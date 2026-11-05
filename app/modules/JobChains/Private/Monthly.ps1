# 月次の連携: 区画ごとの作付け記録 CSV を保存し（PlantingRecordExport）、先月の定植を1つの CSV に集める（LastMonthPlantingDigest）。
#
# 実行ごとに「実行日時のディレクトリ」を作り、その中だけで受け渡す。
# 過去の実行で保存した CSV が集計に混ざらないようにするため。
#
#   <RunRootDirectory>/
#     yyyyMMdd_HHmmss/
#       planting_export_tmp/        PlantingRecordExport の一時ダウンロード先
#       planting_export_downloads/  PlantingRecordExport の保存先 = LastMonthPlantingDigest の読み取り元

$script:MonthlyRunStampFormat = 'yyyyMMdd_HHmmss'
$script:MonthlyTempFolderName = 'planting_export_tmp'
$script:MonthlyDownloadFolderName = 'planting_export_downloads'

function Read-MonthlyPlantingReportSettings {
    param([Parameter(Mandatory)][object]$Settings)

    return [pscustomobject]@{
        RunRootDirectory = Read-JobSetting -Settings $Settings -Name 'RunRootDirectory' -Kind Text -Scope 'Jobs.MonthlyPlantingReport'
    }
}

function New-MonthlyRunDirectories {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][string]$RunRootDirectory
    )

    $stamp = ([datetime](& $Ports.Clock.Now)).ToString($script:MonthlyRunStampFormat, [System.Globalization.CultureInfo]::InvariantCulture)
    $runDirectory = & $Ports.Files.EnsureDirectory -Path (Join-Path $RunRootDirectory $stamp) -Purpose '月次の実行ディレクトリ'
    $tempDirectory = & $Ports.Files.EnsureDirectory -Path (Join-Path $runDirectory $script:MonthlyTempFolderName) -Purpose '作付け記録の一時ダウンロード'
    $downloadDirectory = & $Ports.Files.EnsureDirectory -Path (Join-Path $runDirectory $script:MonthlyDownloadFolderName) -Purpose '作付け記録の保存'

    & $Ports.Log.Info -Message "実行ディレクトリ: $runDirectory"
    return [pscustomobject]@{
        Stamp = $stamp
        RunDirectory = $runDirectory
        TempDirectory = $tempDirectory
        DownloadDirectory = $downloadDirectory
    }
}

function Get-PlantingExportArtifactFilter {
    <#
    .SYNOPSIS
    PlantingRecordExport の成果物 CSV を探すファイル名フィルター（<DownloadFilePrefix>*.csv）。
    .DESCRIPTION
    保存先には失敗一覧 CSV も置かれうるため、成果物の名前の先頭（DownloadFilePrefix）で絞り込む。
    接頭辞はフィルターの一部になるので、ワイルドカード文字は受け付けない。
    #>
    param([Parameter(Mandatory)][object]$Ports)

    $exportSettings = & $Ports.Jobs.GetSettings -JobName 'PlantingRecordExport'
    $prefix = Read-JobSetting -Settings $exportSettings -Name 'DownloadFilePrefix' -Kind Text -Scope 'Jobs.PlantingRecordExport'
    if ($prefix.IndexOfAny([char[]]@('*', '?', '[', ']')) -ge 0) {
        throw "設定 Jobs.PlantingRecordExport.DownloadFilePrefix にワイルドカード文字（* ? [ ]）は使えません: $prefix"
    }
    return "$prefix*.csv"
}

function Get-PlantingExportArtifacts {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][string]$DownloadDirectory
    )

    $filter = Get-PlantingExportArtifactFilter -Ports $Ports
    $artifacts = @(& $Ports.Files.ListFiles -Directory $DownloadDirectory -Filter $filter)
    if ($artifacts.Count -eq 0) {
        throw "連携エラー: PlantingRecordExport の成果物 CSV（$filter）が保存先にありません: $DownloadDirectory"
    }

    & $Ports.Log.Info -Message "PlantingRecordExport の成果物 CSV: $($artifacts.Count) 件（$filter）"
    return , [string[]]@($artifacts | ForEach-Object { $_.FullName })
}

function Invoke-MonthlyPlantingReportFlow {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $run = New-MonthlyRunDirectories -Ports $Ports -RunRootDirectory $Settings.RunRootDirectory

    $export = Invoke-ChainStep -Ports $Ports -JobName 'PlantingRecordExport' -Overrides @{
        TempDirectory = $run.TempDirectory
        DownloadDirectory = $run.DownloadDirectory
    }
    $artifacts = Get-PlantingExportArtifacts -Ports $Ports -DownloadDirectory $run.DownloadDirectory

    $digest = Invoke-ChainStep -Ports $Ports -JobName 'LastMonthPlantingDigest' -Overrides @{ TargetDirectory = $run.DownloadDirectory }

    return [pscustomobject]@{
        Run = $run
        ExportedCsvPaths = $artifacts
        Export = $export
        Digest = $digest
    }
}
