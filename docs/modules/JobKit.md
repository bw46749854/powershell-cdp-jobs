# JobKit — 共有の約束事

すべてのモジュールが依存してよい唯一の共有モジュールです。I/O・時刻・ブラウザには一切触れず、「形」と「約束」だけを持ちます。どこからでも使えるため、ここに業務の知識やジョブ固有の名前を入れてはいけません（テストで検査）。

## 公開関数

| 関数 | ファイル | 内容 |
|---|---|---|
| `Test-PropertyPresent -InputObject -Name` | [Values.ps1](../../app/modules/JobKit/Public/Values.ps1) | hashtable のキー / オブジェクトのプロパティがあるか |
| `Get-PropertyValue -InputObject -Name [-Default]` | 同上 | 値を読む。無ければ `Default`。hashtable と PSCustomObject を同じように扱う |
| `Get-PortMember -Port -PortName -Member` | [Ports.ps1](../../app/modules/JobKit/Public/Ports.ps1) | ポートのメンバー（scriptblock）を取り出す。無ければ分かりやすい例外 |
| `Get-ScriptBlockParameterNames -ScriptBlock` | 同上 | scriptblock が宣言しているパラメーター名 |
| `Assert-PortShape -Port -PortName -Members` | 同上 | ポートの形の検証（下記） |
| `New-JobResult -Job [-Outputs] [-Summary]` | [JobResults.ps1](../../app/modules/JobKit/Public/JobResults.ps1) | ジョブの成功結果を作る |
| `Assert-JobResult -Output -Job` | 同上 | ジョブコマンドの出力が結果の約束どおりか検証し、結果を返す |
| `Read-JobSetting -Settings -Name -Kind -Scope [-Minimum]` | [Settings.ps1](../../app/modules/JobKit/Public/Settings.ps1) | 設定値を1つ、種類を検証して読む |
| `Invoke-LoggedStep -Log -Message -Action` | [Steps.ps1](../../app/modules/JobKit/Public/Steps.ps1) | 手順のログを出してから `Action` を実行し、その戻り値を返す |

## ポートの形

ポートは「メンバー名 → 必須のパラメーター名の配列」で宣言します。

```powershell
$script:PlotRosterServiceShapes = @{
    Files = @{ EnsureDirectory = @('Path', 'Purpose'); ClearDirectory = @('Path', 'Purpose') }
}
Assert-PortShape -Port $ports.Files -PortName 'Files' -Members $script:PlotRosterServiceShapes.Files
```

`Assert-PortShape` は、ポートが `$null` でないこと、各メンバーが scriptblock であること、宣言したパラメーター名をすべて持つことを確かめます。メンバーが余分にあるのは構いません（必要なものだけを宣言する）。本物のサービスもテストの偽物も同じ検証を通すため、形がずれると実行前に失敗します。

## ジョブ結果

```text
Job      : ジョブ名（Assert-JobResult の -Job と一致すること）
Ok       : $true（失敗は例外で表す。$false の結果は約束違反）
Outputs  : 後続のジョブが使う成果物（PSCustomObject）
Summary  : 件数などの記録（PSCustomObject）
```

`Assert-JobResult` は `$null` を除いた出力がちょうど1つであることを要求します。`[void]` の付け忘れでパイプラインに値が漏れると、ここで検出されます。→ [decisions/0003-job-result-protocol.md](../decisions/0003-job-result-protocol.md)

## 設定値の種類（`Read-JobSetting -Kind`）

| Kind | 受け付ける値 |
|---|---|
| `Text` | 空白だけでない文字列 |
| `Integer` | 整数（`-Minimum` 以上） |
| `Pattern` | 正規表現として解釈できる、空白だけでない文字列 |
| `TextList` | 空白だけでない文字列の配列（1件以上。単独の文字列は不可）。戻り値は `@()` で受ける |
| `Flag` | `$true` / `$false` |

メッセージは `設定 <Scope>.<Name> は…` の形で、どの値を直せばよいかが分かるようにしています。空の配列が `$null` に化けないよう、値は関数を経由せず直接読んでいます。

## 使われ方と変更の影響

JobKit はすべてのモジュールから使われるため、振る舞いを変えると全体に効きます。

| 関数 | 主に使う場所 | 変えたときの影響 |
|---|---|---|
| `Assert-PortShape` / `Get-PortMember` | 各ジョブの `Ports.ps1`、JobHost のサービス、PageBridge のトランスポート | 本物と偽物の両方の検証が変わる。緩めると形のずれを見逃す |
| `Read-JobSetting` | 各ジョブの `Settings.ps1`、JobHost の Browser / Logging 設定 | 設定の誤りが開始時に見つかるかどうか |
| `New-JobResult` / `Assert-JobResult` | 各ジョブコマンド、JobHost、JobChains | 連携ジョブが子ジョブの結果を信頼できるかどうか |
| `Get-PropertyValue` | ほぼすべて | hashtable と PSCustomObject を同じように読む前提が崩れる |

ここに業務の知識・ジョブ固有の名前・I/O を持ち込まないこと（テストで検査）。足したくなったら、その機能はジョブのモジュールか JobHost のサービスに置くべきものです（[design-principles.md](../guides/design-principles.md)）。

## ファイル構成

| ファイル | 役割 |
|---|---|
| [JobKit.psm1](../../app/modules/JobKit/JobKit.psm1) | 読み込むファイルの一覧と公開関数 |
| [Public/Values.ps1](../../app/modules/JobKit/Public/Values.ps1) | hashtable / オブジェクトの値の読み方 |
| [Public/Ports.ps1](../../app/modules/JobKit/Public/Ports.ps1) | ポートの形の検証 |
| [Public/JobResults.ps1](../../app/modules/JobKit/Public/JobResults.ps1) | ジョブ結果の約束 |
| [Public/Settings.ps1](../../app/modules/JobKit/Public/Settings.ps1) | 設定値の型付きの読み方 |
| [Public/Steps.ps1](../../app/modules/JobKit/Public/Steps.ps1) | 手順のログ付き実行 |

テスト: [tests/pester/JobKit/JobKit.Tests.ps1](../../tests/pester/JobKit/JobKit.Tests.ps1)

## この文書を更新するとき

- 公開関数・ポートの形の規則・ジョブ結果の約束・設定値の種類が変わったとき
