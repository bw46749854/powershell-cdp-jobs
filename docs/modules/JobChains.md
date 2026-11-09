# JobChains — 連携ジョブ

既存のジョブを決まった順に実行し、前のジョブの成果物（パス）を次のジョブへ渡す、薄い連携の層です。画面操作・CSV の解析・業務の判定は持ちません。それぞれ子ジョブの責務です。

| 連携ジョブ | 子ジョブ | 説明 |
|---|---|---|
| `WeeklySoilAnalysisSync` | `PlotRosterExport` → `SoilAnalysisTargetSync` | [weekly-soil-analysis-sync.md](../jobs/weekly-soil-analysis-sync.md) |
| `MonthlyPlantingReport` | `PlantingRecordExport` → `LastMonthPlantingDigest` | [monthly-planting-report.md](../jobs/monthly-planting-report.md) |

依存: `JobKit` だけ。子ジョブのモジュールを読み込まず、`Jobs` サービス（JobHost）を通して子ジョブを起動します。

## 約束

- **子ジョブは単独実行と同じ入口で動く。** `Jobs.Run` は `Invoke-HostedJob` を呼ぶので、設定の読み込み・検証・Context の組み立て・結果の検証・後始末がすべて単独実行と同じです。
- **親と子は同じ設定ファイル・ジョブ定義を使う。** `Jobs.Run` はパスを受け取る口を持ちません。同じ連携の中で、親と子が別の設定を読む状態は作れません。→ [decisions/0005-child-jobs-share-settings.md](../decisions/0005-child-jobs-share-settings.md)
- **受け渡すのはパスだけ。** 前段の成果物は、存在すること（週次: ファイルがある、月次: 接頭辞に合うファイルが1件以上ある）だけを確かめます。中身の妥当性は後段のジョブが判断します。
- **失敗した時点で止まる。** 子ジョブの失敗は例外のまま呼び出し元へ伝わり、後段の子ジョブは動きません。子ジョブの結果は、`Jobs` サービスの実装に頼らず、ここでも結果の約束（`Assert-JobResult`）どおりか確かめます。
- **上書きはログに残す。** 子ジョブへ渡す上書き値は、`引き渡し: <子ジョブ>.<キー> = <値>` の形でログに出します。

## コードの読み方

```text
Invoke-<連携>Job（Public）
  New-JobChainPorts / Assert-JobChainPorts      Log / Clock / Files / Jobs だけを使う
  Invoke-<連携>Flow（Weekly.ps1 / Monthly.ps1）
    Invoke-ChainStep -JobName <子ジョブ> [-Overrides @{ … }]   子ジョブを実行し、結果の約束を確かめる
    Get-ChainOutputText -Result … -Name …                       前段の Outputs から値を1つ受け取る（無ければ止める）
  New-JobResult                                  子ジョブの Outputs / Summary をまとめて返す
```

新しい連携ジョブを足すときは、`Private/<名前>.ps1` に Flow を書き、`Public/` にジョブコマンドを置いて jobs.psd1 に登録します。連携ジョブの中で CSV を読む・画面を操作する・判定をする必要が出たら、それは子ジョブの責務です（連携ジョブに書かない）。

## ファイル構成

| ファイル | 役割 |
|---|---|
| [JobChains.psm1](../../app/modules/JobChains/JobChains.psm1) | 読み込むファイルの一覧と公開関数（2つのジョブコマンド） |
| [Public/Invoke-WeeklySoilAnalysisSyncJob.ps1](../../app/modules/JobChains/Public/Invoke-WeeklySoilAnalysisSyncJob.ps1) | 週次のジョブコマンド |
| [Public/Invoke-MonthlyPlantingReportJob.ps1](../../app/modules/JobChains/Public/Invoke-MonthlyPlantingReportJob.ps1) | 月次のジョブコマンド |
| [Private/Ports.ps1](../../app/modules/JobChains/Private/Ports.ps1) | 合成ルート（Log / Clock / Files / Jobs） |
| [Private/ChainSteps.ps1](../../app/modules/JobChains/Private/ChainSteps.ps1) | 子ジョブ1つの実行と結果の検証、結果からの値の受け取り |
| [Private/Weekly.ps1](../../app/modules/JobChains/Private/Weekly.ps1) | 週次の順序と受け渡し |
| [Private/Monthly.ps1](../../app/modules/JobChains/Private/Monthly.ps1) | 月次の設定、実行フォルダー、成果物の確認、順序と受け渡し |

## テスト

| テスト | 内容 |
|---|---|
| [JobChains.Tests.ps1](../../tests/pester/JobChains/JobChains.Tests.ps1) | 偽の `Jobs` / `Files` で、順序・受け渡し・止まり方を確かめる |
| [HostedChains.Tests.ps1](../../tests/pester/JobChains/HostedChains.Tests.ps1) | ジョブ定義だけでブラウザを使う子ジョブを差し替え、本物の実行基盤・連携・集計を通しで動かす |

## この文書を更新するとき

- 連携ジョブの種類、受け渡しの約束、ファイル構成が変わったとき
