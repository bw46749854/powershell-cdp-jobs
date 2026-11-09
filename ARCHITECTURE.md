# アーキテクチャ

この文書は、コードを読む・直す人のための全体像です。個々のファイルの説明は [docs/modules](docs/modules) と [docs/jobs](docs/jobs) に、実行の流れを関数の順に追った説明は [docs/guides/code-walkthrough.md](docs/guides/code-walkthrough.md) に、設計の判断基準は [docs/guides/design-principles.md](docs/guides/design-principles.md) にあります。
ここに書いた境界のうち機械的に確かめられるものは、[tests/pester/Quality](tests/pester/Quality) のテストで固定しています。境界を変えるときは、先にこの文書と [docs/decisions](docs/decisions) を更新し、テストの規則を同時に直してください。

## 1. 構成要素と依存の向き

```text
                      app/invoke-job.ps1（入口）
                               │
                               ▼
  ┌──────────────────────── JobHost ─────────────────────────┐
  │ 設定・ジョブ定義の読み込み / Context とサービスの組み立て   │
  │ ジョブの呼び出し / 結果の検証 / 後始末                     │
  └──────┬───────────────────────────────┬────────────────────┘
         │ Context（サービス = ポート）   │ Browser サービスの実装
         ▼                               ▼
  ┌── ジョブのモジュール ───┐      ┌──── PageBridge ─────┐        ┌── app/browser ──┐
  │ PlotRosterExport         │      │ CDP 通信 / タブ選択  │  注入  │ pagekit（核）   │
  │ SoilAnalysisTargetSync   │      │ 操作カタログ / 契約  │ ─────▶ │ 画面の部品      │
  │ PlantingRecordExport     │      └──────────┬───────────┘        │ 機能の部品      │
  │ LastMonthPlantingDigest  │                 │                    └─────────────────┘
  │ JobChains（連携）        │                 │
  └──────────┬───────────────┘                 │
             ▼                                 ▼
  ┌──────────────────────────── JobKit ────────────────────────────┐
  │ ポートの形の検証 / ジョブ結果の約束 / 設定値の読み方（I/O なし）│
  └────────────────────────────────────────────────────────────────┘
```

| モジュール | 依存してよい先 | 役割 |
|---|---|---|
| `JobKit` | なし | すべてのモジュールが共有する純粋な約束事（ポートの形、ジョブ結果、設定値の型チェック） |
| `PageBridge` | `JobKit` | ブラウザとの通信、操作するタブの選択、ページスクリプトの注入と呼び出し、契約結果の判定 |
| `JobHost` | `JobKit`, `PageBridge` | 実行基盤。設定・ジョブ定義を読み、サービスを組み立ててジョブを呼ぶ |
| ジョブのモジュール | `JobKit` だけ | 業務の手順と判断。外の世界にはポートからしか触れない |
| `JobChains` | `JobKit` だけ | 既存のジョブを順に呼び、成果物を受け渡す |

依存は上から下への一方向です。ジョブのモジュールは `JobHost` も `PageBridge` も読み込みません。ジョブ同士も直接は呼びません（連携ジョブは `Jobs` サービスを通して呼ぶ）。
`PageBridge`・`JobHost`・`JobKit` は特定のジョブの名前を一切知りません。ジョブ固有の知識は、ジョブのモジュール・操作カタログ・ページスクリプトにだけあります。

## 2. ジョブが動くまで

```text
週次_土壌分析対象の整合.bat
  └ powershell -File app\invoke-job.ps1 -JobName WeeklySoilAnalysisSync
      └ Invoke-HostedJob（JobHost）
          1. app/config/settings.psd1 を読む（パスはプロジェクトのルート基準の絶対パスにする）
          2. app/config/jobs.psd1 を読み、ジョブの Module / Command / Browser を検証する
          3. Context を組み立てる（Settings = Jobs.<ジョブ名> のコピー、Services = ポート群）
          4. ジョブのモジュールを読み込み、Command に Context を渡して呼ぶ
          5. 戻り値が結果プロトコルどおりか検証する（Assert-JobResult）
          6. 成功・失敗にかかわらずブラウザ接続を閉じる
```

