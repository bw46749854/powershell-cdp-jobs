# 設定

設定ファイルは2つです。役割を分けているので、どちらに書くか迷ったら下の表で判断してください。

| ファイル | 書くこと | 変える人・頻度 |
|---|---|---|
| [app/config/settings.psd1](../../app/config/settings.psd1) | 実行時の値（出力先、ファイル名、タイムアウト、判定のしきい値） | 運用担当。環境や運用ルールが変わったとき |
| [app/config/jobs.psd1](../../app/config/jobs.psd1) | ジョブの実装（どのモジュールのどのコマンドを、どのページスクリプトで動かすか） | 開発者。ジョブを追加・変更したとき |

どちらも PowerShell のデータファイル（`.psd1`）です。UTF-8（BOM 付き）で保存してください（[powershell-compatibility.md](powershell-compatibility.md)）。

## 1. 共通の約束

- **パス**: キー名が `…Path` / `…Directory` の値はパスとして扱います。相対パスはプロジェクトのルート（`app` フォルダーの1つ上）が基準です。`%USERPROFILE%` などの環境変数は展開されます。区切り文字は `\` と `/` のどちらでも構いません。
- **検証**: 各ジョブは開始時に自分の設定をまとめて検証し、欠けている・型が違う値があれば何もせずに止まります（例: `設定 Jobs.PlotRosterExport.MenuTimeoutSeconds は整数で指定してください。`）。
- **安全な出力先**: 出力先のディレクトリには、ドライブのルート・ユーザープロファイルそのもの・ユーザープロファイル直下のフォルダー（`Downloads` など）を指定できません。一時ダウンロード先は中身を消して使うためです。
- **連携ジョブからの上書き**: 連携ジョブは子ジョブの一部の値を、その回だけ上書きします（各表の「上書き」欄）。設定ファイル自体は変わりません。
- 同梱の settings.psd1 が各ジョブの検証を通ること、各ジョブが読まない値が残っていないことは、テスト（[ShippedConfig.Tests.ps1](../../tests/pester/Quality/ShippedConfig.Tests.ps1)）で確かめています。

## 2. Common

### Common.Browser

| キー | 既定値 | 意味 |
|---|---|---|
| `DebuggerUrl` | `http://localhost:9222/json` | リモートデバッグを有効にしたブラウザのタブ一覧の URL。ポートはブラウザの `--remote-debugging-port` と合わせる |
| `ConnectTimeoutSeconds` | `15` | タブ一覧の取得と、タブへの WebSocket 接続の制限時間（秒） |
| `CommandTimeoutSeconds` | `30` | ブラウザへの1回の命令（スクリプトの評価など）の制限時間（秒） |

### Common.Logging

| キー | 既定値 | 意味 |
|---|---|---|
| `Level` | `Info` | 出力する最低のレベル。`Debug` / `Info` / `Warning` / `Error` |
| `Console` | `$true` | コンソールに出すか |
| `File` | `$false` | ファイルにも出すか。`$true` なら `Directory` が必要 |
| `Directory` | `logs` | ログファイルの出力先。ファイル名は `<ジョブ名>_<実行ID>.log` |

## 3. Jobs

### Jobs.PlotRosterExport

| キー | 既定値 | 上書き | 意味 |
|---|---|---|---|
| `TempDirectory` | `work/weekly/tmp/plot_roster_export` | | ブラウザのダウンロード先。**実行のたびに中身を消す**ので専用のフォルダーにする |
| `DownloadDirectory` | `work/weekly/downloads` | | 保存先 |
| `DownloadedFilePattern` | `^.+\.csv$` | | ダウンロードされたファイルとみなす名前の正規表現 |
| `OutputFileNameTemplate` | `plot_roster_{0}.csv` | | 保存名。`{0}` に実行日の月日（`MMdd`）が入る。`.csv` で終わること |
| `DownloadTimeoutSeconds` | `120` | | ダウンロードの完了を待つ上限（秒） |
| `DownloadStableSeconds` | `2` | | サイズが変わらなくなってから完了とみなすまでの秒数（0 以上） |
| `MenuTimeoutSeconds` | `10` | | 「操作」メニューの「CSV出力」が押せるようになるまで待つ上限（秒） |

### Jobs.SoilAnalysisTargetSync

