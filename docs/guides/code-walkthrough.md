# 実行の流れをコードで追う

`週次_土壌分析対象の整合.bat` をダブルクリックしてから終わるまでに、**どのファイルのどの関数が、どの順で動くか**を追います。[ARCHITECTURE.md](../../ARCHITECTURE.md) が「何がどこにあるか」の地図なら、この文書は実際に1回たどる道順です。PowerShell の書き方で分からないところは [powershell-primer.md](powershell-primer.md) を参照してください。

例に使うのは週次の連携ジョブ `WeeklySoilAnalysisSync` です。単独のジョブ・連携ジョブ・ブラウザを使うジョブ・使わない処理が、すべて含まれています。

## 1. 入口 — .bat から Invoke-HostedJob まで

```text
週次_土壌分析対象の整合.bat
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File app\invoke-job.ps1 -JobName WeeklySoilAnalysisSync
    app/invoke-job.ps1
      Import-Module app/modules/JobHost/JobHost.psm1
      Invoke-HostedJob -AppRoot <app> -JobName WeeklySoilAnalysisSync -SettingsPath '' -CatalogPath ''
```

- `.bat` はジョブ名を1つ渡すだけです。終了コードが 0 以外なら `FAILED` を表示して止まります。
- [invoke-job.ps1](../../app/invoke-job.ps1) は JobHost を読み込んで `Invoke-HostedJob` を呼ぶだけです。業務の処理は書きません。

## 2. 実行基盤 — 設定を読み、Context を作る

[Invoke-HostedJob.ps1](../../app/modules/JobHost/Public/Invoke-HostedJob.ps1) が次の順で動きます。

| 順 | 関数（ファイル） | すること |
|---|---|---|
| 1 | `Import-HostSettings`（[HostSettings.ps1](../../app/modules/JobHost/Private/HostSettings.ps1)） | `app/config/settings.psd1` を読み、`…Path` / `…Directory` の値をプロジェクトのルート基準の絶対パスにする |
| 2 | `Import-JobCatalog` / `Get-JobCatalogEntry` / `Assert-JobCatalogEntryFiles`（[JobCatalog.ps1](../../app/modules/JobHost/Private/JobCatalog.ps1)） | `app/config/jobs.psd1` から `WeeklySoilAnalysisSync` の定義を引き、モジュール・スクリプトのファイルが揃っているか確かめる |
| 3 | `New-HostRunContext`（[RunContext.ps1](../../app/modules/JobHost/Private/RunContext.ps1)） | 時計 → 実行 ID → ログ → ジョブの設定のコピー → サービスの順に組み立てる。`UsesBrowser = $false` なので `Browser` は `$null` |
| 4 | `Import-Module` → `Get-Command` | 定義の `Module`（`JobChains.psm1`）を読み込み、`Command`（`Invoke-WeeklySoilAnalysisSyncJob`）を探す |
| 5 | `& $command -Context $context` | ジョブコマンドを呼ぶ。出力は `@( … )` で全部集める |
| 6 | `Assert-JobResult`（JobKit） | 出力がちょうど1つの成功結果か確かめる |
| 7 | `Close-HostRunContext`（finally） | 成功・失敗にかかわらずブラウザ接続を閉じる |

このときの Context は、例えば次のようになります（値は一例）。

```text
JobName      : WeeklySoilAnalysisSync
RunId        : 20260415_093000_123
AppRoot      : C:\…\ps1_CDP\app
ProjectRoot  : C:\…\ps1_CDP
Entry        : Name / Module / Command / UsesBrowser=False
Settings     : @{}                          ← Jobs.WeeklySoilAnalysisSync のコピー（週次は設定を持たない）
Common       : Browser / Logging
Services     : Log / Clock / Files / Downloads / Lists / Jobs / Browser=$null
```

よくある誤解:

- **Context の `Settings` は設定ファイル全体ではありません。** `Jobs.<そのジョブ名>` のコピーだけです。他のジョブの設定を読みたいときは `Jobs.GetSettings`（連携ジョブだけが使う）を使います。
- **ジョブ名とモジュール名は別物です。** `WeeklySoilAnalysisSync` と `MonthlyPlantingReport` は、どちらも `JobChains` モジュールの別のコマンドです。対応は jobs.psd1 だけが知っています。

## 3. 連携ジョブ — 子ジョブを順に呼ぶ

[Invoke-WeeklySoilAnalysisSyncJob.ps1](../../app/modules/JobChains/Public/Invoke-WeeklySoilAnalysisSyncJob.ps1) → `New-JobChainPorts` / `Assert-JobChainPorts`（[Ports.ps1](../../app/modules/JobChains/Private/Ports.ps1)）→ `Invoke-WeeklySoilAnalysisSyncFlow`（[Weekly.ps1](../../app/modules/JobChains/Private/Weekly.ps1)）。

```text
Invoke-WeeklySoilAnalysisSyncFlow
  Invoke-ChainStep -JobName PlotRosterExport                     （ChainSteps.ps1）
    & $Ports.Jobs.Run -JobName PlotRosterExport                    → Invoke-HostedJob（2章をもう一度。今度は Browser あり）
    Assert-JobResult
  Get-ChainOutputText -Name ExportedCsvPath                        前段の Outputs から CSV のパスを受け取る
  & $Ports.Files.Exists -Path <CSV>                                 無ければ「連携エラー」で止める
  Invoke-ChainStep -JobName SoilAnalysisTargetSync -Overrides @{ InputCsvPath = <CSV> }
    & $Ports.Jobs.Run …                                             → Invoke-HostedJob（上書き値つき）
```

