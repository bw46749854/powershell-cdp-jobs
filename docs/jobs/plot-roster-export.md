# PlotRosterExport — 区画一覧の CSV 出力

温室コンソールの「区画」一覧（グループ: 全区画（既定））を、画面の「操作」→「CSV出力」でダウンロードし、日付入りの名前で保存します。週次の連携ジョブ [WeeklySoilAnalysisSync](weekly-soil-analysis-sync.md) の前段です。ブラウザを使うジョブの中で一番短いので、コードを読む入口に向いています。

| 項目 | 内容 |
|---|---|
| 対象の画面 | 温室コンソール「区画」一覧（[page-contracts.md](../browser/page-contracts.md#温室コンソール区画一覧)） |
| 入力 | なし |
| 出力 | `DownloadDirectory` に `plot_roster_MMdd.csv`（同名があれば `plot_roster_MMdd (1).csv`…） |
| 設定 | [Jobs.PlotRosterExport](../guides/configuration.md#jobsplotrosterexport) |

## 流れ

| 順 | 処理 | 止まる条件 |
|---|---|---|
| 1 | 一時ダウンロード先・保存先を用意し、一時ダウンロード先を空にする | 安全でないパス |
| 2 | 画面識別に一致するタブを1つ選んで接続し、ダウンロード先を一時ダウンロード先にする | 一致するタブが0個・2個以上 |
| 3 | ページスクリプトを注入する | カタログのメソッドがヘルパーに無い |
| 4 | 画面の初期状態の契約（`plotRosterExport.initial`）を確かめる | 契約違反 |
| 5 | CSV 出力前の画面の契約（`plotRosterExport.exportScreen`）を確かめる: 件数表示が読める、「操作」ボタンがちょうど1つで押せる | 契約違反 |
| 6 | 「操作」メニューを開く（開いていれば開き直さない） | ボタンが決まらない |
| 7 | 「CSV出力」が押せるようになるまで待つ（`MenuTimeoutSeconds`） | 時間切れ |
| 8 | 「CSV出力」をクリックし、クリックがこのタブで実行されたことを確かめる（`plotRosterExport.postExport`） | 項目が決まらない・契約違反 |
| 9 | ダウンロードの完了を待つ: `*.csv` で `DownloadedFilePattern` に合う候補がちょうど1つ、書き込み途中のファイルが無く、`DownloadStableSeconds` の間サイズが変わらない、0 バイトでない | 時間切れ・候補が複数・0 バイト |
| 10 | `OutputFileNameTemplate` の `{0}` に実行日の `MMdd` を入れた名前で保存先へ移動する | 名前が `.csv` で終わらない・使えない文字 |

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.DownloadedCsvPath` | ブラウザがダウンロードしたファイル（移動前のパス） |
| `Outputs.ExportedCsvPath` | 保存したファイル。連携ジョブが次のジョブへ渡す |

## 操作カタログ（[PageOperations.psd1](../../app/modules/PlotRosterExport/PageOperations.psd1)）

ヘルパー `plotRosterExport`（[plot-roster-export.js](../../app/browser/features/plot-roster-export.js)、画面の部品 [greenhouse-plot-list.js](../../app/browser/screens/greenhouse-plot-list.js)）。

| 操作 | Kind | メソッド | 内容 |
|---|---|---|---|
| `DetectScreen` | Identity | `detectScreen` | 区画一覧画面の識別 |
| `CheckInitialScreen` | Contract | `checkInitialScreen` | 初期状態 |
| `CheckExportScreen` | Contract | `checkExportScreen` | CSV 出力前の画面 |
| `OpenTaskMenu` | Action | `openTaskMenu` | 「操作」メニューを開く |
| `IsExportItemReady` | Probe | `isExportItemReady` | 「CSV出力」が押せるか |
| `ClickExportItem` | Action | `clickExportItem` | 「CSV出力」をクリック |
| `CheckExportAccepted` | Contract | `checkExportAccepted` | クリックがこのタブで実行されたか |

## ファイル構成

| ファイル | 役割 |
|---|---|
| [PlotRosterExport.psm1](../../app/modules/PlotRosterExport/PlotRosterExport.psm1) | 読み込むファイルの一覧と公開関数 |
| [PageOperations.psd1](../../app/modules/PlotRosterExport/PageOperations.psd1) | 操作カタログ |
| [Public/Invoke-PlotRosterExportJob.ps1](../../app/modules/PlotRosterExport/Public/Invoke-PlotRosterExportJob.ps1) | ジョブコマンド |
| [Private/Settings.ps1](../../app/modules/PlotRosterExport/Private/Settings.ps1) | 設定の検証（テンプレートに `{0}` が必要） |
| [Private/Naming.ps1](../../app/modules/PlotRosterExport/Private/Naming.ps1) | 保存名の規則（純粋関数） |
| [Private/Page.ps1](../../app/modules/PlotRosterExport/Private/Page.ps1) | ページポート（操作に業務の名前を付ける） |
| [Private/Ports.ps1](../../app/modules/PlotRosterExport/Private/Ports.ps1) | 合成ルート（Log / Clock / Files / Downloads / Page） |
| [Private/Flow.ps1](../../app/modules/PlotRosterExport/Private/Flow.ps1) | 処理の順序 |

## テスト

| テスト | 内容 |
|---|---|
| [tests/pester/PlotRosterExport](../../tests/pester/PlotRosterExport/PlotRosterExport.Tests.ps1) | 保存名の規則、設定の検証、Flow の呼び出し順と止まり方 |
| [tests/js/plot-roster-export.test.js](../../tests/js/plot-roster-export.test.js) | 画面識別・契約・メニュー操作（構造の違いの吸収と、意味の違いでの停止） |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 週次の連携の一部として実ブラウザで実行。別のグループを選んだ画面では止まること |

## この文書を更新するとき

- 処理の順序・止まる条件・出力・操作カタログ・ファイル構成が変わったとき
