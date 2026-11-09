# Windows PowerShell 5.1 で動かすための約束

本番の実行環境は Windows に標準で入っている Windows PowerShell 5.1（.NET Framework）です。開発やテストは PowerShell 7 で行うこともあるため、7 でしか動かない書き方が紛れ込まないように次の約束を守ります。多くはテスト（[PowerShellCompatibility.Tests.ps1](../../tests/pester/Quality/PowerShellCompatibility.Tests.ps1)、[SourceHygiene.Tests.ps1](../../tests/pester/Quality/SourceHygiene.Tests.ps1)）で検査しています。

## 1. 文字コードと改行

| ファイル | 文字コード | 改行 | 理由 |
|---|---|---|---|
| `*.ps1` / `*.psm1` / `*.psd1` | UTF-8（BOM 付き） | LF | 5.1 は BOM の無い UTF-8 を ANSI（日本語環境では CP932）として読み、日本語の文字列が化ける |
| `*.bat` | ASCII だけ | CRLF | cmd.exe は OEM コードページで読み、LF だけの改行でラベルの解釈を誤ることがある。日本語はファイル名だけに使う |
| その他（md / js / css / html / json） | UTF-8（BOM なし） | LF | |

`.editorconfig` と `.gitattributes` に同じ規則を書いてあります。崩れたときは次で直します。

```bash
pwsh -File tools/Repair-SourceEncoding.ps1          # 直す
pwsh -File tools/Repair-SourceEncoding.ps1 -Check   # 確かめるだけ（違反があれば終了コード 1）
```

## 2. 使わない構文・コマンド

| 使わないもの | 5.1 での代わり |
|---|---|
| 三項演算子 `a ? b : c` | `if (a) { b } else { c }` |
| `??` / `??=` / `?.` / `?[]` | `if ($null -eq $x) { … }` |
| `&&` / `\|\|`（パイプラインの連結） | `if ($LASTEXITCODE -eq 0) { … }` または例外 |
| `ForEach-Object -Parallel` | 使わない |
| `ConvertFrom-Json -AsHashtable` | `PSCustomObject` のまま `Get-PropertyValue`（JobKit）で読む |
| `Get-Content -AsByteStream` | `[System.IO.File]::ReadAllBytes()` |
| `Join-Path a b c`（3つ以上） | `Join-Path (Join-Path a b) c` |
| `-Encoding utf8NoBOM` / `utf8BOM` | `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding -ArgumentList $true))` |
| `$IsWindows` / `$IsLinux` | `[System.IO.Path]::DirectorySeparatorChar -eq '\'` など（StrictMode では未定義の変数を読むとエラーになる） |
| `[System.IO.Path]::GetRelativePath()` などの .NET Core の API | 自前の関数（JobHost の `SafePaths.ps1` など） |
| 文字列中の `` `u{3000} `` などの Unicode エスケープ（6 以降） | `[char]0x3000` を連結する（5.1 では `` `u `` はただの `u` になり、エラーにならずに別の文字列になる） |

## 3. 気をつける振る舞い

- **`Set-Content -Encoding UTF8`** は 5.1 では BOM 付き、7 では BOM なしで書きます。出力ファイルの文字コードを決めたいときは .NET の `WriteAllText` を使います（JobHost の `Files.SaveCsv` は常に BOM 付き UTF-8）。
- **配列の展開**: 関数から要素1つの配列を返すと、呼び出し側では要素そのものになります。配列を期待する側は `@(…)` で受けます。空の配列を「値」として返したいときは `, $array` を使います。
- **`GetNewClosure()`** で作った scriptblock からは、モジュールの非公開関数が見えません。必要な関数は `Get-Command` で取り出した CommandInfo を変数に入れて閉じ込めます（JobHost のサービスの作り方）。逆に、関数の中の変数と非公開関数をそのまま使わせたい callback（`Lists.Traverse` の `-Visit` など）には `GetNewClosure()` を付けません。
- **パラメーター名の前方一致**: `-Arg` のような省略は、後でパラメーターが増えたときに曖昧になります。パラメーター名は省略せずに書きます。
- **`Set-StrictMode -Version 1.0`**: すべてのモジュールで有効です。未定義の変数を読むとエラーになります。
- **HttpClient / WebSocket とプロキシ**: 社内プロキシの設定があると、localhost のデバッグ用ポートへの通信までプロキシへ送られることがあります。PageBridge はプロキシを明示的に無効にしています。
- **`Mandatory` と空の値**: `[Parameter(Mandatory)]` の文字列・配列は空を受け付けません。空を許すときは `[AllowEmptyString()]` / `[AllowEmptyCollection()]` を付けます。

次の書き方は**構文としては正しく、PowerShell 7 ではエラーにも結果の違いにもならない**ため気づけません。5.1 で実行して初めて結果が変わります。最初の3つと、2章の `` `u{…} `` は PowerShellCompatibility のテスト（「avoids constructs whose result silently differs on Windows PowerShell 5.1」）で書き方を検査しています。それでも、書いたら Windows PowerShell 5.1 でテストを実行してください。

- **`ConvertFrom-Json` と JSON の配列**: 5.1 では、JSON の配列を「配列1つ」として出力します。`@(ConvertFrom-Json -InputObject $text)` は、要素がいくつあっても**要素1つ（中身は配列）**になります。要素ごとに扱うときは `@(ConvertFrom-Json -InputObject $text | ForEach-Object { $_ })` と書きます（7 でも同じ結果になります）。
- **`Get-Content` / `Set-Content` の既定の文字コード**: 5.1 で `-Encoding` を省くと ANSI（日本語環境では CP932）として読み書きします。BOM の無い UTF-8 のファイル（`.gitignore`、md、js など）を読むと日本語が化け、行の区切りまで崩れることがあります。`-Encoding UTF8` を付けるか、`[System.IO.File]::ReadAllText($path)`（既定が UTF-8）を使います。テストが検査するのは `Get-Content` の `-Encoding` の有無です。`Set-Content` で日本語を書くときも `-Encoding UTF8` を付けます。
- **`Get-ChildItem -LiteralPath … -Include …`**: 5.1 では、`-LiteralPath` と一緒に指定した `-Include` が効かず、すべてのファイルが返ることがあります。拡張子で絞るときは `Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }` を使います。
- **英語の Windows では気づけない違い**: 文字コードの問題は、ANSI が1バイト文字の環境（英語版 Windows、CI の既定）では表に出ないことがあります。本番と同じ日本語環境の 5.1 で確かめます。

## この文書を更新するとき

- 守るべき約束が増えた・不要になったとき（検査するテストも同時に直す）
