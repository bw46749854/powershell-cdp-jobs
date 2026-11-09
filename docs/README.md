# ドキュメントの地図

## 目的別の読む順番

| 目的 | 読む順番 |
|---|---|
| まず動かしてみたい | [guides/getting-started.md](guides/getting-started.md) → [../mock/README.md](../mock/README.md) |
| 週次・月次の作業を運用する | [guides/operations.md](guides/operations.md) → [guides/troubleshooting.md](guides/troubleshooting.md) → [guides/configuration.md](guides/configuration.md) |
| PowerShell に慣れていない | [guides/powershell-primer.md](guides/powershell-primer.md) → [glossary.md](glossary.md) |
| コードを読み始める | [../ARCHITECTURE.md](../ARCHITECTURE.md) → [guides/code-walkthrough.md](guides/code-walkthrough.md) → [modules/JobKit.md](modules/JobKit.md) → [modules/JobHost.md](modules/JobHost.md) → [jobs/plot-roster-export.md](jobs/plot-roster-export.md)（一番短いジョブ） → [modules/PageBridge.md](modules/PageBridge.md) → [browser/pagekit.md](browser/pagekit.md) |
| 画面が変わって止まった | [guides/troubleshooting.md](guides/troubleshooting.md) → [guides/changing-page-contracts.md](guides/changing-page-contracts.md) → [browser/page-contracts.md](browser/page-contracts.md) |
| 既存のジョブを直す | [guides/making-changes.md](guides/making-changes.md) → 該当する [jobs](jobs) の文書 → [guides/testing.md](guides/testing.md) |
| ジョブを追加する | [guides/adding-a-job.md](guides/adding-a-job.md) → [guides/testing.md](guides/testing.md) |
| 構造を整理する・設計を変える | [guides/maintenance-rules.md](guides/maintenance-rules.md) → [guides/design-principles.md](guides/design-principles.md) → [decisions](decisions/README.md) |
| AI（Claude Code など）に作業させる | [../CLAUDE.md](../CLAUDE.md) → [guides/maintenance-rules.md](guides/maintenance-rules.md) |
| テストを書く・直す | [guides/testing.md](guides/testing.md) → [guides/powershell-compatibility.md](guides/powershell-compatibility.md) |
| 設計の理由を知りたい | [decisions](decisions/README.md) → [guides/design-principles.md](guides/design-principles.md) |

## 文書の一覧

### ガイド（guides）

| 文書 | 内容 |
|---|---|
| [getting-started.md](guides/getting-started.md) | 前提、モック画面で試す手順、本番で動かす前の確認 |
| [operations.md](guides/operations.md) | 週次・月次の実行手順、成果物の確認、失敗したときの対応 |
| [configuration.md](guides/configuration.md) | settings.psd1 / jobs.psd1 の全項目 |
| [troubleshooting.md](guides/troubleshooting.md) | 主なエラーメッセージと原因・対処 |
| [changing-page-contracts.md](guides/changing-page-contracts.md) | 画面が変わったときの判断と、ページスクリプトの直し方 |
| [adding-a-job.md](guides/adding-a-job.md) | ジョブの追加手順とチェックリスト |
| [testing.md](guides/testing.md) | テストの層、実行方法、テスト補助、変更とテストの対応、落ちたときの読み方、テストを直してよい条件 |
| [powershell-compatibility.md](guides/powershell-compatibility.md) | Windows PowerShell 5.1 で動かすための約束 |
| [powershell-primer.md](guides/powershell-primer.md) | このプロジェクトで使う PowerShell の書き方（入門） |
| [code-walkthrough.md](guides/code-walkthrough.md) | .bat から終了まで、どの関数がどの順に動くか |
| [making-changes.md](guides/making-changes.md) | 変更内容・起きたことから直す場所を引く、やってはいけない直し方、具体例 |
| [design-principles.md](guides/design-principles.md) | 責務の置き場所、依存の向き、抽象を残す・消す、似たコードをまとめるかの判断基準 |
| [maintenance-rules.md](guides/maintenance-rules.md) | AI と人の共通の保守規約（不変条件・判定の手順・進め方・提案の形） |

