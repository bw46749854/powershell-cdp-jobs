# ジョブを追加する

新しいジョブ（例: `HarvestRecordExport`）を追加する手順です。既存のジョブと同じ形にそろえると、実行基盤・テスト・文書の仕組みがそのまま使えます。手本には、ブラウザを使うなら [PlotRosterExport](../jobs/plot-roster-export.md)、使わないなら [LastMonthPlantingDigest](../jobs/last-month-planting-digest.md) が向いています。

## 1. ファイルを作る

```text
app/modules/HarvestRecordExport/
  HarvestRecordExport.psm1            読み込むファイルの一覧と、公開する関数（ジョブコマンドだけ）
  PageOperations.psd1                 操作カタログ（ブラウザを使う場合）
  Public/Invoke-HarvestRecordExportJob.ps1
  Private/Settings.ps1                Read-HarvestRecordExportSettings
  Private/Ports.ps1                   New-…Ports / Assert-…Ports（合成ルート）
  Private/Page.ps1                    ページポート（ブラウザを使う場合）
  Private/Flow.ps1                    処理の順序
  Private/<規則>.ps1                  判定・命名などの純粋関数
app/browser/features/harvest-record-export.js   ページの部品とヘルパーの登録（ブラウザを使う場合）
```

### モジュール（.psm1）

既存のモジュールと同じ形にします。`JobKit` 以外のモジュールを読み込んではいけません（テストで検査）。

```powershell
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# HarvestRecordExport: <このジョブが何をするかを1行で>

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/Settings.ps1',
    'Private/Page.ps1',
    'Private/Ports.ps1',
    'Private/Flow.ps1',
    'Public/Invoke-HarvestRecordExportJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "HarvestRecordExport の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @('Invoke-HarvestRecordExportJob')
```

### ジョブコマンド

```powershell
function Invoke-HarvestRecordExportJob {
    <#
    .SYNOPSIS
    <何をするジョブか>
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-HarvestRecordExportSettings -Settings $Context.Settings   # 最初に設定をすべて検証する
    $ports = New-HarvestRecordExportPorts -Context $Context                     # 使うポートだけを取り出す
    Assert-HarvestRecordExportPorts -Ports $ports                               # 形を検証する

    $outcome = Invoke-HarvestRecordExportFlow -Ports $ports -Settings $settings
    return New-JobResult -Job 'HarvestRecordExport' -Outputs @{ … } -Summary @{ … }
}
```

- 失敗は `throw` で表します。`Ok = $false` の結果は返しません。
- 戻り値を使わない呼び出しには `[void]` を付けます（出力が漏れると「結果が2つ」として失敗します）。

### Ports.ps1（合成ルート）

使うサービスとメンバーだけを形として宣言し、`Assert-PortShape` で検証します。Context に触れてよいのは、このファイルとジョブコマンドだけです。ブラウザを使うジョブは、`Services.Browser` からページポート（`Page.ps1`）を作ります。

### Flow.ps1

処理の順序だけを書きます。ファイル・時刻・画面出力のコマンド（`Get-ChildItem`、`Get-Date`、`Start-Sleep`、`Write-Host` など）は直接使わず、`$Ports.Files`、`$Ports.Clock.Now`、`$Ports.Clock.Sleep`、`$Ports.Log` を使います（テストで検査）。手順ごとのログには `Invoke-LoggedStep`（JobKit）が使えます。

### 操作カタログとページスクリプト（ブラウザを使う場合）

- 操作カタログの `Helper` と同じ名前で、ページスクリプトが `kit.define('<Helper>', [部品…])` を呼びます。
- カタログの操作ごとに `Method`・`Kind` を決めます（[PageBridge.md](../modules/PageBridge.md#操作カタログ)）。画面識別（`Kind = 'Identity'`）はちょうど1つ必要です。同じ画面を対象にする既存のジョブがあれば、画面の部品（`app/browser/screens`）を共有します。
- 部品の冒頭コメントに「部品名」「契約（意味）」「吸収する構造の違い」を書きます（テストで検査）。書き方は [browser/pagekit.md](../browser/pagekit.md) を参照してください。

## 2. 登録する

1. [app/config/jobs.psd1](../../app/config/jobs.psd1) にジョブを追加する（`Command` は `Invoke-<ジョブ名>Job`）。
2. [app/config/settings.psd1](../../app/config/settings.psd1) に `Jobs.<ジョブ名>` を追加する（設定が無くても `@{}` が必要）。
3. ブラウザを使う場合は [tests/js/support/page.js](../../tests/js/support/page.js) の `SCRIPTS` に、jobs.psd1 と同じ順でスクリプトを追加する。
4. 品質ゲートの規則に新しいモジュールを加える（[Architecture.Tests.ps1](../../tests/pester/Quality/Architecture.Tests.ps1) の `$script:AllowedImports`、[ShippedConfig.Tests.ps1](../../tests/pester/Quality/ShippedConfig.Tests.ps1) の `$script:SettingsReaders`）。
5. 運用の入口が必要なら、リポジトリ直下に .bat を追加する（ASCII・CRLF、`-JobName` は1つ）。

## 3. テストと文書

- `tests/pester/HarvestRecordExport/` に単体テストを書く（純粋関数・設定の検証・Flow）。
- ブラウザを使う場合は `tests/js/harvest-record-export.test.js` と fixture を書く。
- `docs/jobs/harvest-record-export.md` を書き、モジュールのすべてのファイルを「ファイル構成」に載せる。
- 設定項目を [configuration.md](configuration.md) に載せる。
- ページスクリプトを [browser/page-contracts.md](../browser/page-contracts.md) に載せる。
- 必要なら [mock](../../mock) にモック画面を追加し、E2E テストを書く。

## 4. チェックリスト

- [ ] `pwsh -File tools/Invoke-Tests.ps1` がすべて通る（掲載漏れ・依存の向き・5.1 互換もここで検出される）
- [ ] `tools\run-tests.bat`（Windows PowerShell 5.1）で通る
- [ ] `pwsh -File tools/Repair-SourceEncoding.ps1 -Check` が通る
- [ ] 失敗したときのメッセージが、運用者に原因と対処を伝えている（必要なら [troubleshooting.md](troubleshooting.md) に追記）
- [ ] 画面の意味が変わったときに止まり、構造の軽微な変更は吸収することを、ブラウザスクリプトのテストで示した

## この文書を更新するとき

- ジョブのモジュールの構成・登録の手順・品質ゲートの規則が変わったとき
