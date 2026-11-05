# テスト

## 1. 実行する

```bash
pwsh -File tools/Invoke-Tests.ps1                                  # Pester + ブラウザスクリプト（E2E を除く）
pwsh -File tools/Invoke-Tests.ps1 -Suite Pester -IncludeE2E        # E2E を含める
pwsh -File tools/Invoke-Tests.ps1 -Suite Pester -Path tests/pester/PlotRosterExport
pwsh -File tools/Invoke-Tests.ps1 -Suite Js                        # ブラウザスクリプトだけ（npm test と同じ）
pwsh -File tools/Invoke-Tests.ps1 -Suite Pester -Coverage          # tests/out/coverage.xml（JaCoCo）
```

Windows PowerShell 5.1 では `tools\run-tests.bat`（引数はそのまま渡る）を使います。本番と同じ 5.1 で通ることを、変更のたびに一度は確かめてください。

| 必要なもの | 用途 |
|---|---|
| Pester 5.7.1 | `tools/vendor/Pester` に同梱。無ければインストール済みの 5.5 以上を使う（[decisions/0007-vendored-test-tools.md](../decisions/0007-vendored-test-tools.md)） |
| Node.js 22 以上 + `npm install` | ブラウザスクリプトのテスト（jsdom） |
| Edge / Chrome / Chromium | E2E テスト。`E2E_BROWSER_PATH` で場所を指定できる。見つからなければ Skipped |

終了コードは、失敗が1件でもあれば 1 です。

## 2. テストの層

| 層 | 場所 | 確かめること | 速さ |
|---|---|---|---|
| 単体（PowerShell） | `tests/pester/<モジュール>` | 純粋関数の規則、ポートを偽物にした Flow の分岐・順序・止まり方、実行基盤のサービス | 速い |
| ブラウザスクリプト | `tests/js` | jsdom 上の DOM で、契約の判定（意味の違いで止まる）と、構造の違いを吸収できること | 速い |
| 品質ゲート | `tests/pester/Quality` | 設計の境界、Windows PowerShell 5.1 互換、同梱設定の妥当性、文字コード、文書の網羅 | 速い |
| E2E | `tests/e2e`（タグ `E2E`） | 実ブラウザ（ヘッドレス）とモック画面で、連携ジョブを入口から通しで動かす | 数分 |

単体テストでは、実時間を待たない時計（`New-ManualClock`）と偽のポートを使うため、タイムアウトや再試行の経路も一瞬で確かめられます。E2E テストは、ジョブの結果をジョブ自身の関数ではなく**テスト側で独立に計算した期待値**と比べます（同じ誤りを見逃さないため）。

### 品質ゲートの内容

| テスト | 確かめること |
|---|---|
| [Architecture.Tests.ps1](../../tests/pester/Quality/Architecture.Tests.ps1) | モジュールの依存の向き、モジュールのファイルがすべて読み込まれること、公開関数は Public にだけあること、ジョブのモジュールがポート以外で I/O・時刻・画面出力に触れないこと、Context に触れるのは合成ルートとジョブコマンドだけであること、PowerShell 側に DOM の探し方を書かないこと、操作カタログのメソッドがページスクリプトにあること、ページスクリプトが契約を冒頭に書いていること・外部へデータを送らないこと |
| [PowerShellCompatibility.Tests.ps1](../../tests/pester/Quality/PowerShellCompatibility.Tests.ps1) | すべての PowerShell ファイルが構文エラーなく読め、5.1 に無い構文・コマンド・パラメーター・.NET API を使っていないこと |
| [ShippedConfig.Tests.ps1](../../tests/pester/Quality/ShippedConfig.Tests.ps1) | 同梱の jobs.psd1 / settings.psd1 が各ジョブの検証を通り、読まれない設定が無いこと、ブラウザスクリプトのテストと注入順が一致すること、起動ファイルが定義済みのジョブだけを呼ぶこと |
| [SourceHygiene.Tests.ps1](../../tests/pester/Quality/SourceHygiene.Tests.ps1) | 文字コード・改行の規約（`tools/Repair-SourceEncoding.ps1 -Check`）、バッチファイルが ASCII と CRLF であること |
| [Documentation.Tests.ps1](../../tests/pester/Quality/Documentation.Tests.ps1) | 文書のリンク切れ、ジョブ・モジュール・ファイル・設定項目・ページスクリプトの掲載漏れ、公開関数のヘルプ |

## 3. テスト補助

### PowerShell（[tests/support/TestSupport.psm1](../../tests/support/TestSupport.psm1)）