失敗は例外で呼び出し元へ伝わり、`invoke-job.ps1` は終了コード 1 で終わります（.bat は失敗を表示して一時停止します）。

## 3. Context とサービス（ポート）

ジョブコマンドが受け取るのは `Context` だけです。ジョブが使ってよいものの全量がここにあります。

| 項目 | 内容 |
|---|---|
| `JobName` / `RunId` | ジョブ名、実行 ID（`yyyyMMdd_HHmmss_fff`、ログの識別に使う） |
| `AppRoot` / `ProjectRoot` / `SettingsPath` / `CatalogPath` | パス |
| `Entry` | ジョブ定義（jobs.psd1 の解決済みエントリ） |
| `Settings` | `Jobs.<ジョブ名>` のコピー（連携ジョブからの上書き値を適用済み） |
| `Common` | 共通設定 |
| `Services` | 下表のサービス |

| サービス | メンバー（パラメーター） | 実装 |
|---|---|---|
| `Log` | `Info`/`Warn`/`Error`(Message)、`Section`(Title)、`Data`(Label, Data) | [HostLog.ps1](app/modules/JobHost/Private/HostLog.ps1) |
| `Clock` | `Now`、`Sleep`(Milliseconds) | [HostClock.ps1](app/modules/JobHost/Private/HostClock.ps1) |
| `Files` | `EnsureDirectory`、`ClearDirectory`、`RemoveFile`、`ListFiles`、`Exists`、`ReadBytes`、`ReadText`、`SaveCsv`、`MoveToUnique` | [FileService.ps1](app/modules/JobHost/Private/FileService.ps1) |
| `Downloads` | `WaitForFile`(Directory, Filter, NamePattern, TimeoutSeconds, StableSeconds, RejectEmpty) | [DownloadWatcher.ps1](app/modules/JobHost/Private/DownloadWatcher.ps1) |
| `Lists` | `Traverse`(ExpectedCount, ReadVisible, KeyOf, Visit, ScrollNext, MaxLoops, StallLimit, EmptyMessage) | [ListTraversal.ps1](app/modules/JobHost/Private/ListTraversal.ps1) |
| `Jobs` | `Run`(JobName, Overrides)、`GetSettings`(JobName) | [ChildJobs.ps1](app/modules/JobHost/Private/ChildJobs.ps1) |
| `Browser` | `Connect`、`SetDownloadDirectory`、`Inject`、`Invoke`/`WaitUntil`/`WaitFor`/`Assert`(Operation, …)、`IsFatal`、`Close` | [BrowserService.ps1](app/modules/JobHost/Private/BrowserService.ps1)（ブラウザを使わないジョブでは `$null`） |

ポートは「メンバー名 → 必須のパラメーター名」の形で宣言し、`Assert-PortShape`（JobKit）で検証します。テスト用の偽物も同じ検証を通すため、偽物と本物の形がずれると即座に失敗します。メンバーは `[CmdletBinding()]` 付きの scriptblock なので、パラメーター名の綴り違いも実行時エラーになります。

## 4. ジョブのモジュールの中身

ジョブのモジュールは、どれも同じ役割分担のファイルで構成します。

| ファイル | 役割 | Context に触れるか |
|---|---|---|
| `Public/Invoke-<Job>Job.ps1` | ジョブコマンド。設定を読み、ポートを組み立て、Flow を呼び、結果を返す | 触れる |
| `Private/Ports.ps1` | 合成ルート。Context のサービスから、このジョブが使うポートだけを組み立てて形を検証する | 触れる（ここだけ） |
| `Private/Settings.ps1` | `Jobs.<Job>` の値を、ジョブ開始時にまとめて型付きで読む | 触れない |
| `Private/Page.ps1` | ページポート。操作カタログの操作を、業務の名前（`AssertExportScreen` など）で包む | 触れない |
| `Private/Flow*.ps1` | 処理の順序だけを書く。具体的な I/O はポートの向こう側 | 触れない |
| `Private/Policy.ps1` など | 判定ルール・名前の規則などの純粋関数 | 触れない |
| `PageOperations.psd1` | 操作カタログ（PowerShell の操作名 → ページヘルパーのメソッド） | — |

