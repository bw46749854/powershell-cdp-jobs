# MonthlyPlantingReport — 月次の連携（作付け記録の保存 → 先月の定植の集約）

実行ごとのフォルダーを作り、その中へ [PlantingRecordExport](planting-record-export.md) で区画ごとの作付け記録 CSV を保存し、同じフォルダーを [LastMonthPlantingDigest](last-month-planting-digest.md) で集計します。入口は `月次_定植レポート.bat` です。実装は [JobChains](../modules/JobChains.md) モジュールにあります。

| 項目 | 内容 |
|---|---|
| 子ジョブ | `PlantingRecordExport` → `LastMonthPlantingDigest` |
| 受け渡し | 実行フォルダーの `planting_export_tmp` / `planting_export_downloads` を `PlantingRecordExport` の `TempDirectory` / `DownloadDirectory` に、`planting_export_downloads` を `LastMonthPlantingDigest` の `TargetDirectory` に上書きして渡す |
| 設定 | [Jobs.MonthlyPlantingReport](../guides/configuration.md#jobsmonthlyplantingreport) |

## 実行フォルダー

```text
<RunRootDirectory>/
  yyyyMMdd_HHmmss/                 実行した日時（Clock から）
    planting_export_tmp/           PlantingRecordExport の一時ダウンロード先
    planting_export_downloads/     PlantingRecordExport の保存先 = LastMonthPlantingDigest の読み取り元・出力先
```

実行ごとに新しいフォルダーを使うのは、過去の実行で保存した CSV が集計に混ざらないようにするためです。

## 流れ

| 順 | 処理 | 止まる条件 |
|---|---|---|
| 1 | `RunRootDirectory` を設定から読む | 設定が無い |
| 2 | 実行フォルダーと2つのサブフォルダーを作る | 安全でないパス |
| 3 | `PlantingRecordExport` を実行する | 子ジョブの失敗（件数不足・保存の失敗を含む） |
| 4 | `PlantingRecordExport` の `DownloadFilePrefix` を読み、保存先に `<DownloadFilePrefix>*.csv` が1件以上あることを確かめる（中身は読まない） | 接頭辞が無い・ワイルドカード文字を含む / 成果物が0件 |
| 5 | `LastMonthPlantingDigest` を `TargetDirectory` を上書きして実行する | 子ジョブの失敗 |

成果物を接頭辞で数えるのは、保存先に置かれうる失敗一覧（`failed_planting_exports.csv`）を成果物と取り違えないためです。

## 設計の理由と注意点

- **`PlantingRecordExport` の `TempDirectory` / `DownloadDirectory` の設定は、月次の連携では使われません。** 実行フォルダーのサブフォルダーで上書きされます。設定の値は、単独で実行したときだけ使います。
- **前段が1区画でも失敗すると、集計は動きません。** 一部の区画が欠けたまま「先月の定植」を作らないためです。失敗一覧を見て原因を直し、もう一度連携ジョブを実行します（新しい実行フォルダーが作られます）。
- **実行フォルダーは消さずに残ります。** 後から結果を確かめられるようにするためです。たまったら運用で片付けます（[operations.md](../guides/operations.md)）。
- `DownloadFilePrefix` にワイルドカード文字（`*` `?` `[` `]`）は使えません。成果物を数える条件として、そのままファイル名のフィルターに使うためです。

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.RunDirectory` / `TempDirectory` / `DownloadDirectory` | 今回の実行フォルダーと、そのサブフォルダー |
| `Outputs.ExportedCsvPaths` | 見つけた成果物 CSV のパスの配列 |
| `Outputs.PlantingRecordExport` / `Outputs.LastMonthPlantingDigest` | 子ジョブの `Outputs` |
| `Summary.RunStamp` | 実行フォルダーの名前（`yyyyMMdd_HHmmss`） |
| `Summary.PlantingRecordExport` / `Summary.LastMonthPlantingDigest` | 子ジョブの `Summary` |

## ファイル

| ファイル | 役割 |
|---|---|
| [Public/Invoke-MonthlyPlantingReportJob.ps1](../../app/modules/JobChains/Public/Invoke-MonthlyPlantingReportJob.ps1) | ジョブコマンド |
| [Private/Monthly.ps1](../../app/modules/JobChains/Private/Monthly.ps1) | 設定の検証、実行フォルダーの作成、成果物の確認、処理の順序 |

連携ジョブで共有するファイル（ポート・子ジョブの呼び出し）は [JobChains.md](../modules/JobChains.md) にあります。

## テスト

| テスト | 内容 |
|---|---|
| [JobChains.Tests.ps1](../../tests/pester/JobChains/JobChains.Tests.ps1) | 実行フォルダーの名前と作る順序、受け渡し、成果物が0件・接頭辞が不正・子ジョブが失敗したときに集計を動かさないこと |
| [HostedChains.Tests.ps1](../../tests/pester/JobChains/HostedChains.Tests.ps1) | 実行基盤を通して、本物の LastMonthPlantingDigest が今回の実行フォルダーだけを集計すること |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 実ブラウザとモック画面での通しの実行 |

## この文書を更新するとき

- 子ジョブ・実行フォルダーの構成・受け渡す値・止まる条件・結果の形・設計の理由が変わったとき