| 関数 | 用途 |
|---|---|
| `Get-RepositoryPath` | リポジトリ直下からの相対パスを絶対パスにする |
| `New-ManualClock` | 手で進む時計。`Sleep` を呼ぶとその分だけ時刻が進む（実時間は待たない）。`-StepMilliseconds` で `Now` のたびに進めることもできる |
| `New-RecordingLog` / `Get-LogMessages` | ログポートの偽物と、記録したメッセージの取り出し |
| `New-ScriptedPort` / `Get-PortCalls` | 形（メンバー名・パラメーター名）を宣言した偽のポート。呼び出しを記録し、`Result` に値か `{ param($Bound) … }` を渡して応答を決める。複数のポートで記録を共有すれば、ポートをまたいだ呼び出し順を検証できる |
| `New-CallRecorder` | 記録用のリスト |
| `New-FakeCdpTransport` / `New-SimulatedPage` | CDP の偽物。タブ一覧と `Runtime.evaluate` への応答を PowerShell で作る（PageBridge・Browser サービスのテスト用） |
| `New-ContractResult` | 契約結果と同じ形のオブジェクト |
| `New-CategorizedTestException` | PageBridge の分類付き例外と同じ形の例外 |

E2E 用の補助（モック画面の起動、ブラウザの起動、ページ内での式の評価、テスト用設定ファイルの作成）は [tests/support/E2EHarness.psm1](../../tests/support/E2EHarness.psm1) にあります。

### ブラウザスクリプト（[tests/js/support/page.js](../../tests/js/support/page.js)）

| 名前 | 用途 |
|---|---|
| `SCRIPTS` | ジョブごとの注入順（jobs.psd1 と一致することをテストで確認） |
| `loadPage({ html, scripts, setup })` | jsdom に DOM を作り、本番と同じく文字列として評価してスクリプトを読み込む。`helper(name)` でヘルパーを得る |
| `failedChecks(result)` | 契約結果のうち満たさなかった条件名の配列 |
| `plain(value)` | jsdom 側のオブジェクトを比較用の素のオブジェクトにする |

jsdom はレイアウトを計算しないため、`hidden` 属性・`display:none`・`visibility:hidden` が自分か祖先にあれば大きさ 0、それ以外は 100×20 とみなす簡易版に置き換えています。fixture（[tests/js/fixtures](../../tests/js/fixtures)）は、モック画面と同じ契約要素を持つ静的な DOM です。

## 4. 変更とテストの対応

| 変更したもの | 直す・足すテスト |
|---|---|
| 判定ルール・名前の規則などの純粋関数 | そのジョブの単体テスト（境界値を TestCases で並べる） |
| Flow（処理の順序・止まり方） | そのジョブの Flow のテスト（`New-ScriptedPort` で呼び出し順と停止を確かめる） |
| ページスクリプト | `tests/js` の該当テスト。構造の違いを吸収する例と、意味の違いで止まる例の両方 |
| 操作カタログ | `tests/js` の `ack` のテスト、Architecture の対応チェックが自動で確かめる |
| 実行基盤のサービス | `tests/pester/JobHost` |
| ブラウザとの通信 | `tests/pester/PageBridge`（偽の CDP） |
| 設定項目 | ShippedConfig が検出する。[configuration.md](configuration.md) にも追記する |
| 画面の流れ・連携 | E2E（`-IncludeE2E`）。モック画面も合わせて直す |

## 5. テストを書くときの約束

- テストも Windows PowerShell 5.1 で動く書き方にする（品質ゲートの対象に含まれる）。
- 実時間を待たない。待機・タイムアウトは `New-ManualClock` で表す。
- 一時ファイルは `$TestDrive` に作る。リポジトリの中に書かない（E2E の出力も `$TestDrive`）。
- 偽のポートは本物と同じ形の検証（`Assert-*Ports`）を通す。形がずれた偽物でテストが通る状態を作らない。
- テスト名は「何をすると、どうなるか」を英語の文で書く（例: `stops before the sync when the exported CSV does not exist`）。
- ブラウザスクリプトのテストでは、テスト用に部品の中身を差し替えない。DOM だけを変えて確かめる。

## 6. CI

[.github/workflows/tests.yml](../../.github/workflows/tests.yml)（GitHub Actions）が、pull request と手動実行のときに次を実行します。

| 環境 | 内容 |
|---|---|
| Windows | Windows PowerShell 5.1 で Pester とブラウザスクリプトのテスト、PowerShell 7 で E2E を含む Pester（ブラウザは Edge） |
| Linux | PowerShell 7 で E2E を含むテスト一式（ブラウザは Chrome） |

本番と同じ Windows PowerShell 5.1 での実行結果は、ここで確かめられます。

## この文書を更新するとき

- テストの層・実行方法・補助関数・品質ゲート・CI が変わったとき