Flow と純粋関数はファイル・時刻・画面出力のコマンド（`Get-ChildItem`、`Get-Date`、`Write-Host` など）を直接使いません。時刻は `Clock.Now`、待機は `Clock.Sleep`、ファイルは `Files` を通します。これにより、偽の時計と偽のファイル操作で全経路をテストできます。

## 5. ジョブ結果の約束

ジョブコマンドは `New-JobResult` で作った結果を**ちょうど1つ**返します。

```text
Job      ジョブ名
Ok       常に $true（失敗は結果ではなく例外で表す）
Outputs  後続のジョブが使う成果物（パスなど）
Summary  件数などの記録
```

実行基盤は `Assert-JobResult` で、出力が1つであること・ジョブ名が一致すること・`Ok` が `$true` であることを確かめます。パイプラインへの出力漏れ（`[void]` の付け忘れ）は「結果が2つ」として検出されます。連携ジョブは子ジョブの `Outputs` だけを読みます。→ [docs/decisions/0003-job-result-protocol.md](docs/decisions/0003-job-result-protocol.md)

## 6. ブラウザとの境界

```text
Flow ──業務の名前──▶ Page ポート ──操作名──▶ Browser サービス ──▶ PageBridge
                                                        │
          操作カタログ（PageOperations.psd1）: 操作名 → Method / Kind / Scope
                                                        │ Runtime.evaluate
                                                        ▼
                         window.__pagekit.helpers.<helper>.<method>(...)
```

- **操作カタログ** は、PowerShell 側の操作名とページヘルパーのメソッドの対応表です。操作の種類（`Kind`）が、許される呼び出し方とヘルパーが無いときの扱いを決めます。

  | Kind | 用途 | 呼び出し | ヘルパーが無いとき |
  |---|---|---|---|
  | `Identity` | タブの画面識別 | Invoke | 契約失敗の結果 |
  | `Contract` | 画面の契約の検証 | Assert | 契約失敗の結果 |
  | `Action` | クリック・スクロールなど | Invoke | 例外（続行不能） |
  | `Query` | 一覧・件数などの読み取り | Invoke / WaitFor | 例外（0件と区別するため） |
  | `Probe` | 待機の条件（真偽値） | WaitUntil | `false`（待ち続ける） |
  | `Cleanup` | 後始末（閉じるなど） | Invoke | warning の結果（finally を壊さない） |

- **ページスクリプト**（[app/browser](app/browser)）は、ジョブごとに jobs.psd1 の `Browser.Scripts` の順で連結し、1回の評価で注入します。注入の最後に、ヘルパーが持つメソッドの一覧を返させ（`__pagekit.ack`）、カタログのメソッドが揃っているかを PowerShell 側で確かめます。
- **タブの選択**: ブラウザのタブ一覧から業務画面になり得るものだけを残し、各タブで画面識別（Kind=Identity）を実行します。一致したタブがちょうど1つのときだけ接続し、0個・2個以上なら停止します。

## 7. DOM を契約とみなす

ページスクリプトは画面の DOM を「契約」として読みます。

| 区分 | 例 | 扱い |
|---|---|---|
| **意味**（契約） | 製品名、メニュー・ボタン・タブの名前、列見出しの文言、`aria-selected` などの状態、`data-*` の目印、件数表示 | 厳格に確かめる。ちょうど1つに決まらなければ止まる |
| **構造**（実装の都合） | タグの種類、CSS クラス、ラッパー要素の有無、列の並び順、固定列と通常列のどちらにあるか | 吸収する。位置ではなく意味から辿る |

