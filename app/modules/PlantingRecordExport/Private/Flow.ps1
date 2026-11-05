# 処理の順序（全体）: 画面の確認 → 一覧を上から1区画ずつ処理 → 失敗一覧の出力 → 件数と失敗の最終確認。
#
# 区画ごとの失敗は記録して次の区画へ進む（読み取りだけの操作なので、他の区画の処理を止める理由にならない）。
# 最後に「一覧の件数ぶん処理したか」「失敗が無いか」を確かめ、どちらかが崩れていれば異常終了する。

function Invoke-PlantingExportFlow {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $log = $Ports.Log
    $page = $Ports.Page
    $files = $Ports.Files

    & $log.Info -Message '実行内容: 作付け台帳の区画を1つずつ開き、作付け記録の CSV を区画コード付きの名前で保存します。'
    & $log.Info -Message "一時ダウンロード先: $($Settings.TempDirectory)"
    & $log.Info -Message "保存先            : $($Settings.DownloadDirectory)"

    [void](& $files.EnsureDirectory -Path $Settings.TempDirectory -Purpose '作付け記録の一時ダウンロード')
    [void](& $files.EnsureDirectory -Path $Settings.DownloadDirectory -Purpose '作付け記録の保存')
    & $files.ClearDirectory -Path $Settings.TempDirectory -Purpose '作付け記録の一時ダウンロード'

    [void](& $page.Connect)
    & $page.UseDownloadDirectory -Path $Settings.TempDirectory
    [void](& $page.Load)
    [void](& $page.AssertScreen)
    [void](& $page.AssertList)

    $total = & $page.ReadTotalCount
    if ($null -eq $total) {
        throw 'ページ契約違反: 区画一覧の件数を読めません。'
    }
    $total = [int]$total

    Close-PlantingDetailSafely -Ports $Ports -Settings $Settings
    [void](& $page.ScrollToTop)
    & $Ports.Clock.Sleep -Milliseconds 500
    & $log.Info -Message "一覧の件数: $total 件"

    $successes = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[object]

    # Lists.Traverse に渡す scriptblock は GetNewClosure しない。
    # このモジュールの非公開関数と、この関数内の変数（$successes など）をそのまま使うため。
    $visit = {
        param($Row)
        try {
            [void]$successes.Add((Invoke-PlantingRecordTransaction -Ports $Ports -Settings $Settings -Row $Row))
        }
        catch {
            $reason = $_.Exception.Message
            & $log.Warn -Message "処理失敗: $($Row.plotCode) ($($Row.rowId)) / $reason"
            $timestamp = ([datetime](& $Ports.Clock.Now)).ToString('yyyy-MM-dd HH:mm:ss')
            [void]$failures.Add((New-PlantingExportFailure -RowId ([string]$Row.rowId) -PlotCode ([string]$Row.plotCode) -Reason $reason -Timestamp $timestamp))
        }
    }

    $traversal = & $Ports.Lists.Traverse `
        -ExpectedCount $total `
        -ReadVisible { & $page.ReadVisibleRows } `
        -KeyOf { param($Row) Get-PlantingRowKey -Row $Row } `
        -Visit $visit `
        -ScrollNext { & $page.ScrollDown } `
        -MaxLoops $Settings.MaxScanLoops `
        -StallLimit $Settings.StallLimit `
        -EmptyMessage '区画の行を取得できませんでした。'

    $failurePath = Join-Path $Settings.DownloadDirectory $Settings.FailureCsvFileName
    $failureCsv = & $files.SaveCsv -Path $failurePath -Rows $failures.ToArray() -Columns $script:PlantingFailureColumns -Within $Settings.DownloadDirectory -WhenEmpty 'Remove'

    & $log.Section -Title 'PlantingRecordExport 処理結果'
    & $log.Info -Message "処理した区画: $($traversal.VisitedCount) / $total 件（終了理由: $($traversal.StopReason)）"
    & $log.Info -Message "成功        : $($successes.Count) 件"
    & $log.Info -Message "失敗        : $($failures.Count) 件"
    if ($failureCsv.Written) {
        & $log.Warn -Message "失敗一覧 CSV を出力しました: $failurePath"
    }
    else {
        & $log.Info -Message "失敗一覧 CSV はありません（前回のファイルがあれば削除しました）: $failurePath"
    }

    if ($traversal.VisitedCount -lt $total) {
        throw "ページ契約違反: 一覧の件数 $total 件に対して、処理できたのは $($traversal.VisitedCount) 件です（終了理由: $($traversal.StopReason)）。"
    }
    if ($failures.Count -gt 0) {
        throw "処理に失敗した区画が $($failures.Count) 件あります。失敗一覧 CSV を確認してください: $failurePath"
    }

    return [pscustomobject]@{
        Total = $total
        Traversal = $traversal
        Successes = $successes.ToArray()
        FailurePath = $failurePath
    }
}
