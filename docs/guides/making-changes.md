# 変更ガイド

「これを変えたい」「こういうことが起きた」から、**どこを直し、何を一緒に直すか**を引くための文書です。画面が変わって止まったときは [changing-page-contracts.md](changing-page-contracts.md)、ジョブを新しく作るときは [adding-a-job.md](adding-a-job.md) を参照してください。守るべき規約は [maintenance-rules.md](maintenance-rules.md) にあります。

## 1. 変更内容から直す場所を引く

| 変えたいこと | 直す場所 | 一緒に直すもの |
|---|---|---|
| 土壌分析の ON / OFF の条件 | [SoilAnalysisTargetSync/Private/Policy.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Policy.ps1) の `Get-AnalysisDecision` | 同じファイルの `Get-AnalysisRuleDescription`（ログに出る説明）、Policy.Tests の TestCases、E2E の期待値の計算（`Get-ExpectedAnalysisTargets`）、[soil-analysis-target-sync.md](../jobs/soil-analysis-target-sync.md#判定ルール) |
| 土壌分析のしきい値（日数） | `settings.psd1` の `Jobs.SoilAnalysisTargetSync.DaysThreshold` | なし（コードは直さない） |
| 日付として読める形式 | 週次: [CalendarDate.ps1](../../app/modules/SoilAnalysisTargetSync/Private/CalendarDate.ps1)、月次: [LastMonthPlantingDigest/Private/Policy.ps1](../../app/modules/LastMonthPlantingDigest/Private/Policy.ps1) の `$script:PlantingDateFormats` | 各ジョブの Policy / Parsing のテスト、ジョブの文書 |
| 入力 CSV の列の名前 | 週次: [RosterCsv.ps1](../../app/modules/SoilAnalysisTargetSync/Private/RosterCsv.ps1) の `$script:RosterCsvColumns`、月次: 設定の `RequiredHeaders` と [Records.ps1](../../app/modules/LastMonthPlantingDigest/Private/Records.ps1) の見出しの定数 | テスト、ジョブの文書。月次は見出しが**順序まで完全一致**であることに注意（6章） |
| 出力 CSV の列 | 各ジョブの `Records.ps1` の `$script:…Columns` と、記録を作る関数 | 列を確かめるテスト、ジョブの文書の「出力」「失敗の記録」 |
| 保存するファイルの名前 | 週次の区画一覧: [Naming.ps1](../../app/modules/PlotRosterExport/Private/Naming.ps1) と設定の `OutputFileNameTemplate`、作付け記録: [PlantingRecordExport/Private/Records.ps1](../../app/modules/PlantingRecordExport/Private/Records.ps1) の `Get-PlantingRecordFileName`、月次の実行フォルダー: [Monthly.ps1](../../app/modules/JobChains/Private/Monthly.ps1) の先頭の定数 | 月次の集計がファイル名から区画コードを取り出す `FileNamePattern` と矛盾しないか |
| 処理の順序・止まる条件 | 各ジョブの `Flow*.ps1` | Flow のテスト（`Get-PortCalls` で呼び出し順を確かめる）、ジョブの文書の「流れ」 |
| タイムアウト・待機時間 | まず `settings.psd1`。画面操作ごとの上限は各ジョブの `PageOperations.psd1` の `TimeoutSeconds`、既定値は PageBridge の `PageGateway.ps1` の `$script:PageWaitDefaults` | [configuration.md](configuration.md) |
| 画面の文言・目印 | ページスクリプトの先頭の定数（例: `const CSV_BUTTON_NAME = 'CSV出力'`） | [changing-page-contracts.md](changing-page-contracts.md) の手順どおり |
| 新しい画面操作 | ページスクリプトのメソッド → `PageOperations.psd1` → `Page.ps1` | tests/js、[page-contracts.md](../browser/page-contracts.md)、ジョブの文書の操作カタログ |
| 失敗の Code を増やす | 記録を作る場所（週次なら `Records.ps1` の `New-SyncFailureRecord` を呼ぶ箇所） | テスト、ジョブの文書の Code の表、[troubleshooting.md](troubleshooting.md) |
| 設定項目を増やす | `settings.psd1` と、そのジョブの `Settings.ps1` | [configuration.md](configuration.md)（テストで検査）。読まれない設定項目があると ShippedConfig のテストが失敗する |
| 作業ディレクトリの安全の規則 | JobHost の [SafePaths.ps1](../../app/modules/JobHost/Private/SafePaths.ps1) | すべてのジョブに効く。FilesAndSafety のテスト |
| 連携ジョブの受け渡し | JobChains の [Weekly.ps1](../../app/modules/JobChains/Private/Weekly.ps1) / [Monthly.ps1](../../app/modules/JobChains/Private/Monthly.ps1) | JobChains のテスト、連携ジョブの文書 |

## 2. 起きたことから探す

| 起きたこと | 最初に見る場所 |
|---|---|
| 運用中にジョブが止まった | [troubleshooting.md](troubleshooting.md)（メッセージから原因を引く） |
| 画面の変更で止まった | [changing-page-contracts.md](changing-page-contracts.md) |
| 結果の件数・判定が期待と違う | 該当ジョブの純粋関数のテスト。期待する入力と出力を TestCases に足して、どの規則で食い違うかを再現する |
| Windows PowerShell 5.1 でだけ失敗する | [powershell-compatibility.md](powershell-compatibility.md) |
| テストだけが失敗する | [testing.md](testing.md#7-テストが落ちたとき) |
| 「結果オブジェクトを1つだけ返す必要があります（実際: 2 個）」 | 戻り値を使わない呼び出しの `[void]` の付け忘れ（[powershell-primer.md](powershell-primer.md#5-戻り値とパイプライン)） |

## 3. 安全な変更の手順

1. 変えたいことを1章で引き、直す場所と、一緒に直すものを確かめる。
2. 変えたい振る舞いを、まずテストに書く。今の実装でそのテストが失敗することを確かめる。
3. 直す場所を1か所だけ直す。
4. そのジョブ・モジュールのテストを実行する（`-Path tests/pester/<モジュール>`）。
5. テスト一式を Windows PowerShell 5.1 で実行する（[testing.md](testing.md#1-実行する)）。画面に関わる変更は、ブラウザスクリプトのテストと E2E も実行する。
6. 1章の「一緒に直すもの」と、各文書の「この文書を更新するとき」に従って文書を直す。
7. 本番の画面で動かす前に、モック画面で通しの動きを確かめる。週次は何度実行しても同じ結果になるので、モックで2回続けて実行し、2回目に何も変わらないことも確かめる。

## 4. やってはいけない直し方

| してはいけないこと | なぜ | 代わりに |
|---|---|---|
| 見出しやボタンが見つからないとき「左から2番目」「最初の要素」で代用する | 列やボタンが増えたときに別のものを操作する | 名前が本当に変わったと確認し、契約の名前を更新する |
| Flow に `if` の判定ルールを書き足す | 判定を表でテストできなくなる | 純粋関数（Policy など）に書き、Flow はその結果で分岐する |
| Flow で `Get-Date` / `Start-Sleep` / `Get-ChildItem` を使う | 実時間・実ファイルなしでテストできなくなる（テストで検出） | `$Ports.Clock` / `$Ports.Files` を使う |
| ジョブのモジュールで `Context` を `Ports.ps1` 以外に渡す | ジョブが何に依存しているか分からなくなる（テストで検出） | 必要なサービスを `Ports.ps1` の形の宣言に足す |
| PowerShell 側に CSS セレクターを書く / ページスクリプトで CSV を作る | 境界が崩れ、画面の変更とファイル形式の変更が混ざる | 画面の探し方はページスクリプト、ファイルは PowerShell |
| 失敗を握りつぶして続ける（`catch { }` で何もしない） | 失敗が記録されず、成功に見える | 失敗として記録する。後始末だけは warning で続けてよい |
| ブラウザとの通信が切れた後も区画の処理を続ける | 全件が失敗するだけで、原因が埋もれる | `IsFatal` で判定して止める |
| テストの期待値を、実装の出力に合わせて書き換える | テストが仕様でなくなる | 仕様が変わったと確認できたときだけ、理由を添えて直す |
| 設定の値をテストを通すために変える | 本番の動きが変わる | テスト用の設定はテストの中で作る |
| 文書を後回しにする | 文書と実装がずれる（文書のテストでも一部を検出） | 同じ変更で直す |

## 5. 具体例

### 5.1 判定ルールを足す — 「稼働状態が『休止中』の区画は OFF にする」

1. **業務の確認**: 新しい規則を、今の6つの規則のどこに入れるかを決める。ここでは「日付を読めない・前後が矛盾する行は、これまでどおり CSV データエラー（規則2〜4）。そのあと、しきい値の判定（規則5）より前に『休止中なら OFF』を入れる」と決めたとする。
2. **テスト**: [Policy.Tests.ps1](../../tests/pester/SoilAnalysisTargetSync/Policy.Tests.ps1) の判定の TestCases に、「休止中・完了が空欄」「休止中・しきい値以上」「休止中・日付が読めない」の行を足す。期待はそれぞれ ON（規則1が先）、OFF、CSV データエラー。
3. **直す**: [Policy.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Policy.ps1) の `Get-AnalysisDecision` に `-Status` を足して規則を加え、`Get-AnalysisRuleDescription` に説明の行を足す。呼び出し側の [Plan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Plan.ps1) で `$record.Status` を渡す。冒頭コメントの規則の一覧も直す。
4. **E2E**: [Chains.E2E.Tests.ps1](../../tests/e2e/Chains.E2E.Tests.ps1) の `Get-ExpectedAnalysisTargets` は、ジョブの関数を使わずに期待値を計算しています。同じ規則をここにも書く（ジョブと同じ誤りを見逃さないため、ジョブの関数を呼ぶ形にはしない）。モック画面のデータには「休止中」の区画が含まれるので、そのまま確かめられます。
5. **文書**: [soil-analysis-target-sync.md](../jobs/soil-analysis-target-sync.md#判定ルール) の判定ルールの表。

### 5.2 出力 CSV に列を足す — チェック整合失敗一覧に `ElapsedDays` を加える

1. **影響の確認**: 失敗一覧を開いて使っている人（Excel のマクロなど）がいれば、列の追加を伝える。列は末尾ではなく意味の近い位置（`AnalysisCompleted` の後）に置く。
2. **直す**: 週次の [Records.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Records.ps1) の `$script:SyncFailureColumns` に列を足し、`New-SyncFailureRecord` に `-ElapsedDays` を足す。区画の記録から作る失敗（`SYNC_FAILED` / `SYNC_EXCEPTION`、[Flow.Scan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.Scan.ps1)）では、計画の対象が持つ `ElapsedDays` を渡す。一覧全体の失敗では空のままにする。
3. **テスト**: 失敗一覧の見出しと、`SYNC_FAILED` の行に値が入ることを確かめるテストを足す。
4. **文書**: [soil-analysis-target-sync.md](../jobs/soil-analysis-target-sync.md#チェック整合失敗一覧failurecsvfilename) の列の一覧。

### 5.3 ボタンの名前が変わった — 作付け台帳の「CSV出力」が「CSVダウンロード」になった

1. **意味の確認**: 名前だけが変わり、押したときの動き（作付け記録の CSV がダウンロードされる）が同じであることを業務担当に確認する。動きが変わったなら、これは「意味」の変更なので、ジョブの流れから見直す。
2. **直す**: [planting-record-export.detail.js](../../app/browser/features/planting-record-export.detail.js) の `const CSV_BUTTON_NAME = 'CSV出力'` を直す。探し方は変えない（「ちょうど1つ」で決める）。
3. **テスト・モック**: [tests/js/fixtures/planting-ledger.js](../../tests/js/fixtures/planting-ledger.js) と [mock/site/planting-ledger](../../mock/site/planting-ledger) のボタンの名前を直し、tests/js と E2E を実行する。古い名前のままの画面では契約違反で止まることも確かめる。
4. **文書**: 部品の冒頭コメントの「契約（意味）」と、[page-contracts.md](../browser/page-contracts.md#作付け台帳区画一覧と区画詳細)、[planting-record-export.md](../jobs/planting-record-export.md)。

## この文書を更新するとき

- 変更内容と直す場所の対応（ファイル・関数・定数の名前）が変わったとき
- 新しい「してはいけない直し方」が見つかったとき
