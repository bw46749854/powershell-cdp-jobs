# SoilAnalysisTargetSync — 土壌分析の対象チェックの整合

区画一覧 CSV（[PlotRosterExport](plot-roster-export.md) の出力）を読み、区画ごとに土壌分析の対象（ON）か対象外（OFF）かを判定して、温室コンソールの区画一覧のチェック（選択）をその判定どおりに揃えます。

**「土壌分析を依頼」は決してクリックしません。** 区画を選んだことで依頼の項目が有効になったことを確かめるだけです。依頼は、結果を確認した担当者が画面で行います。クリックする操作は、操作カタログにもページポートにもページスクリプトにも存在しません。

| 項目 | 内容 |
|---|---|
| 対象の画面 | 温室コンソール「区画」一覧（[page-contracts.md](../browser/page-contracts.md#温室コンソール区画一覧)） |
| 入力 | `InputCsvPath` の区画一覧 CSV（UTF-8、BOM の有無は問わない。1行目にタブがあればタブ区切り、無ければカンマ区切り） |
| 出力 | `OutputDirectory` に CSV データエラー一覧・チェック整合失敗一覧（どちらも1件以上あるときだけ） |
| 設定 | [Jobs.SoilAnalysisTargetSync](../guides/configuration.md#jobssoilanalysistargetsync) |

## 判定ルール

[Policy.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Policy.ps1) が区画ごとに判定します。日数は暦日どうしの差です（時刻は見ません）。

| 順 | 条件 | 判定 |
|---|---|---|
| 1 | 土壌分析の完了が空欄または `-` | **ON** |
| 2 | 土壌分析の完了を日付として読めない | CSV データエラー（`ANALYSIS_DATE_INVALID`） |
| 3 | 最終計測日時を日付として読めない | CSV データエラー（`MEASURED_DATE_INVALID`） |
| 4 | 最終計測日時が土壌分析の完了より前 | CSV データエラー（`DATE_ORDER_INCONSISTENT`） |
| 5 | 最終計測日時 − 土壌分析の完了 が `DaysThreshold` 日以上 | **ON** |
| 6 | それ以外 | **OFF** |

日付として読める形式は [CalendarDate.ps1](../../app/modules/SoilAnalysisTargetSync/Private/CalendarDate.ps1) にあります（`2026-04-10`、`2026/4/10 8:00:00`、`2026年4月10日`、時差付きの ISO 8601 など）。時差付きの値は換算せず、表示どおりの日付として扱います。

CSV の列は見出しの名前で読みます（[RosterCsv.ps1](../../app/modules/SoilAnalysisTargetSync/Private/RosterCsv.ps1)）。必須は `区画コード`・`担当者`・`稼働状態`・`最終計測日時`・`土壌分析の依頼`・`土壌分析の完了` で、他の列は読み捨てます。

## 流れ

| 段階 | 処理 | 止まる条件 | 画面への影響 |
|---|---|---|---|
| 1. 計画 | CSV を読み、全行を判定する。区画コードの空欄・重複も調べる | CSV データエラーが1件でもある / 判定の件数が CSV と合わない | なし |
| 2. 画面の確認 | 接続・注入し、画面（`soilAnalysisSync.screen`）と一覧の表（`soilAnalysisSync.list`）の契約を確かめ、操作に使うペインを決める | 契約違反 / 件数表示が CSV の行数・対象件数と合わない | なし |
| 3. 走査と整合 | 一覧の先頭から、表示中の行を読み、まだ処理していない区画のチェックを目的の状態に揃え、下へスクロールする | 通信を続けられない失敗（区画ごとの失敗は記録して続ける） | チェックが変わる |
| 4. 突き合わせ | 画面で見た区画・処理した区画・成功の内訳を CSV と突き合わせる | — （食い違いは失敗として記録） | なし |
| 5. 依頼の項目 | ON の区画があれば、「選択区画」の「土壌分析を依頼」が有効か確かめる（`soilAnalysisSync.postSelection`） | — （有効でなければ失敗として記録） | なし |
| 6. 出力 | 2つの一覧 CSV を出力する（0件なら前回のファイルを削除） | 失敗が1件でもあれば異常終了 | なし |

途中で例外になったときも、まだ出力していなければ `FATAL_ERROR` の記録を加えて一覧を出力してから止まります。

### 走査の終わり方

- 一覧の件数表示ぶんの区画を見て、対象をすべて処理したら終わる（`complete`）。
- スクロールしても位置が変わらないことが `StallLimit` 回続いたら終わる（`end-of-list`）。
- `MaxScanLoops` 回に達したら終わる（`loop-limit`、`SCAN_LOOP_LIMIT` を記録）。

### 1区画の整合（ページヘルパー `syncSelection`）

1. 保持している操作スコープ（ペイン）の中で、区画コードが一致する行がちょうど1つか確かめる。
2. その行の選択列のチェックボックスがちょうど1つで、操作できるか確かめる。
3. 目的の状態と違えば、チェックボックス（を包む label）をクリックして 300 ミリ秒待つ。
4. もう一度その区画の行を探し、ちょうど1つで、目的の状態になっていることを確かめる。

失敗の理由（`reason`）: `scope_not_prepared` / `plot_not_visible` / `plot_duplicated_in_view` / `checkbox_not_unique` / `checkbox_disabled` / `plot_not_unique_after_click` / `checkbox_not_unique_after_click` / `state_not_aligned_after_click`。

## 失敗の記録

### CSV データエラー一覧（`CsvErrorFileName`）

列: `PlotCode, Owner, Status, LastMeasured, AnalysisRequested, AnalysisCompleted, ElapsedDays, Code, Reason, Timestamp`

| Code | 記録する箇所 | 意味 |
|---|---|---|
| `ANALYSIS_DATE_INVALID` | Policy | 土壌分析の完了を日付として読めない |
| `MEASURED_DATE_INVALID` | Policy | 最終計測日時を日付として読めない |
| `DATE_ORDER_INCONSISTENT` | Policy | 最終計測日時が土壌分析の完了より前 |
| `PLOT_CODE_BLANK` | Plan | 区画コードが空欄 |
| `PLOT_CODE_DUPLICATED` | Plan | 区画コードが CSV 内で重複 |

### チェック整合失敗一覧（`FailureCsvFileName`）

列: `PlotCode, RowId, Owner, Status, LastMeasured, AnalysisRequested, AnalysisCompleted, Code, Reason, Timestamp`（一覧全体に関わる失敗は `PlotCode` が空）

| Code | 記録する箇所 | 意味 |
|---|---|---|
| `CSV_CLASSIFICATION_COUNT_MISMATCH` / `TARGET_COUNT_MISMATCH` / `TARGET_DUPLICATED` | Plan | 判定・対象の件数が CSV と合わない、対象に重複（操作前に停止） |
| `UI_TOTAL_COUNT_INVALID` / `CSV_UI_COUNT_MISMATCH` / `TARGET_UI_COUNT_MISMATCH` | Flow（画面の確認） | 画面の件数が読めない・CSV や対象件数と合わない（操作前に停止） |
| `SYNC_FAILED` | Flow.Scan | ページヘルパーが目的の状態にできなかった（`Reason` にヘルパーの理由） |
| `SYNC_EXCEPTION` | Flow.Scan | 整合中に例外 |
| `SCAN_LOOP_LIMIT` | Reconciliation | 走査の最大回数に達した |
| `UI_ROW_WITHOUT_KEY` | Reconciliation | 区画コードか行 ID が空の行があった |
| `UI_PLOT_CODE_CONFLICT` | Reconciliation | 同じ区画コードが別の行 ID で現れた |
| `UI_SEEN_COUNT_MISMATCH` | Reconciliation | 画面で見た区画数が件数表示と合わない |
| `PLOT_NOT_FOUND_IN_UI` | Reconciliation | CSV の区画が一覧に無い |
| `PLOT_NOT_IN_CSV` | Reconciliation | 一覧の区画が CSV に無い |
| `SYNC_NOT_ATTEMPTED` | Reconciliation | 一覧で見つけたが整合を実行できなかった |
| `PROCESSED_COUNT_MISMATCH` | Reconciliation | 整合を試みた数が対象件数と合わない |
| `ON_SUCCESS_COUNT_MISMATCH` / `OFF_SUCCESS_COUNT_MISMATCH` / `SUCCESS_NOT_ALIGNED` | Reconciliation | 成功の内訳が対象と合わない |
| `REQUEST_MENU_NOT_ENABLED` | Flow | 「土壌分析を依頼」が有効にならない |
| `FATAL_ERROR` | Flow | 上記以外の理由で途中停止 |

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.CsvErrorPath` / `Outputs.FailurePath` | 2つの一覧のパス（ファイルは1件以上あるときだけ存在する） |
| `Summary.CsvRows` / `OnTargets` / `OffTargets` / `Succeeded` | CSV の行数、ON・OFF の対象数、整合に成功した区画数 |

## 操作カタログ（[PageOperations.psd1](../../app/modules/SoilAnalysisTargetSync/PageOperations.psd1)）

ヘルパー `soilAnalysisSync`（[soil-analysis-sync.js](../../app/browser/features/soil-analysis-sync.js)、[soil-analysis-sync.table.js](../../app/browser/features/soil-analysis-sync.table.js)、画面の部品 [greenhouse-plot-list.js](../../app/browser/screens/greenhouse-plot-list.js)）。

| 操作 | Kind | メソッド | 内容 |
|---|---|---|---|
| `DetectScreen` | Identity | `detectScreen` | 区画一覧画面の識別（PlotRosterExport と同じ部品） |
| `CheckScreen` | Contract | `checkScreen` | 画面の契約（絞り込み欄・件数表示・行がある） |
| `CheckList` | Contract | `checkList` | 表の契約（必須の列見出し・操作スコープ・行 ID・区画コード・チェックボックス・スクロール領域） |
| `PrepareScope` | Action | `prepareScope` | 操作に使うペインを決めて保持する |
| `ReadVisibleRows` | Query | `readVisibleRows` | 保持したペインの表示中の行 |
| `SyncSelection` | Action | `syncSelection` | 1区画のチェックを目的の状態にする |
| `CheckAnalysisMenu` | Contract | `checkAnalysisMenu` | 「土壌分析を依頼」が有効か |
| `ScrollToTop` / `ScrollDown` | Action | `scrollToTop` / `scrollDown` | 一覧のスクロール |

## 設計の理由と注意点

**なぜこうしているか**

- **判定できない行が1件でもあれば、画面に触れない。** 一部の区画だけを揃えた中途半端な状態を作らないためです。CSV を直して最初からやり直せば、同じ結果になります。
- **CSV の行数・対象件数と、画面の件数が一致しなければ、チェックを触らない。** CSV が古い・絞り込みが残っているなど、前提が崩れたまま操作しないためです。
- **絞り込み欄を使わず、一覧を上から全件たどる。** 画面で見た区画の全体を CSV と突き合わせ、「CSV にあって画面に無い」「画面にあって CSV に無い」を両方検出するためです（絞り込みで1件ずつ探すと、前者しか分かりません）。
- **操作スコープ（ペイン）を最初に1つ決めて保持する。** 同じ区画の行が左固定ペインと通常ペインの両方に描画される画面で、走査の途中で操作するペインが入れ替わらないようにします（決め方は [page-contracts.md](../browser/page-contracts.md#操作スコープどのペインの行を操作するか)）。
- **「土壌分析を依頼」は押さない。** 依頼は結果を確認した担当者が行います。押す操作はコードのどこにもありません（[maintenance-rules.md](../guides/maintenance-rules.md) の不変条件 I-1）。

**誤解しやすい点**

- 「対象」は ON にする区画だけではありません。**OFF にする区画も対象**で、すべての区画を判定どおりに揃えます。既に揃っている区画は押さずに「変更不要」として数えます。
- 何度実行しても同じ結果になります（2回目は何も変わらない）。途中で止まったときは、原因を直して最初から実行し直せば揃います。
- `InputCsvPath` の設定は単独実行のときだけ使います。週次の連携では、前段が出力した CSV のパスで上書きされます。

**変更するときに危険な箇所**

- 判定ルール（[Policy.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Policy.ps1)）を変えるときは、E2E の期待値の計算（テスト側で独立に書いている）も同じように直します（[making-changes.md](../guides/making-changes.md#51-判定ルールを足す--稼働状態が休止中の区画は-off-にする)）。
- 区画ごとの例外で「通信を続けられないか」を判定する箇所（[Flow.Scan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.Scan.ps1) の `Fatal`）を外すと、ブラウザが閉じた後も全区画に失敗を記録し続け、原因が埋もれます。
- 件数の照合を緩めると、別のグループや古い CSV のまま操作する事故につながります。

## ファイル構成

| ファイル | 役割 |
|---|---|
| [SoilAnalysisTargetSync.psm1](../../app/modules/SoilAnalysisTargetSync/SoilAnalysisTargetSync.psm1) | 読み込むファイルの一覧と公開関数 |
| [PageOperations.psd1](../../app/modules/SoilAnalysisTargetSync/PageOperations.psd1) | 操作カタログ |
| [Public/Invoke-SoilAnalysisTargetSyncJob.ps1](../../app/modules/SoilAnalysisTargetSync/Public/Invoke-SoilAnalysisTargetSyncJob.ps1) | ジョブコマンド |
| [Private/Settings.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Settings.ps1) | 設定の検証 |
| [Private/RosterCsv.ps1](../../app/modules/SoilAnalysisTargetSync/Private/RosterCsv.ps1) | CSV の見出し → 内部の項目名（見出しの変更はここで止める） |
| [Private/CalendarDate.ps1](../../app/modules/SoilAnalysisTargetSync/Private/CalendarDate.ps1) | 日付として読む規則 |
| [Private/Policy.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Policy.ps1) | ON / OFF の判定ルール（純粋関数） |
| [Private/Records.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Records.ps1) | 出力する記録の形と列順、表示用の文言 |
| [Private/Plan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Plan.ps1) | 計画（判定・区画コードの検査・対象の並び） |
| [Private/ScanState.ps1](../../app/modules/SoilAnalysisTargetSync/Private/ScanState.ps1) | 走査の状態（見た区画・処理した区画・矛盾） |
| [Private/Reconciliation.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Reconciliation.ps1) | 走査結果と CSV の突き合わせ |
| [Private/Ledger.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Ledger.ps1) | 失敗の記録帳（記録時刻は Clock から） |
| [Private/Report.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Report.ps1) | 2つの一覧 CSV の出力 |
| [Private/Page.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Page.ps1) | ページポート（依頼をクリックする操作は持たない） |
| [Private/Ports.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Ports.ps1) | 合成ルート（Log / Clock / Files / Page） |
| [Private/Flow.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.ps1) | 処理の順序（計画 → 画面の確認 → 走査 → 突き合わせ → 出力） |
| [Private/Flow.Scan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.Scan.ps1) | 走査と1区画の整合 |

## テスト

| テスト | 内容 |
|---|---|
| [tests/pester/SoilAnalysisTargetSync/Policy.Tests.ps1](../../tests/pester/SoilAnalysisTargetSync/Policy.Tests.ps1) | 判定ルールの境界、日付の形式、CSV の読み方、計画と突き合わせ |
| [tests/pester/SoilAnalysisTargetSync/Flow.Tests.ps1](../../tests/pester/SoilAnalysisTargetSync/Flow.Tests.ps1) | 操作前に止まる条件、走査、失敗の記録、通信の失敗での即停止 |
| [tests/js/soil-analysis-sync.test.js](../../tests/js/soil-analysis-sync.test.js) | 操作スコープの決め方、チェックの整合、依頼の項目の確認 |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 実ブラウザで、選択された区画がテスト側で独立に計算した期待と一致すること、依頼が押されないこと、再実行で何も変わらないこと |

## この文書を更新するとき

- 判定ルール・止まる条件・失敗の Code・出力の列・操作カタログ・ファイル構成が変わったとき
- 設計の理由・注意点が変わったとき
