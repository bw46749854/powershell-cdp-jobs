# 1区画分の作付け記録 CSV の取得（業務上ひとまとまりの取引）。
#
#   区画詳細を開く → 開いた区画が対象か確認 → 作付け記録タブ → 表示内容の契約 → 区画コードの再確認
#   → 一時ディレクトリを空にする → CSV 出力 → ダウンロード完了待ち → 区画コード付きの名前で保存
#   → （成功・失敗にかかわらず）区画詳細を閉じる
# 途中で失敗したら、その区画を失敗として呼び出し元へ伝える。区画詳細を閉じる処理は後始末なので、
# 閉じられなくても例外にせず warning を残す（次の区画を開いた時点の契約確認で取り違えを防ぐ）。

function Close-PlantingDetailSafely {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $log = $Ports.Log
    try {
        $closed = & $Ports.Page.CloseDetail
        if ((Get-PropertyValue -InputObject $closed -Name 'ok') -ne $true) {
            & $log.Warn -Message "区画詳細を閉じられませんでした（後始末のため続行します）。詳細=$(ConvertTo-Json -InputObject $closed -Compress -Depth 6)"
            return
        }
        if ((Get-PropertyValue -InputObject $closed -Name 'alreadyClosed') -eq $true) { return }

        try {
            [void](& $Ports.Page.WaitDetailClosed -TimeoutSeconds $Settings.DetailCloseWaitSeconds)
        }
        catch {
            & $log.Warn -Message "区画詳細が $($Settings.DetailCloseWaitSeconds) 秒以内に閉じたことを確認できませんでした。詳細: $($_.Exception.Message)"
        }
    }
    catch {
        & $log.Warn -Message "区画詳細を閉じる処理に失敗しました（後始末のため続行します）。詳細: $($_.Exception.Message)"
    }
}

function Invoke-PlantingRecordTransaction {
    <#
    .SYNOPSIS
    1区画分の CSV を取得して保存し、成功の記録を返す。失敗は例外で伝える。
    #>
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][object]$Row
    )

    $page = $Ports.Page
    $log = $Ports.Log
    $files = $Ports.Files
    $rowId = [string]$Row.rowId
    $plotCode = [string]$Row.plotCode

    try {
        & $log.Info -Message ('-' * 60)
        & $log.Info -Message "処理開始: $plotCode ($rowId)"

        & $log.Data -Label '区画詳細を開く' -Data (& $page.OpenDetail -RowId $rowId -PlotCode $plotCode)
        [void](& $page.WaitDetailFor -RowId $rowId -PlotCode $plotCode)
        & $log.Info -Message "区画詳細が対象の区画を表示していることを確認しました: $plotCode"

        & $log.Data -Label '作付け記録タブ' -Data (& $page.OpenPlantingTab)
        $tab = & $page.AssertPlantingTab
        & $log.Data -Label '作付け記録の表示' -Data (Get-PropertyValue -InputObject $tab -Name 'details')

        $shown = [string](& $page.ReadDetailPlotCode)
        if ($shown -ne $plotCode) {
            throw "区画詳細の区画コードが対象と一致しません。対象=$plotCode 表示=$shown"
        }

        & $files.ClearDirectory -Path $Settings.TempDirectory -Purpose '作付け記録の一時ダウンロード'
        & $log.Data -Label 'CSV出力' -Data (& $page.ClickPlantingCsv)
        $downloaded = & $Ports.Downloads.WaitForFile `
            -Directory $Settings.TempDirectory `
            -Filter "$($Settings.DownloadFilePrefix)*.csv" `
            -NamePattern '' `
            -TimeoutSeconds $Settings.DownloadTimeoutSeconds `
            -StableSeconds $Settings.DownloadStableSeconds `
            -RejectEmpty $false

        $fileName = Get-PlantingRecordFileName -DownloadedName $downloaded.Name -PlotCode $plotCode
        $saved = & $files.MoveToUnique -Path $downloaded.FullName -DestinationDirectory $Settings.DownloadDirectory -FileName $fileName
        & $log.Info -Message "CSV を保存しました: $saved"

        return New-PlantingExportSuccess -RowId $rowId -PlotCode $plotCode -CsvPath $saved
    }
    finally {
        Close-PlantingDetailSafely -Ports $Ports -Settings $Settings
    }
}
