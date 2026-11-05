# PlantingRecordExport — 区画ごとの作付け記録 CSV の保存

作付け台帳の区画一覧を上から順にたどり、区画ごとに区画詳細を開いて「作付け記録」タブの「CSV出力」でダウンロードし、区画コード付きの名前で保存します。月次の連携ジョブ [MonthlyPlantingReport](monthly-planting-report.md) の前段です。

| 項目 | 内容 |
|---|---|
| 対象の画面 | 作付け台帳「区画一覧」と区画詳細（[page-contracts.md](../browser/page-contracts.md#作付け台帳区画一覧と区画詳細)） |
| 入力 | なし |
| 出力 | `DownloadDirectory` に区画ごとの `planting_yyyyMMdd_<区画コード>.csv`、失敗があれば `FailureCsvFileName` |
| 設定 | [Jobs.PlantingRecordExport](../guides/configuration.md#jobsplantingrecordexport) |

## 流れ

1. 一時ダウンロード先・保存先を用意し、一時ダウンロード先を空にする。
2. 画面識別に一致するタブに接続し、ダウンロード先を一時ダウンロード先にして、ページスクリプトを注入する。
3. 画面（`plantingExport.screen`）と一覧の表（`plantingExport.list`）の契約を確かめ、一覧の件数（`data-bind="plotList.total"`）を読む。
4. 開いたままの区画詳細があれば閉じ、一覧の先頭へスクロールする。
5. `Lists.Traverse` で一覧をたどり、まだ処理していない行ごとに「1区画の取引」（次節）を行う。行のキーは「行 ID + 区画コード」。
6. 失敗一覧を出力する（0件なら前回のファイルを削除）。
7. **処理した区画数が一覧の件数に届かない**、または**失敗が1件でもある**ときは異常終了する。

### 1区画の取引（[RecordTransaction.ps1](../../app/modules/PlantingRecordExport/Private/RecordTransaction.ps1)）

| 順 | 処理 | 確かめること |
|---|---|---|
| 1 | 区画コードのリンクをクリックして区画詳細を開く | 対象の行がちょうど1つ |
| 2 | 一覧で選択中の行が対象の区画になり、区画詳細に対象の区画コードが表示されるまで待つ | 待機は `IsDetailReadyFor`（最大 20 秒） |
| 3 | 開いた区画詳細の契約（`plantingExport.openedDetail`） | 選択中の行がちょうど1つでクリックした区画、詳細の区画コードが一致 |
| 4 | 「作付け記録」タブを開き、タブの契約（`plantingExport.plantingTab`）を確かめる | 記録の種類「作付け記録」が選ばれている、見出し `作物名`・`品種`・`定植日` がある、「CSV出力」がちょうど1つ |
| 5 | 区画詳細の区画コードをもう一度読み、対象と一致することを確かめる | 取り違えの防止 |
| 6 | 一時ダウンロード先を空にして「CSV出力」をクリックし、`<DownloadFilePrefix>*.csv` のダウンロード完了を待つ | 候補がちょうど1つ、0 バイトでない |
| 7 | ダウンロードした名前に区画コードを付けて保存先へ移動する | — |
| 8 | **成功・失敗にかかわらず**区画詳細を閉じる（後始末） | 閉じられなくても例外にせず warning を残す |

保存名は、ダウンロードした名前から、ブラウザが付けた ` (1)` などの番号を除き、`_<区画コード>` を付けたものです（例: `planting_20260415 (1).csv` → `planting_20260415_GH2-B01.csv`）。区画コードのうちファイル名に使えない文字と空白は `_` にします。

1区画の失敗は失敗一覧に記録して次の区画へ進みます（読み取りだけの操作なので、他の区画を止める理由にならない）。

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.DownloadDirectory` | 保存先 |
| `Outputs.ExportedCsvPaths` | 保存した CSV のパスの配列 |
| `Outputs.FailurePath` | 失敗一覧のパス（失敗があるときだけ存在する。その場合ジョブは異常終了する） |
| `Summary.Total` / `Processed` / `Succeeded` | 一覧の件数、処理した区画数、成功数 |

失敗一覧の列: `RowId, PlotCode, Reason, Timestamp`

## 操作カタログ（[PageOperations.psd1](../../app/modules/PlantingRecordExport/PageOperations.psd1)）

ヘルパー `plantingRecordExport`（[planting-record-export.js](../../app/browser/features/planting-record-export.js) が、画面の部品 [ledger-plot-list.js](../../app/browser/screens/ledger-plot-list.js)、表の部品 [planting-record-export.grid.js](../../app/browser/features/planting-record-export.grid.js)、詳細の部品 [planting-record-export.detail.js](../../app/browser/features/planting-record-export.detail.js) をまとめて登録する）。

| 操作 | Kind | メソッド | 内容 |
|---|---|---|---|
| `DetectScreen` | Identity | `detectScreen` | 区画一覧画面の識別 |
| `CheckScreen` / `CheckList` | Contract | `checkScreen` / `checkList` | 画面・表の契約 |
| `ReadTotalCount` / `ReadVisibleRows` / `ReadSelectedRow` | Query | 同名 | 件数・表示中の行・選択中の行 |
| `OpenDetail` | Action | `openDetail` | 区画詳細を開く |
| `IsDetailReadyFor` | Probe | `isDetailReadyFor` | 区画詳細に対象の区画が表示されたか |
| `CheckOpenedDetail` | Contract | `checkOpenedDetail` | 開いた区画詳細の契約 |
| `OpenPlantingTab` | Action | `openPlantingTab` | 作付け記録タブを開く |
| `CheckPlantingTab` | Contract | `checkPlantingTab` | 作付け記録タブの契約 |
| `ReadDetailPlotCode` | Query | `readDetailPlotCode` | 区画詳細の区画コード |
| `ClickPlantingCsv` | Action | `clickPlantingCsv` | 「CSV出力」（押す直前にタブの契約をもう一度確かめる） |
| `CloseDetail` | Cleanup | `closeDetail` | 区画詳細を閉じる |
| `IsDetailClosed` | Probe | `isDetailClosed` | 閉じたか |
| `ScrollToTop` / `ScrollDown` | Action | 同名 | 一覧のスクロール |

## ファイル構成

| ファイル | 役割 |
|---|---|
| [PlantingRecordExport.psm1](../../app/modules/PlantingRecordExport/PlantingRecordExport.psm1) | 読み込むファイルの一覧と公開関数 |
| [PageOperations.psd1](../../app/modules/PlantingRecordExport/PageOperations.psd1) | 操作カタログ |
| [Public/Invoke-PlantingRecordExportJob.ps1](../../app/modules/PlantingRecordExport/Public/Invoke-PlantingRecordExportJob.ps1) | ジョブコマンド |
| [Private/Settings.ps1](../../app/modules/PlantingRecordExport/Private/Settings.ps1) | 設定の検証 |
| [Private/Records.ps1](../../app/modules/PlantingRecordExport/Private/Records.ps1) | 行のキー、成功・失敗の記録、保存名の規則（純粋関数） |
| [Private/Page.ps1](../../app/modules/PlantingRecordExport/Private/Page.ps1) | ページポート（区画詳細が対象になるまでの待ち方を含む） |
| [Private/Ports.ps1](../../app/modules/PlantingRecordExport/Private/Ports.ps1) | 合成ルート（Log / Clock / Files / Downloads / Lists / Page） |
| [Private/RecordTransaction.ps1](../../app/modules/PlantingRecordExport/Private/RecordTransaction.ps1) | 1区画の取引と、区画詳細を閉じる後始末 |
| [Private/Flow.ps1](../../app/modules/PlantingRecordExport/Private/Flow.ps1) | 処理の順序と最終確認 |

## テスト

| テスト | 内容 |
|---|---|
| [tests/pester/PlantingRecordExport](../../tests/pester/PlantingRecordExport/PlantingRecordExport.Tests.ps1) | 保存名、Flow（件数不足・失敗での異常終了、後始末が必ず走る）、ページポート |
| [tests/js/planting-record-export.test.js](../../tests/js/planting-record-export.test.js) | 区画コード列が固定列側・通常列側のどちらでも読めること、詳細・タブの契約、閉じる |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 実ブラウザで全区画を保存すること、区画コード列を移しても同じ結果になること |

## この文書を更新するとき

- 処理の順序・取引の手順・保存名の規則・出力・操作カタログ・ファイル構成が変わったとき