### 用語集

[glossary.md](glossary.md) — 設計・ブラウザとの境界・業務（題材）の言葉。

### ジョブ（jobs）

| 文書 | ジョブ |
|---|---|
| [plot-roster-export.md](jobs/plot-roster-export.md) | `PlotRosterExport` |
| [soil-analysis-target-sync.md](jobs/soil-analysis-target-sync.md) | `SoilAnalysisTargetSync` |
| [planting-record-export.md](jobs/planting-record-export.md) | `PlantingRecordExport` |
| [last-month-planting-digest.md](jobs/last-month-planting-digest.md) | `LastMonthPlantingDigest` |
| [weekly-soil-analysis-sync.md](jobs/weekly-soil-analysis-sync.md) | `WeeklySoilAnalysisSync`（連携） |
| [monthly-planting-report.md](jobs/monthly-planting-report.md) | `MonthlyPlantingReport`（連携） |

### モジュール（modules）

| 文書 | モジュール |
|---|---|
| [JobKit.md](modules/JobKit.md) | 共有の約束事（ポート・結果・設定値） |
| [JobHost.md](modules/JobHost.md) | 実行基盤とサービス |
| [PageBridge.md](modules/PageBridge.md) | ブラウザとの境界 |
| [JobChains.md](modules/JobChains.md) | 連携ジョブ |

ジョブのモジュール（PlotRosterExport など）のファイル構成は、それぞれのジョブの文書にあります。

### ブラウザ（browser）

| 文書 | 内容 |
|---|---|
| [pagekit.md](browser/pagekit.md) | ページスクリプトの核（pagekit）の API と、部品の書き方 |
| [page-contracts.md](browser/page-contracts.md) | 画面ごとの契約（意味）と、吸収する構造の違い |

### 設計判断（decisions）

[decisions/README.md](decisions/README.md) に一覧があります。

## 文書を保守する約束

- 文書はコードと同じ変更で直します。直す対象は、各文書の末尾の「この文書を更新するとき」に書いてあります。
- **1つの話題は1か所に書きます。** ほかの文書では繰り返さずにリンクします（例: 5.1 で使えない書き方は powershell-compatibility.md だけ、ファイルごとの役割はジョブ・モジュールの文書の「ファイル構成」だけ）。
- **正本**: 何が正しいかは、次の順で決まります。
  1. コードとテスト（実際の振る舞い）
  2. [../ARCHITECTURE.md](../ARCHITECTURE.md) と [decisions](decisions/README.md)（設計の判断）
  3. ガイド・ジョブ・モジュール・ブラウザの文書（説明）
- 文書とコードが食い違っていたら、まず「意図して設計を変えたのか」「文書が古くなっただけか」を決めます。意図した変更なら、設計判断の記録・ARCHITECTURE.md・関係する文書・品質ゲートのテストを同じ変更で直します。文書が古いだけなら文書を直します。どちらとも言えないときは、直さずに相談します（[guides/maintenance-rules.md](guides/maintenance-rules.md)）。
- 次のことはテスト（[tests/pester/Quality/Documentation.Tests.ps1](../tests/pester/Quality/Documentation.Tests.ps1)）で確かめています。
  - 文書内の相対リンクの行き先が存在する
  - すべてのジョブに文書があり、ジョブのモジュールのすべてのファイルがその文書に載っている
  - 実行基盤のモジュールのすべてのファイルが、モジュールの文書に載っている
  - settings.psd1 のすべての設定項目が [guides/configuration.md](guides/configuration.md) に載っている
  - すべてのページスクリプトが [browser/page-contracts.md](browser/page-contracts.md) に載っている
  - 公開関数にコメントベースのヘルプ（`.SYNOPSIS`）がある
