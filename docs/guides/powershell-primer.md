# このプロジェクトの PowerShell 入門

このプロジェクトのコードを読むために必要な PowerShell の書き方を、**実際に使っている形**に絞って説明します。PowerShell の一般的な入門書の代わりではありません。Windows PowerShell 5.1 で動かすための制約（使ってはいけない構文など）は [powershell-compatibility.md](powershell-compatibility.md) にまとめてあり、ここでは繰り返しません。

## 1. ファイルの種類とモジュールの組み立て

| 拡張子 | 役割 | このプロジェクトでの例 |
|---|---|---|
| `.ps1` | スクリプト。関数の定義を置く | `app/modules/*/Private/*.ps1`、`app/invoke-job.ps1` |
| `.psm1` | モジュール。読み込むファイルの一覧と、公開する関数を決める | `app/modules/JobKit/JobKit.psm1` |
| `.psd1` | データファイル。`@{ … }` の値だけを書く（コードは実行されない） | `app/config/settings.psd1`、`PageOperations.psd1` |

モジュール（`.psm1`）はどれも同じ形です。

```powershell
Set-StrictMode -Version 1.0          # 未定義の変数を読むとエラーにする
$ErrorActionPreference = 'Stop'      # コマンドのエラーを例外として扱う（後続を実行しない）

Import-Module -Name (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1') -DisableNameChecking

foreach ($relativePath in @('Private/Settings.ps1', 'Private/Flow.ps1', 'Public/Invoke-PlotRosterExportJob.ps1')) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "… の構成ファイルが見つかりません: $path" }
    . $path                          # ドットソース: ファイルの関数をこのモジュールの中に定義する
}

Export-ModuleMember -Function @('Invoke-PlotRosterExportJob')   # 外から呼べるのはこれだけ
```

- `$PSScriptRoot` は、そのファイルがあるフォルダーです。
- `Public/` の関数だけを `Export-ModuleMember` で公開し、`Private/` の関数はモジュールの中でだけ使います（テストで検査）。
- `.psd1` は `Import-PowerShellDataFile` で読みます。`$true` / `$false`、文字列、数値、`@( … )`（配列）、`@{ … }`（hashtable）だけが書けます。

## 2. 関数とパラメーター

```powershell
function Get-RosterExportFileName {
    <#
    .SYNOPSIS
    1行の説明（公開関数には必須。テストで検査）
    #>
    param(
        [Parameter(Mandatory)][string]$Template,     # 必須。型は string
        [Parameter(Mandatory)][datetime]$Date
    )
    …
}

Get-RosterExportFileName -Template 'plot_roster_{0}.csv' -Date $now   # 呼び出しは「-名前 値」
```

| 書き方 | 意味 |
|---|---|
| `[Parameter(Mandatory)]` | 必須。渡さないとエラー。**空文字・空配列も拒否する** |
| `[AllowEmptyString()]` / `[AllowEmptyCollection()]` / `[AllowNull()]` | 必須のまま、空文字・空配列・`$null` を受け付ける |
| `[ValidateSet('On', 'Off', 'Error')]` | 決まった値だけを受け付ける |
| `[int]$TimeoutSeconds = 0` | 型と既定値（省略できるパラメーター） |
| `[CmdletBinding()]` | 高度な関数にする。**知らないパラメーター名を渡すとエラーになる**（このプロジェクトではポートの誤記を見つけるために使う。4章） |

パラメーター名は省略せずに書きます（`-Temp` のような前方一致は使わない）。

## 3. 値の入れ物

| 書き方 | 種類 | 使いどころ |
|---|---|---|
| `@{ Key = 'value' }` | hashtable | 設定（`.psd1` の中身）、ポートの形の宣言、上書き値 |
| `[ordered]@{ … }` | 順序付き hashtable | 列の順番を保ちたい記録 |
| `[pscustomobject]@{ Name = …; Path = … }` | オブジェクト | 関数の戻り値、記録、ポート（メンバーが scriptblock のオブジェクト） |
| `@( … )` | 配列 | 0個・1個でも必ず配列にしたいとき |
| `New-Object System.Collections.Generic.List[object]` | 伸びるリスト | ループで要素を足していくとき（`[void]$list.Add($x)`、最後に `.ToArray()`） |