意味の変更（例: 別のグループが選ばれている、ボタンの名前が変わった）を吸収しようとすると、取り違えたまま操作を続ける危険があります。そのため推測はせず、どの条件を満たしていないかをログに残して止まります。
各スクリプトの冒頭コメントに「契約（意味）」と「吸収する構造の違い」を書き、画面ごとの一覧を [docs/browser/page-contracts.md](docs/browser/page-contracts.md) にまとめています。→ [docs/decisions/0001-dom-as-contract.md](docs/decisions/0001-dom-as-contract.md)

契約の検証結果は次の形で返り、PowerShell 側（[ContractResult.ps1](app/modules/PageBridge/Private/ContractResult.ps1)）が判定します。

```text
{ scope, ok, fatalCount, warningCount, checks: [{ name, ok, severity: fatal|warning, message, details }], details }
```

## 8. エラーの分類と止め方

ブラウザ境界の例外には分類（`Exception.Data['pagebridge.category']`）を付けます。

| 分類 | 意味 | 行単位の処理を続けるか |
|---|---|---|
| `session-lost` / `timeout` / `helper-missing` / `protocol` | ブラウザとの通信を続けられない | 続けない（即停止） |
| `contract` | 画面が契約を満たさない | 操作の手前で停止 |
| `wait-timeout` | 待機の条件が期限内に成り立たない | 呼び出し側が判断 |
| `javascript` / `command` | ページ内の例外・CDP コマンドの失敗 | 呼び出し側が判断 |
| `browser-unreachable` / `configuration` | ブラウザに接続できない・設定やカタログの誤り | 開始前に停止 |

区画単位の処理（チェックの整合、作付け記録の保存）は、1区画の失敗を記録して次へ進みます。最後に件数と失敗を確かめ、食い違いや失敗が1件でもあれば異常終了します。

通信を続けられない分類のエラーの扱いは、ジョブによって違います。

- **チェックの整合（SoilAnalysisTargetSync）**: 区画ごとに `IsFatal` で判定し、その場で走査を止めます。失敗一覧は出力してから止まります。
- **作付け記録の保存（PlantingRecordExport）**: 区画ごとには判定せず、失敗として記録して次へ進みます。表示中の残りの区画も失敗になったあと、一覧を読み直すところで例外になって止まります（失敗一覧は出力されません）。

## 9. 連携ジョブ

`JobChains` は子ジョブを `Jobs.Run` で呼びます。子ジョブは単独実行と同じ入口（`Invoke-HostedJob`）を通り、**親と同じ設定ファイル・ジョブ定義**で動きます（`Jobs` サービスはパスを受け取る口を持たない）。受け渡すのは成果物のパスだけで、連携ジョブは CSV の中身を読みません。→ [docs/decisions/0005-child-jobs-share-settings.md](docs/decisions/0005-child-jobs-share-settings.md)

## 10. 実行環境の前提

- 本番は Windows PowerShell 5.1。PowerShell 7 専用の構文・パラメーター・.NET API は使いません（テストで検査）。→ [docs/decisions/0006-windows-powershell-5-1.md](docs/decisions/0006-windows-powershell-5-1.md)
- PowerShell のソースは UTF-8（BOM 付き）、バッチファイルは ASCII・CRLF。→ [docs/guides/powershell-compatibility.md](docs/guides/powershell-compatibility.md)
- ブラウザとの通信は localhost だけで、プロキシを使いません。

## 11. テストの層

| 層 | 場所 | 確かめること |
|---|---|---|
| 単体 | `tests/pester/<モジュール>` | 純粋関数、ポートを偽物にした Flow、実行基盤のサービス |
| ブラウザスクリプト | `tests/js` | jsdom 上で、契約の判定と、構造の違いを吸収できること |
| 品質ゲート | `tests/pester/Quality` | 依存の向き・ポート経由の I/O・5.1 互換・同梱設定・文字コード・文書の網羅 |
| E2E | `tests/e2e` | 実ブラウザとモック画面で、連携ジョブを入口から通しで動かす |

詳しくは [docs/guides/testing.md](docs/guides/testing.md) を参照してください。
