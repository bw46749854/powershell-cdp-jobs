# 処理の順序: 対象ディレクトリの CSV を名前順に読み、ファイルごとに集約して、結果 CSV と失敗一覧 CSV を出す。
#
# ファイル単位・行単位の問題は失敗一覧に残して処理を続ける（1ファイルの不備で全体の集計を止めない）。
# 結果 CSV は0件でも見出し行だけで必ず作る（「該当なし」と「未実行」を区別するため）。

function Get-DigestSourceFiles {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $excluded = @($Settings.OutputCsvFileName, $Settings.FailureCsvFileName)
    return @(& $Ports.Files.ListFiles -Directory $Settings.TargetDirectory -Filter '*.csv' | Where-Object { $excluded -notcontains $_.Name })
}

function Invoke-PlantingDigestFlow {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $log = $Ports.Log
    $files = $Ports.Files
    $now = [datetime](& $Ports.Clock.Now)
    $timestamp = $now.ToString('yyyy-MM-dd HH:mm:ss')
    $range = New-LastMonthRange -Now $now

    [void](& $files.EnsureDirectory -Path $Settings.TargetDirectory -Purpose '先月の定植の集約')
    $sources = @(Get-DigestSourceFiles -Ports $Ports -Settings $Settings)
    & $log.Info -Message "読み取り対象の CSV: $($sources.Count) 件（$($Settings.TargetDirectory)）"
    & $log.Info -Message "対象期間: $($range.StartInclusive.ToString('yyyy-MM-dd')) 以上 $($range.EndExclusive.ToString('yyyy-MM-dd')) 未満"

    $rows = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[object]
    $processed = 0
    $skipped = 0
    $readRows = 0

    foreach ($source in $sources) {
        try {
            $bytes = & $files.ReadBytes -Path $source.FullName
            $digest = Invoke-FileDigest -FileName $source.Name -Bytes $bytes -Range $range -RequiredHeaders $Settings.RequiredHeaders -FileNamePattern $Settings.FileNamePattern
        }
        catch {
            $digest = New-FileDigestResult -Skipped $true -Failures @(New-DigestFailure -FileName $source.Name -Reason "ファイルを読めないため飛ばしました: $($_.Exception.Message)")
        }

        foreach ($failure in $digest.Failures) {
            $failure.Timestamp = $timestamp
            & $log.Warn -Message "$($failure.FileName) $($failure.LineNumber): $($failure.Reason)"
            [void]$failures.Add($failure)
        }

        if ($digest.Skipped) {
            $skipped++
            continue
        }

        $processed++
        $readRows += $digest.ReadRowCount
        foreach ($row in $digest.Rows) { [void]$rows.Add($row) }
        & $log.Info -Message "集約: $($source.Name) / 区画=$($digest.PlotCode) / $($digest.EncodingName) / $($digest.DelimiterName) / 行=$($digest.ReadRowCount) / 先月の定植=$(@($digest.Rows).Count)"
    }

    $outputPath = Join-Path $Settings.TargetDirectory $Settings.OutputCsvFileName
    $failurePath = Join-Path $Settings.TargetDirectory $Settings.FailureCsvFileName
    [void](& $files.SaveCsv -Path $outputPath -Rows $rows.ToArray() -Columns $script:DigestColumns -Within $Settings.TargetDirectory -WhenEmpty 'HeaderOnly')
    $failureCsv = & $files.SaveCsv -Path $failurePath -Rows $failures.ToArray() -Columns $script:DigestFailureColumns -Within $Settings.TargetDirectory -WhenEmpty 'Remove'

    & $log.Section -Title 'LastMonthPlantingDigest 処理結果'
    & $log.Info -Message "出力 CSV        : $outputPath"
    & $log.Info -Message "実行日          : $($range.Today.ToString('yyyy-MM-dd'))"
    & $log.Info -Message "入力 CSV        : $($sources.Count) 件（集約 $processed 件 / 飛ばした $skipped 件）"
    & $log.Info -Message "読み取った行    : $readRows 行"
    & $log.Info -Message "先月の定植      : $($rows.Count) 件"
    if ($failureCsv.Written) {
        & $log.Warn -Message "失敗・飛ばした内容の一覧を出力しました（$($failures.Count) 件）: $failurePath"
    }
    else {
        & $log.Info -Message "失敗・飛ばした内容はありません（前回の一覧があれば削除しました）: $failurePath"
    }

    return [pscustomobject]@{
        Range = $range
        OutputPath = $outputPath
        FailurePath = $failurePath
        InputFileCount = $sources.Count
        ProcessedFileCount = $processed
        SkippedFileCount = $skipped
        ReadRowCount = $readRows
        Rows = $rows.ToArray()
        Failures = $failures.ToArray()
    }
}