hashtable は `$h['Key']` / `$h.Key`、オブジェクトは `$o.Key` で読みます。どちらが来るか分からない値（設定、ブラウザから返った JSON、ポートのメンバー）は、JobKit の `Get-PropertyValue -InputObject $x -Name 'Key' -Default …` で読みます。存在しないキーでも例外にならず、既定値を返します。

## 4. scriptblock とポート

`{ … }` は「あとで実行する処理」（scriptblock）です。`&` で実行します。

```powershell
$add = { param($A, $B) $A + $B }
& $add -A 1 -B 2          # 3
```

このプロジェクトの**ポート**は、「メンバーが scriptblock のオブジェクト」です。ジョブはファイル・時刻・ブラウザに、このメンバーを呼ぶことでだけ触れます。

```powershell
# 呼ぶ側（Flow）: メンバーを取り出して、名前付きの引数で呼ぶ
[void](& $Ports.Files.EnsureDirectory -Path $Settings.TempDirectory -Purpose '区画一覧の一時ダウンロード')
$now = & $Ports.Clock.Now

# 作る側（JobHost のサービスやページポート）: [CmdletBinding()] 付きの param を宣言する
UseDownloadDirectory = { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) & $Browser.SetDownloadDirectory -Path $Path }.GetNewClosure()
```