| キー | 既定値 | 上書き | 意味 |
|---|---|---|---|
| `InputCsvPath` | `%USERPROFILE%\Downloads\plot_roster.csv` | 週次: `PlotRosterExport` が保存した CSV | 判定に使う区画一覧 CSV。単独で実行するときだけこの値を使う |
| `OutputDirectory` | `work/weekly/downloads` | | CSV データエラー一覧・チェック整合失敗一覧の出力先 |
| `CsvErrorFileName` | `soil_analysis_csv_errors.csv` | | CSV データエラー一覧のファイル名（0件なら作らない） |
| `FailureCsvFileName` | `soil_analysis_sync_failures.csv` | | チェック整合失敗一覧のファイル名（0件なら作らない） |
| `DaysThreshold` | `7` | | 「最終計測日時 − 土壌分析の完了」がこの日数以上なら ON（[判定ルール](../jobs/soil-analysis-target-sync.md#判定ルール)） |
| `MaxScanLoops` | `500` | | 一覧の走査（読む → 揃える → スクロール）の最大回数 |
| `StallLimit` | `5` | | スクロールしても位置が変わらない回数がこれに達したら、一覧の終端とみなす |

### Jobs.PlantingRecordExport

| キー | 既定値 | 上書き | 意味 |
|---|---|---|---|
| `TempDirectory` | `work/monthly/tmp` | 月次: 実行フォルダーの `planting_export_tmp` | ブラウザのダウンロード先。**区画ごとに中身を消す** |
| `DownloadDirectory` | `work/monthly/downloads` | 月次: 実行フォルダーの `planting_export_downloads` | 区画ごとの CSV の保存先 |
| `DownloadFilePrefix` | `planting_` | | 作付け台帳がダウンロードさせる CSV の名前の先頭。ダウンロードの検出と、月次の成果物の確認に使う。ワイルドカード文字（`* ? [ ]`）は使えない |
| `FailureCsvFileName` | `failed_planting_exports.csv` | | 保存できなかった区画の一覧（0件なら作らない）。`DownloadFilePrefix` で始まらない名前にする（成果物と取り違えないため） |
| `DownloadTimeoutSeconds` | `120` | | 1区画のダウンロードの完了を待つ上限（秒） |
| `DownloadStableSeconds` | `2` | | サイズが変わらなくなってから完了とみなすまでの秒数（0 以上） |
| `DetailCloseWaitSeconds` | `3` | | 区画詳細を閉じたあと、閉じたことを確かめるまで待つ上限（秒） |
| `MaxScanLoops` | `500` | | 一覧の走査の最大回数 |
| `StallLimit` | `2` | | スクロールしても位置が変わらない回数がこれに達したら、一覧の終端とみなす |

### Jobs.LastMonthPlantingDigest

| キー | 既定値 | 上書き | 意味 |
|---|---|---|---|
| `TargetDirectory` | `work/monthly/downloads` | 月次: 実行フォルダーの `planting_export_downloads` | 読み取る CSV のフォルダー。結果もここに出す |
| `OutputCsvFileName` | `last_month_plantings.csv` | | 先月の定植をまとめた CSV（0件でも見出し行だけで作る） |
| `FailureCsvFileName` | `last_month_plantings_failures.csv` | | 読めなかったファイル・行の一覧（0件なら作らない） |
| `FileNamePattern` | `^.+_(GH\d-[A-Z]\d{2})\.csv$` | | 読み取る CSV の名前の正規表現。**グループ1が区画コード**になる。大文字・小文字を区別する |
| `RequiredHeaders` | `作物名`, `品種`, `定植日` | | CSV の見出し行。**順序も含めて完全に一致**する必要がある。この3つは出力の列の元になるため必ず含める |

### Jobs.WeeklySoilAnalysisSync

設定項目はありません（空の `@{}`）。子ジョブの設定を使います。

### Jobs.MonthlyPlantingReport

| キー | 既定値 | 意味 |
|---|---|---|
| `RunRootDirectory` | `work/monthly/runs` | 実行ごとのフォルダー（`yyyyMMdd_HHmmss`）を作る場所 |

## 4. jobs.psd1 の書式

```powershell
@{
    Jobs = @{
        PlotRosterExport = @{
            Module = 'modules/PlotRosterExport/PlotRosterExport.psm1'   # app からの相対パス
            Command = 'Invoke-PlotRosterExportJob'                        # Invoke-<ジョブ名>Job
            UsesBrowser = $true                                           # 必ず明示する
            Browser = @{                                                  # UsesBrowser = $true のときだけ
                Operations = 'modules/PlotRosterExport/PageOperations.psd1'
                Scripts = @(                                              # この順で連結して注入する
                    'browser/kernel/pagekit.js'
                    'browser/screens/greenhouse-plot-list.js'
                    'browser/features/plot-roster-export.js'
                )
            }
        }
    }
}
```

| キー | 必須 | 検証 |
|---|---|---|
| `Module` | ○ | ファイルが存在すること |
| `Command` | ○ | 「動詞-名詞」の形。モジュールが公開していること |
| `UsesBrowser` | ○ | `$true` / `$false`。`$false` なら `Browser` を書かない |
| `Browser.Operations` | ブラウザを使うとき | 操作カタログ（[PageBridge.md](../modules/PageBridge.md#操作カタログ)）が存在すること |
| `Browser.Scripts` | ブラウザを使うとき | 1件以上の配列（先頭は `browser/kernel/pagekit.js` にする） |

ジョブ名は英数字だけです。未知のキーは誤記とみなして止まります。`Browser.Scripts` の並びは、ブラウザスクリプトのテスト（[tests/js/support/page.js](../../tests/js/support/page.js) の `SCRIPTS`）と一致している必要があります（テストで確認）。

## この文書を更新するとき

- settings.psd1 の項目を追加・削除・改名したとき、既定値や意味を変えたとき（項目の掲載漏れはテストで検出される）
- jobs.psd1 の書式や検証を変えたとき
