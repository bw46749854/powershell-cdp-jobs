# 温室運用の自動化ジョブ（greenhouse-ops-automation）

Web 画面で行っている定型作業を、PowerShell からブラウザを操作して自動化するジョブ群です。
ブラウザ（Microsoft Edge / Google Chrome）とは Chrome DevTools Protocol（CDP）で通信し、追加のソフトウェアをインストールせずに Windows 標準の Windows PowerShell 5.1 で動きます。

題材は架空の温室運用です。「温室コンソール」と「作付け台帳」という2つの業務画面を対象に、次の作業を行います。

| 作業 | 入口 | 内容 |
|---|---|---|
| 週次: 土壌分析対象の整合 | `週次_土壌分析対象の整合.bat` | 区画一覧を CSV で出力し、その CSV の判定どおりに、画面の「土壌分析の対象」チェックを ON / OFF に揃える |
| 月次: 定植レポート | `月次_定植レポート.bat` | 区画ごとに作付け記録 CSV を保存し、先月に定植した作付けを1つの CSV にまとめる |

2つの作業は、次の4つのジョブを組み合わせた「連携ジョブ」です。ジョブは単独でも実行できます。

| ジョブ | ブラウザ | 内容 | 説明 |
|---|---|---|---|
| `PlotRosterExport` | 使う | 温室コンソールの区画一覧を CSV 出力し、日付入りの名前で保存する | [docs/jobs/plot-roster-export.md](docs/jobs/plot-roster-export.md) |
| `SoilAnalysisTargetSync` | 使う | 区画一覧 CSV の判定どおりに、区画ごとのチェックを ON / OFF に揃える（依頼ボタンは押さない） | [docs/jobs/soil-analysis-target-sync.md](docs/jobs/soil-analysis-target-sync.md) |
| `PlantingRecordExport` | 使う | 作付け台帳の区画を1つずつ開き、作付け記録 CSV を区画コード付きの名前で保存する | [docs/jobs/planting-record-export.md](docs/jobs/planting-record-export.md) |
| `LastMonthPlantingDigest` | 使わない | 作付け記録 CSV 群から、先月に定植した作付けを1つの CSV に集める | [docs/jobs/last-month-planting-digest.md](docs/jobs/last-month-planting-digest.md) |
| `WeeklySoilAnalysisSync` | （子ジョブが使う） | `PlotRosterExport` → `SoilAnalysisTargetSync` | [docs/jobs/weekly-soil-analysis-sync.md](docs/jobs/weekly-soil-analysis-sync.md) |
| `MonthlyPlantingReport` | （子ジョブが使う） | `PlantingRecordExport` → `LastMonthPlantingDigest` | [docs/jobs/monthly-planting-report.md](docs/jobs/monthly-planting-report.md) |

## 特徴

- **画面の DOM を契約として扱う。** 画面の「意味」（見出しの文言、ボタンの名前、選択状態、件数など）が変わったら、推測で続けずに止まります。タグ・クラス・入れ子・列の並びといった「構造」の軽微な変更は吸収します。→ [docs/browser/page-contracts.md](docs/browser/page-contracts.md)
- **誤操作をしない止め方。** 操作するタブは画面識別に一致したものがちょうど1つのときだけ選び、件数が CSV と画面で一致しなければチェック操作を始めません。失敗は一覧 CSV に残します。
- **疎結合な構成。** ジョブはファイル・時刻・ブラウザに「ポート」（決まった形の窓口）からしか触れません。ポートは実行基盤が組み立てて渡すため、ジョブ単位でテストできます。→ [ARCHITECTURE.md](ARCHITECTURE.md)
- **テストで境界を守る。** 単体テストに加え、設計上の境界・Windows PowerShell 5.1 との互換・同梱設定の妥当性・文書の網羅をテストで確かめます。実ブラウザとモック画面による E2E テストもあります。→ [docs/guides/testing.md](docs/guides/testing.md)

## はじめに

モック画面（架空の業務画面）を使えば、本番の画面がなくても手元で動きを確認できます。

1. `mock\start-mock-site.bat` を実行する（http://localhost:8080/ でモック画面を配信）
2. `mock\open-browser.bat` を実行する（リモートデバッグ付きの Edge で2つの画面を開く）
3. `週次_土壌分析対象の整合.bat` または `月次_定植レポート.bat` を実行する
4. 結果は `work\` 配下に出力される

詳しい手順と、本番の画面で動かす前の確認は [docs/guides/getting-started.md](docs/guides/getting-started.md)、日々の運用は [docs/guides/operations.md](docs/guides/operations.md) を参照してください。

## 動作環境

| 用途 | 必要なもの |
|---|---|
| 実行 | Windows 10 / 11、Windows PowerShell 5.1（標準搭載）、Microsoft Edge または Google Chrome |
| テスト（PowerShell） | 上記に加えて追加インストール不要（Pester 5.7.1 を `tools/vendor` に同梱） |
| テスト（ブラウザスクリプト） | Node.js 22 以上と `npm install`（jsdom） |
| E2E テスト | Edge / Chrome / Chromium（見つからなければ自動で Skipped） |

PowerShell 7 でも動きますが、本番の基準は Windows PowerShell 5.1 です。→ [docs/guides/powershell-compatibility.md](docs/guides/powershell-compatibility.md)

## フォルダー構成

```text
週次_土壌分析対象の整合.bat   運用の入口（週次）
月次_定植レポート.bat         運用の入口（月次）
app/
  invoke-job.ps1              ジョブを1つ実行する入口（.bat から呼ばれる）
  config/                     jobs.psd1（ジョブの実装定義）/ settings.psd1（実行時の設定）
  modules/                    PowerShell モジュール（実行基盤・ブラウザ境界・各ジョブ）
  browser/                    ページへ注入する JavaScript（画面の契約と操作）
mock/                         モック画面と、それを配信する小さな Web サーバー
tests/                        Pester テスト、ブラウザスクリプトのテスト（Node.js）、E2E テスト
tools/                        テスト実行・文字コード整形のスクリプト、同梱した Pester
docs/                         ガイド・ジョブごとの説明・モジュールの説明・設計判断
work/                         実行時の出力先（git 管理外）
```

## テスト

```bash
pwsh -File tools/Invoke-Tests.ps1
```

Windows では `tools\run-tests.bat`（Windows PowerShell 5.1）でも実行できます。E2E テストを含めるときは `-IncludeE2E` を付けます。pull request では GitHub Actions（[.github/workflows/tests.yml](.github/workflows/tests.yml)）が Windows PowerShell 5.1 を含めて実行します。詳しくは [docs/guides/testing.md](docs/guides/testing.md) を参照してください。

## ドキュメント

読む順番と文書の一覧は [docs/README.md](docs/README.md) にあります。設計の全体像は [ARCHITECTURE.md](ARCHITECTURE.md) から読んでください。
