# 実行台帳を2つの CSV に書き出す。
#   CSV データエラー一覧  : 入力 CSV の行ごとの判定不能・空欄・重複
#   チェック整合失敗一覧  : ブラウザ操作中・走査後に見つかった失敗
# 0件のときは前回の同名ファイルを削除する（古い失敗一覧を今回の結果と誤読させない）。

function Export-SoilAnalysisReports {
    param(
        [Parameter(Mandatory)][object]$Ledger,
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings
    )

    $files = $Ports.Files
    $log = $Ports.Log
    $directory = $Settings.OutputDirectory

    $outputs = @(
        @{ Label = 'CSV データエラー一覧'; FileName = $Settings.CsvErrorFileName; Rows = $Ledger.CsvErrors.ToArray(); Columns = $script:CsvErrorColumns },
        @{ Label = 'チェック整合失敗一覧'; FileName = $Settings.FailureCsvFileName; Rows = $Ledger.Failures.ToArray(); Columns = $script:SyncFailureColumns }
    )

    $paths = @{}
    foreach ($output in $outputs) {
        $path = Join-Path $directory $output.FileName
        $saved = & $files.SaveCsv -Path $path -Rows $output.Rows -Columns $output.Columns -Within $directory -WhenEmpty 'Remove'
        $paths[$output.Label] = $path

        if ($saved.Written) {
            & $log.Warn -Message "$($output.Label): $($saved.Count) 件を出力しました: $path"
        }
        elseif ($saved.Removed) {
            & $log.Info -Message "$($output.Label): 0 件のため、前回のファイルを削除しました: $path"
        }
        else {
            & $log.Info -Message "$($output.Label): 0 件です: $path"
        }
    }

    $Ledger.Exported = $true
    return [pscustomobject]@{
        CsvErrorPath = $paths['CSV データエラー一覧']
        FailurePath = $paths['チェック整合失敗一覧']
    }
}