- `Jobs.Run`（[ChildJobs.ps1](../../app/modules/JobHost/Private/ChildJobs.ps1)）は、親と同じ `SettingsPath` / `CatalogPath` で `Invoke-HostedJob` を呼びます。子ジョブは単独で実行したときと同じ道を通ります。
- 上書き値は `Get-HostJobSettings` が子ジョブの設定のコピーに適用します。パスの値は設定ファイルと同じ規則で解決されます。
- 子ジョブが例外で終わると、`Invoke-ChainStep` はそれを捕まえないので、連携全体がそこで止まります。

## 4. ブラウザを使うジョブ — PlotRosterExport の中

[Invoke-PlotRosterExportJob.ps1](../../app/modules/PlotRosterExport/Public/Invoke-PlotRosterExportJob.ps1):

```text
Read-PlotRosterExportSettings      設定をすべて型付きで読む（足りなければここで止まる）
New-PlotRosterExportPorts          Context.Services から使うものだけを取り出し、Browser からページポートを作る
Assert-PlotRosterExportPorts       ポートの形を検証する
Invoke-PlotRosterExportFlow        処理の順序（Flow.ps1）
New-JobResult                      Outputs に DownloadedCsvPath / ExportedCsvPath
```

Flow の1行が、どこまで降りていくかを追います。例: `& $page.AssertExportScreen`。

```text
Flow.ps1           & $page.AssertExportScreen
Page.ps1             & $Browser.Assert -Operation 'CheckExportScreen'                        業務名 → 操作名
BrowserService.ps1     Invoke-HostBrowserGateway -Member Assert                               JobHost → PageBridge
PageGateway.ps1          Assert-PageOperationContract
OperationCatalog.ps1       Get-PageOperation -Use Assert                                       Kind=Contract か確かめる
HelperCall.ps1             New-HelperCallExpression                                            JavaScript の式を作る
CdpRuntime.ps1             Wait-CdpEvaluation                                                  fatal が 0 になるまで 250 ミリ秒ごとに評価し直す
CdpRuntime.ps1               Invoke-CdpEvaluate                                                Runtime.evaluate
CdpSession.ps1                 Send-CdpCommand                                                 id 付きで送り、同じ id の応答を待つ
                             ……ページの中で window.__pagekit.helpers.plotRosterExport.checkExportScreen() が動く
ContractResult.ps1         Assert-PageContractScope / Assert-PageContractPassed               scope の一致、fatal が無いこと（期限切れなら最後の結果の詳細付きで契約違反）
```

最初の `& $page.Connect` だけは特別で、タブを選ぶ処理が入ります（[PageBridge.md](../modules/PageBridge.md#タブの選び方)）。

```text
Connect-HostBrowser → Open-PageConnection（PageConnection.ps1）
  Get-CdpPageTargets                     http://localhost:9222/json からタブ一覧を得る
  Select-IdentifiedPageTarget            操作し得るタブだけに絞り、1つずつ
    Test-PageTargetIdentity                一時的に接続 → スクリプトを注入 → DetectScreen（Kind=Identity）
  一致がちょうど1つなら Open-CdpSession → New-PageGateway
```

ダウンロードの完了待ちと保存名の付け替えはブラウザではなく、`Downloads.WaitForFile`（[DownloadWatcher.ps1](../../app/modules/JobHost/Private/DownloadWatcher.ps1)）と `Files.MoveToUnique`（[FileService.ps1](../../app/modules/JobHost/Private/FileService.ps1)）が行います。

## 5. 後段 — SoilAnalysisTargetSync

子ジョブとしての入り方は4章と同じです。中身の順序は [Flow.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.ps1) の冒頭コメントと [soil-analysis-target-sync.md](../jobs/soil-analysis-target-sync.md#流れ) にあります。読むときの目印は次の3つです。

| 目印 | 場所 | 意味 |
|---|---|---|
| ブラウザに触れる前に止まる | `Invoke-SoilAnalysisSyncFlow` の CSV データエラーの判定 | 判定できない行があれば画面に一切触れない |
| 操作を始める前に止まる | `Open-SoilAnalysisScreen` の件数の比較 | CSV と画面の件数が合わなければチェックを触らない |
| 区画ごとに続けるか止まるか | `Invoke-SoilAnalysisPlotSync`（[Flow.Scan.ps1](../../app/modules/SoilAnalysisTargetSync/Private/Flow.Scan.ps1)）の `Fatal` | 通信を続けられない失敗なら走査を止め、それ以外は記録して次の区画へ |

## 6. 終わり方

- 子ジョブがそれぞれ `New-JobResult` を返し、親の `Invoke-ChainStep` が確かめ、最後に週次のジョブコマンドが自分の結果を返します。
- `Invoke-HostedJob` が `正常終了` のセクションを書き、`invoke-job.ps1` は終了コード 0 で終わります。
- どこかで例外になると、`Invoke-HostedJob` が `<ジョブ名> は異常終了しました: …` をログに書いて例外を投げ直し、`invoke-job.ps1` は終了コード 1 で終わります。子ジョブの失敗は、子・親の両方の `Invoke-HostedJob` でログに残ります。

## この文書を更新するとき

- 入口（.bat・invoke-job.ps1）、`Invoke-HostedJob` の順序、Context の項目、連携の受け渡し、ブラウザ呼び出しの経路が変わったとき