- メンバーに `[CmdletBinding()]` があるので、`-Pth` のような綴り違いは「そのパラメーターは無い」というエラーになります（黙って無視されない）。
- 形（メンバー名と必須のパラメーター名）は `Assert-PortShape` で検証します（[JobKit.md](../modules/JobKit.md#ポートの形)）。テストの偽物（`New-ScriptedPort`）も同じ検証を通ります。

### `GetNewClosure()` — 変数を閉じ込める

scriptblock は、普通は**実行したときの**変数を見ます。`.GetNewClosure()` を付けると、**作ったときの**変数の値を閉じ込めます。サービスやページポートは、作ったときの `$Browser` や `$state` を覚えておく必要があるので付けます。

閉じ込めた scriptblock からは、モジュールの非公開関数が見えなくなります。そのため JobHost のサービスは、使う関数を `Get-Command` で先に取り出して変数に入れ、それを閉じ込めています。

```powershell
$connect = Get-Command -Name Connect-HostBrowser -CommandType Function
Connect = { [CmdletBinding()] param() & $connect -State $state }.GetNewClosure()
```

逆に、関数の中の変数や非公開関数をそのまま使わせたい callback（`Lists.Traverse` に渡す `-Visit` など）には付けません（[PlantingRecordExport の Flow.ps1](../../app/modules/PlantingRecordExport/Private/Flow.ps1) のコメント参照）。

## 5. 戻り値とパイプライン

PowerShell では、関数の中で**捨てなかった値はすべて戻り値**になります。`return` は「ここで終わる」だけです。

```powershell
function New-Something {
    $list.Add('x')          # Add の戻り値（番号）が出力に混ざる
    [void]$list.Add('x')    # 捨てる
    return $result
}
```

- 戻り値を使わない呼び出しには `[void]` を付けます。付け忘れると、ジョブの結果が2つになり `Assert-JobResult` が失敗します（[ARCHITECTURE.md](../../ARCHITECTURE.md#5-ジョブ結果の約束)）。
- **配列の展開**: 関数が配列を返すと、パイプラインで要素に分かれます。要素が1つなら要素そのもの、0個なら `$null` になります。配列として受けたい側は `@( … )` で包みます（`$rows = @(& $page.ReadVisibleRows)`）。
- 配列を1つの値として返したいときは `return , $array`（カンマ演算子）と書きます（JobChains の `Get-PlantingExportArtifacts` など）。

## 6. エラーの扱い

| 書き方 | 意味 |
|---|---|
| `throw "メッセージ"` | 例外を投げる。ジョブの失敗はすべて例外で表す（結果に `Ok = $false` は入れない） |
| `try { … } catch { … }` | 例外を受け止める。`$_` が例外の記録、`$_.Exception.Message` がメッセージ |
| `try { … } finally { … }` | 成功・失敗にかかわらず後始末をする（区画詳細を閉じる、ブラウザ接続を閉じる） |
| `throw` だけ（catch の中） | 受け止めた例外をそのまま投げ直す |

ブラウザとの境界の例外には、分類（`Exception.Data['pagebridge.category']`）が付いています。区画ごとの処理で「続けてよい失敗か」を判断するときは、Browser サービスの `IsFatal` を使います（[PageBridge.md](../modules/PageBridge.md#エラーの分類)）。

## 7. スコープ — `$script:`

`$script:名前` は、そのモジュールの中で共有する変数です。このプロジェクトでは、**変わらない宣言**（ポートの形、列の順番、日付の形式の一覧）にだけ使います。

```powershell
$script:CsvErrorColumns = @('PlotCode', 'Owner', 'Status', …)
$script:PlotRosterServiceShapes = @{ Clock = @{ Now = @() } }
```

途中の状態（ループの変数、判定結果）を `$script:` に置くことはしません。状態は関数の引数と戻り値で受け渡します。

## 8. 文字列・比較・正規表現

| 書き方 | 意味 |
|---|---|
| `"区画: $plotCode"` | 二重引用符は変数を展開する |
| `'固定の文字列'` | 一重引用符は展開しない |
| `"件数: $($rows.Count)"` | `$( … )` で式を埋め込む |
| `'{0}_{1}{2}' -f $a, $b, $c` | 書式指定 |
| `` ` ``（行末のバッククォート） | 次の行に続ける（長い呼び出しを改行するとき） |
| `-eq` `-ne` `-lt` `-ge` | 比較。**文字列は大文字小文字を区別しない** |
| `-ceq` `-cne` `-ccontains` `-cnotcontains` | 大文字小文字を区別する比較（見出しの完全一致など） |
| `-like 'planting_*'` | ワイルドカード一致 |
| `-match` / `[regex]::Match($text, $pattern)` | 正規表現。このプロジェクトでは結果を変数で受け取れる `[regex]::Match` を主に使う |

## 9. Pester（テスト）の読み方

```powershell
BeforeAll {                                  # このファイルのテストの前に1回だけ実行
    Import-Module (Join-Path $PSScriptRoot '../../support/TestSupport.psm1') -Force
    Import-Module (Get-RepositoryPath 'app/modules/PlotRosterExport/PlotRosterExport.psm1') -Force
}

Describe 'Get-RosterExportFileName' {        # テストのまとまり
    It 'inserts the month and day of the run date' {        # テスト1件（何をするとどうなるか）
        InModuleScope PlotRosterExport {     # モジュールの非公開関数を呼べる場所で実行する
            Get-RosterExportFileName -Template 'plot_roster_{0}.csv' -Date ([datetime]'2026-04-05') |
                Should -Be 'plot_roster_0405.csv'
        }
    }
}
```

| 書き方 | 意味 |
|---|---|
| `Should -Be` / `-BeTrue` / `-BeNullOrEmpty` / `-Contain` / `-Match` | 期待値の確認 |
| `{ … } \| Should -Throw '*メッセージの一部*'` | 例外になることの確認（`*` はワイルドカード） |
| `It '… <Decision> …' -TestCases @( @{ Decision = 'On'; … }, … )` | 同じテストを値を変えて繰り返す。`<名前>` はテスト名に値を埋め込む |
| `InModuleScope 名前 -Parameters @{ X = $x } { param($X) … }` | テスト側の変数をモジュールの中へ渡す |
| `$TestDrive` | テストごとの一時フォルダー（終わると消える） |

偽のポートは `New-ScriptedPort` で作り、呼び出しの順番を `Get-PortCalls` で確かめます（[testing.md](testing.md#3-テスト補助)）。

## 10. ジョブのコードを読む順番

1. `Public/Invoke-<Job>Job.ps1` — 設定を読み、ポートを作り、Flow を呼んで結果を返す（10〜30行）。
2. `Private/Ports.ps1` — このジョブが外の世界のどれを使うか（形の宣言を見れば全部分かる）。
3. `Private/Flow*.ps1` — 処理の順序と止まる条件。`& $Ports.…` の行が外の世界との境目です。
4. `Private/Policy.ps1` などの純粋関数 — 判定・命名の規則。
5. `Private/Page.ps1` と `PageOperations.psd1` — 画面操作の業務名と、ページスクリプトのメソッドの対応。

実行の全体を順に追うときは [code-walkthrough.md](code-walkthrough.md) を参照してください。

## この文書を更新するとき

- このプロジェクトで新しい書き方（構文・モジュールの組み立て方・テストの書き方）を使い始めたとき
- ポートの作り方・呼び方の約束が変わったとき
