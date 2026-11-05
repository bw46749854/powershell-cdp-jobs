# 処理の順序だけを書く。画面の探し方・ファイル操作の具体・時刻の取り方はポートの向こう側にある。

function Invoke-PlotRosterExportFlow {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $log = $Ports.Log
    $page = $Ports.Page
    $files = $Ports.Files

    & $log.Info -Message '実行内容: 温室コンソールの区画一覧を CSV 出力し、保存名を付けて保存します。'
    & $log.Info -Message "一時ダウンロード先: $($Settings.TempDirectory)"
    & $log.Info -Message "保存先            : $($Settings.DownloadDirectory)"

    Invoke-LoggedStep -Log $log -Message '作業ディレクトリを準備します（一時ダウンロード先は空にします）。' -Action {
        [void](& $files.EnsureDirectory -Path $Settings.TempDirectory -Purpose '区画一覧の一時ダウンロード')
        [void](& $files.EnsureDirectory -Path $Settings.DownloadDirectory -Purpose '区画一覧の保存')
        & $files.ClearDirectory -Path $Settings.TempDirectory -Purpose '区画一覧の一時ダウンロード'
    }

    Invoke-LoggedStep -Log $log -Message '区画一覧の画面を開いているタブに接続します。' -Action { [void](& $page.Connect) }
    Invoke-LoggedStep -Log $log -Message 'ブラウザのダウンロード先を一時ディレクトリにします。' -Action { & $page.UseDownloadDirectory -Path $Settings.TempDirectory }
    Invoke-LoggedStep -Log $log -Message 'ページスクリプトを読み込みます。' -Action { [void](& $page.Load) }
    Invoke-LoggedStep -Log $log -Message '画面の初期状態を確認します。' -Action { [void](& $page.AssertInitialScreen) }
    Invoke-LoggedStep -Log $log -Message 'CSV 出力前の画面を確認します。' -Action { [void](& $page.AssertExportScreen) }
    Invoke-LoggedStep -Log $log -Message '「操作」メニューを開きます。' -Action { [void](& $page.OpenTaskMenu) }
    Invoke-LoggedStep -Log $log -Message '「CSV出力」が押せるようになるまで待ちます。' -Action { [void](& $page.WaitExportItemReady -TimeoutSeconds $Settings.MenuTimeoutSeconds) }
    $click = Invoke-LoggedStep -Log $log -Message '「CSV出力」をクリックします。' -Action { & $page.ClickExportItem }
    Invoke-LoggedStep -Log $log -Message 'クリックがこの画面で実行されたことを確認します。' -Action { [void](& $page.AssertExportAccepted) }

    $downloaded = Invoke-LoggedStep -Log $log -Message 'ダウンロードの完了を待ちます。' -Action {
        & $Ports.Downloads.WaitForFile `
            -Directory $Settings.TempDirectory `
            -Filter '*.csv' `
            -NamePattern $Settings.DownloadedFilePattern `
            -TimeoutSeconds $Settings.DownloadTimeoutSeconds `
            -StableSeconds $Settings.DownloadStableSeconds `
            -RejectEmpty $true
    }

    $fileName = Get-RosterExportFileName -Template $Settings.OutputFileNameTemplate -Date (& $Ports.Clock.Now)
    $exportedPath = Invoke-LoggedStep -Log $log -Message "保存名「$fileName」で保存先へ移動します。" -Action {
        & $files.MoveToUnique -Path $downloaded.FullName -DestinationDirectory $Settings.DownloadDirectory -FileName $fileName
    }

    & $log.Section -Title 'PlotRosterExport 処理結果'
    & $log.Info -Message "ダウンロードした CSV: $($downloaded.FullName)"
    & $log.Info -Message "保存した CSV        : $exportedPath"
    & $log.Data -Label 'CSV出力のクリック結果' -Data $click

    return [pscustomobject]@{
        DownloadedCsvPath = $downloaded.FullName
        ExportedCsvPath = $exportedPath
    }
}
