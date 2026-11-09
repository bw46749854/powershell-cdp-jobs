# WeeklySoilAnalysisSync — 週次の連携（区画一覧の出力 → 土壌分析対象の整合）

[PlotRosterExport](plot-roster-export.md) で区画一覧 CSV を出力し、その CSV を入力にして [SoilAnalysisTargetSync](soil-analysis-target-sync.md) を実行します。入口は `週次_土壌分析対象の整合.bat` です。実装は [JobChains](../modules/JobChains.md) モジュールにあります。

| 項目 | 内容 |
|---|---|
| 子ジョブ | `PlotRosterExport` → `SoilAnalysisTargetSync` |
| 受け渡し | `PlotRosterExport` の `Outputs.ExportedCsvPath` を、`SoilAnalysisTargetSync` の `InputCsvPath` に上書きして渡す |
| 設定 | [Jobs.WeeklySoilAnalysisSync](../guides/configuration.md#jobsweeklysoilanalysissync)（項目なし） |

## 流れ

| 順 | 処理 | 止まる条件 |
|---|---|---|
| 1 | `PlotRosterExport` を実行する | 子ジョブの失敗（例外をそのまま伝える） |
| 2 | 結果が結果プロトコルどおりで、`Outputs.ExportedCsvPath` が空でないことを確かめる | 結果の形が違う・パスが無い |
| 3 | そのファイルが存在することを確かめる（中身は読まない） | ファイルが無い |
| 4 | `SoilAnalysisTargetSync` を `InputCsvPath` を上書きして実行する | 子ジョブの失敗 |

子ジョブは、単独で実行したときと同じ入口（設定・ジョブ定義・Context の組み立て）を通り、**親と同じ設定ファイルとジョブ定義**で動きます。上書きはこの1回の実行だけに効き、設定ファイルは変わりません。

## 設計の理由と注意点

- **前段の CSV が実在することを確かめてから後段を動かす。** パスだけを渡して後段で「入力 CSV が見つかりません」になるより、どこで途切れたかが分かりやすいためです。中身の妥当性は後段が判断します。
- **前段を飛ばして、手元の古い CSV で後段だけを動かさない。** 古い CSV は画面の件数と合わず止まるはずですが、区画が増減していない場合は通ってしまい、古い計測日時で判定することになります。週次は必ず連携ジョブとして最初から実行します。
- 連携の途中で止まったときも、最初から実行し直してかまいません（後段は何度実行しても同じ結果になります）。

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.InputCsvPath` | `SoilAnalysisTargetSync` に渡した CSV のパス |
| `Outputs.PlotRosterExport` / `Outputs.SoilAnalysisTargetSync` | 子ジョブの `Outputs` |
| `Summary.PlotRosterExport` / `Summary.SoilAnalysisTargetSync` | 子ジョブの `Summary` |

## ファイル

| ファイル | 役割 |
|---|---|
| [Public/Invoke-WeeklySoilAnalysisSyncJob.ps1](../../app/modules/JobChains/Public/Invoke-WeeklySoilAnalysisSyncJob.ps1) | ジョブコマンド |
| [Private/Weekly.ps1](../../app/modules/JobChains/Private/Weekly.ps1) | 処理の順序と受け渡し |

連携ジョブで共有するファイル（ポート・子ジョブの呼び出し）は [JobChains.md](../modules/JobChains.md) にあります。

## テスト

| テスト | 内容 |
|---|---|
| [JobChains.Tests.ps1](../../tests/pester/JobChains/JobChains.Tests.ps1) | 呼び出しの順序と受け渡し、CSV が無い・パスが無い・子ジョブが失敗した・結果の形が違うときに後段を動かさないこと |
| [HostedChains.Tests.ps1](../../tests/pester/JobChains/HostedChains.Tests.ps1) | 実行基盤を通して、子ジョブが上書きされた入力を受け取ること |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 実ブラウザとモック画面での通しの実行 |

## この文書を更新するとき

- 子ジョブ・受け渡す値・止まる条件・結果の形・設計の理由が変わったとき
