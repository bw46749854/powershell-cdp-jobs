# PageBridge — ブラウザとの境界

ブラウザ（Edge / Chrome）と Chrome DevTools Protocol（CDP）で通信し、操作するタブを選び、ページスクリプトを注入して、操作カタログに従って呼び出します。実行基盤（JobHost）の Browser サービスだけが使い、ジョブのモジュールは直接使いません。どの画面のどのボタンか、という業務の知識は持ちません（それは操作カタログとページスクリプトにある）。

依存: `JobKit`

## CDP の基礎

PageBridge のコードを読むために必要な範囲だけを書きます。

1. **デバッグ用ポートを開いたブラウザ**: Edge / Chrome を `--remote-debugging-port=9222` 付きで起動すると、`http://localhost:9222/json` でタブ（ターゲット）の一覧を JSON で返します。1つのタブには `type`（`page` など）、`title`、`url`、`webSocketDebuggerUrl` があります。
2. **タブとの接続**: `webSocketDebuggerUrl` に WebSocket で接続すると、そのタブに命令を送れます。
3. **命令と応答**: 命令は `{ "id": 7, "method": "Runtime.evaluate", "params": { … } }` の JSON です。ブラウザは同じ `id` を付けて `{ "id": 7, "result": { … } }` か `{ "id": 7, "error": { … } }` を返します。`id` の無いメッセージ（イベントの通知）も届くため、`Send-CdpCommand` は自分の `id` の応答が来るまで、それ以外を読み捨てます。
4. **このプロジェクトが使う命令は3つだけです。**

   | 命令 | 用途 | 主なパラメーター |
   |---|---|---|
   | `Runtime.evaluate` | ページの中で JavaScript の式を評価する（注入・ヘルパーの呼び出し） | `returnByValue`（結果を JSON の値で返す。DOM 要素は返せない）、`awaitPromise`（Promise の解決まで待つ）、`userGesture`（利用者の操作として扱う） |
   | `Browser.setDownloadBehavior` | ダウンロードを確認なしで許可し、保存先を決める | `behavior = 'allow'`、`downloadPath` |
   | `Page.setDownloadBehavior` | 上が使えない環境での代わり | 同上 |

5. **期限と切断**: 命令1つ（送信から応答まで）に期限を1つ持ちます。期限切れ・切断・応答が JSON でないときは、そのセッションを強制的に閉じます（`Stop-CdpSessionAfterFailure`）。遅れて届いた応答で `id` の対応が崩れたセッションを、続けて使わないためです。以後の呼び出しは `session-lost` で即座に失敗します。
6. **プロキシを使わない**: 通信は localhost だけです。社内プロキシの設定に引きずられないよう、HTTP / WebSocket ともにプロキシを無効にしています（[CdpTransport.ps1](../../app/modules/PageBridge/Private/CdpTransport.ps1)）。

## 公開関数

| 関数 | ファイル | 内容 |
|---|---|---|
| `New-CdpTransport` | [Public/Transport.ps1](../../app/modules/PageBridge/Public/Transport.ps1) | 実ブラウザ用のトランスポート（HTTP と WebSocket。プロキシを使わない） |
| `Import-PageOperationCatalog -Path` | [Public/Catalog.ps1](../../app/modules/PageBridge/Public/Catalog.ps1) | 操作カタログを読み、検証済みのカタログを返す |
| `Open-PageConnection` | [Public/PageConnection.ps1](../../app/modules/PageBridge/Public/PageConnection.ps1) | 画面識別に一致するタブを1つ選んで接続し、`Session` / `Target` / `Gateway` を返す |
| `Close-PageConnection` | 同上 | 切断する（何度呼んでもよい） |
| `Set-PageDownloadDirectory` | 同上 | ブラウザのダウンロード先を設定する |
| `Test-PageBridgeFatalError` | 同上 | ブラウザとの通信を続けられない分類のエラーか |

## タブの選び方

1. `DebuggerUrl`（例: `http://localhost:9222/json`）からタブ一覧を得る（制限時間は `ConnectTimeoutSeconds`）。
2. 業務画面になり得ないものを除く: `type` が `page` でない、WebSocket の URL が無い、`chrome://`・`edge://`・`devtools://`・`chrome-extension://`、Service Worker。
3. 残った各タブに一時的に接続し、ページスクリプトを注入して、画面識別（`Kind = 'Identity'` の操作）を実行する。
   - 接続できなかったタブ（段階 `connect`）は「不一致」として扱い、他のタブの判定を続ける。
   - 接続できたのに画面識別そのものが失敗した（段階 `identify`）ときは、スクリプトかカタログの誤りとして即座に止める。
4. 一致したタブが**ちょうど1つ**のときだけ接続する。0個・2個以上のときは、タブごとの判定結果（満たしていない条件の名前と説明）をログに出して止める。

## 操作カタログ

各ジョブの `PageOperations.psd1` です。PowerShell 側の操作名と、ページヘルパーのメソッドを対応させます。

```powershell
@{
    Helper = 'plotRosterExport'                     # window.__pagekit.helpers の名前
    Operations = @{
        DetectScreen = @{ Method = 'detectScreen'; Kind = 'Identity'; Scope = 'greenhousePlotList.identity'; TimeoutSeconds = 3; Label = '区画一覧画面の識別' }
        OpenTaskMenu = @{ Method = 'openTaskMenu'; Kind = 'Action'; Label = '「操作」メニューを開く' }
    }
}
```

| キー | 必須 | 内容 |
|---|---|---|
| `Method` | ○ | ヘルパーのメソッド名（JavaScript の識別子） |
| `Kind` | ○ | 下表のいずれか |
| `Scope` | Identity / Contract のとき | ページが返す契約結果の `scope` と一致すること（取り違えの検出） |
| `TimeoutSeconds` | | この操作の制限時間・待機の上限（省略時は Invoke: `CommandTimeoutSeconds`、WaitUntil / WaitFor: 10 秒、Assert: 20 秒） |
| `Label` | | ログ・エラーに出す名前 |

`Kind = 'Identity'` の操作はちょうど1つ必要です。未知のキーは誤記とみなして止まります。

| Kind | 呼び出し方 | ヘルパー・メソッドが無いとき |
|---|---|---|
| `Identity` | Invoke | 契約失敗（fatal）の結果を返す（そのタブは不一致） |
| `Contract` | Assert | 契約失敗（fatal）の結果を返す |
| `Action` | Invoke | 例外（`helper-missing`、続行不能） |
| `Query` | Invoke / WaitFor | 例外（0件と「無い」を混同しないため） |
| `Probe` | WaitUntil | `false` を返す（待ち続ける） |
| `Cleanup` | Invoke | warning の結果を返す（finally の後始末を壊さない） |

Kind に許されない呼び出し方（例: Contract を Invoke で読み捨てる）は、設定の誤りとして止まります。→ [decisions/0004-operation-catalog-kinds.md](../decisions/0004-operation-catalog-kinds.md)

## 注入と呼び出し

- **注入**（`Inject`）: jobs.psd1 の `Browser.Scripts` を順に読み（UTF-8、BOM は除く）、1つの式に連結して評価します。最後に `__pagekit.ack('<Helper>')` でヘルパーのメソッド一覧を受け取り、カタログのメソッドがすべてあるか確かめます。注入はタブを選ぶとき・接続したときに行い、何度行っても同じ状態になります（kernel は毎回作り直す）。
- **呼び出し**（`Invoke`）: `(async () => { … return await helper[method](...args); })()` の形の式を `Runtime.evaluate`（`awaitPromise`、`returnByValue`）で評価します。引数は JSON の値として埋め込みます。
- **待機**（`WaitUntil` / `WaitFor` / `Assert`）: 250 ミリ秒ごとに評価し直します。通信を続けられない分類のエラーは待たずに即座に伝え、期限までに条件が成り立たなければ `wait-timeout` にします。`Assert` が期限切れになったときは、もう一度評価して、満たしていない条件の詳細をエラーに載せます。
- **契約結果**: `{ scope, ok, fatalCount, warningCount, checks, details }` の形であること、`scope` がカタログと一致することを確かめ、fatal が1件でもあれば `contract` のエラー（`ページ契約違反: …`）、warning は記録して続けます。
- **ダウンロード先**: `Browser.setDownloadBehavior` を試し、使えなければ `Page.setDownloadBehavior` で設定します。

## エラーの分類

例外の `Data['pagebridge.category']` に分類を入れます。PowerShell が例外を包んでも読めるよう、判定時は内側の例外まで辿ります。

| 分類 | 例 | 通信を続けられないか |
|---|---|---|
| `session-lost` | WebSocket が閉じた、セッションが閉じている | ○ |
| `timeout` | 命令への応答が制限時間内に来ない | ○ |
| `helper-missing` | ヘルパー・メソッドが無い（画面が再読み込みされた等） | ○ |
| `protocol` | 応答を解釈できない | ○ |
| `wait-timeout` | 待機の条件が期限内に成り立たない | |
| `javascript` | ページ内の例外 | |
| `command` | CDP の命令がエラーを返した | |
| `contract` | 契約違反、一致するタブが無い・複数 | |
| `browser-unreachable` | デバッグ用ポートに接続できない | |
| `configuration` | カタログ・スクリプト・設定の誤り | |

## トランスポート

ブラウザとの通信は、次の形のポート（`New-CdpTransport`）を通します。テストでは同じ形の偽物（`New-FakeCdpTransport`）に差し替えます。

| メンバー | パラメーター |
|---|---|
| `GetText` | `Uri`, `TimeoutSeconds` |
| `Connect` | `Uri`, `TimeoutMilliseconds` |
| `Send` | `Handle`, `Text`, `TimeoutMilliseconds` |
| `Receive` | `Handle`, `TimeoutMilliseconds` |
| `Close` | `Handle`, `TimeoutMilliseconds` |
| `Abort` | `Handle` |

## コードの読み方

ファイルは下の層から上の層へ、次の順に依存しています。上の層は下の層の形にだけ依存し、`System.Net` を直接使うのは `CdpTransport.ps1` だけです。

```text
PageConnection.ps1（公開）   接続・切断・ダウンロード先
  TargetSelection.ps1          タブ一覧 → 操作し得るタブ → 画面識別でちょうど1つ
  PageGateway.ps1              Inject / Invoke / WaitUntil / WaitFor / Assert
    OperationCatalog.ps1         操作の定義と、Kind ごとに許される呼び方
    HelperCall.ps1               ヘルパー呼び出しの JavaScript の式
    ScriptBundle.ps1             スクリプトの連結と ack の検証
    ContractResult.ps1           契約結果の形・scope・合否
    CdpRuntime.ps1               Runtime.evaluate、評価の待機、ダウンロード先
      CdpSession.ps1               命令の送受信、期限、失敗時の強制切断
        CdpTransport.ps1             HTTP / WebSocket（トランスポートポートの実装）
BridgeErrors.ps1               分類付きの例外（どの層からも使う）
```

主なデータの形:

| 名前 | 形 | 作る場所 |
|---|---|---|
| セッション | `Transport` / `Handle` / `WebSocketUrl` / `CommandTimeoutSeconds` / `Clock` / `NextId` / `Closed` | `Open-CdpSession` |
| 操作カタログ | `Path` / `Helper` / `Operations`（操作名 → 操作の定義） / `IdentityOperation` | `Import-PageOperationCatalog` |
| ゲートウェイの状態 | `Session` / `Catalog` / `ScriptPaths` / `JobName` / `Log` | `New-PageGatewayState` |
| 接続 | `Session` / `Target`（`Title`, `Url`） / `Gateway` / `Log` | `Open-PageConnection` |
| 操作の定義 | `Name` / `Method` / `Kind` / `Scope` / `TimeoutSeconds` / `Label` | `Import-PageOperationCatalog` |
| 契約結果 | `{ scope, ok, fatalCount, warningCount, checks, details }` | ページスクリプト（pagekit の `contract.result`） |

変更の典型と影響:

| 変えたいこと | 直す場所 | 影響 |
|---|---|---|
| 待機の既定の上限・間隔 | `PageGateway.ps1` の `$script:PageWaitDefaults`、`Wait-CdpEvaluation` の `PollMilliseconds` | すべてのジョブの待機 |
| Kind の追加・扱いの変更 | `OperationCatalog.ps1`、`HelperCall.ps1`（ヘルパーが無いときの扱い） | すべての操作カタログ。設計判断の記録（[decisions/0004](../decisions/0004-operation-catalog-kinds.md)）も直す |
| 「通信を続けられない」分類の変更 | `BridgeErrors.ps1` の `$script:BridgeFatalCategories` | ジョブの区画ごとの処理が止まるか続くかが変わる |
| タブを候補から除く条件 | `TargetSelection.ps1` の `Test-OperablePageTarget` | 画面識別を試すタブが変わる |

## ファイル構成

| ファイル | 役割 |
|---|---|
| [PageBridge.psm1](../../app/modules/PageBridge/PageBridge.psm1) | 読み込むファイルの一覧と公開関数 |
| [Public/Transport.ps1](../../app/modules/PageBridge/Public/Transport.ps1) | 実ブラウザ用のトランスポートを作る |
| [Public/Catalog.ps1](../../app/modules/PageBridge/Public/Catalog.ps1) | 操作カタログの読み込み |
| [Public/PageConnection.ps1](../../app/modules/PageBridge/Public/PageConnection.ps1) | 接続・切断・ダウンロード先・エラーの判定 |
| [Private/BridgeErrors.ps1](../../app/modules/PageBridge/Private/BridgeErrors.ps1) | 分類付きの例外と、分類の判定 |
| [Private/CdpTransport.ps1](../../app/modules/PageBridge/Private/CdpTransport.ps1) | HTTP / WebSocket の通信の実装（プロキシを使わない） |
| [Private/CdpSession.ps1](../../app/modules/PageBridge/Private/CdpSession.ps1) | セッション、命令の送受信と期限 |
| [Private/CdpRuntime.ps1](../../app/modules/PageBridge/Private/CdpRuntime.ps1) | 式の評価、ページ内の例外の分類、評価の待機、ダウンロード先の設定 |
| [Private/TargetSelection.ps1](../../app/modules/PageBridge/Private/TargetSelection.ps1) | タブ一覧、操作し得るタブの判定、画面識別によるタブの選択 |
| [Private/OperationCatalog.ps1](../../app/modules/PageBridge/Private/OperationCatalog.ps1) | Kind と呼び出し方の規則、操作の定義の検証 |
| [Private/HelperCall.ps1](../../app/modules/PageBridge/Private/HelperCall.ps1) | ヘルパー呼び出しの式の組み立て（ヘルパーが無いときの扱いを含む） |
| [Private/ScriptBundle.ps1](../../app/modules/PageBridge/Private/ScriptBundle.ps1) | ページスクリプトの連結と、ack による検証 |
| [Private/ContractResult.ps1](../../app/modules/PageBridge/Private/ContractResult.ps1) | 契約結果の形・scope・合否の判定と、ログ用の書式 |
| [Private/PageGateway.ps1](../../app/modules/PageBridge/Private/PageGateway.ps1) | 注入・Invoke・WaitUntil・WaitFor・Assert の窓口 |

## テスト

| テスト | 内容 |
|---|---|
| [CdpSession.Tests.ps1](../../tests/pester/PageBridge/CdpSession.Tests.ps1) | 命令の送受信、期限、切断の分類 |
| [CdpRuntime.Tests.ps1](../../tests/pester/PageBridge/CdpRuntime.Tests.ps1) | 評価、ページ内の例外の分類、待機、ダウンロード先の設定 |
| [OperationCatalog.Tests.ps1](../../tests/pester/PageBridge/OperationCatalog.Tests.ps1) | カタログの検証、Kind と呼び出し方 |
| [HelperCall.Tests.ps1](../../tests/pester/PageBridge/HelperCall.Tests.ps1) | 呼び出しの式（Node.js で実際に評価して確かめる） |
| [ContractAndBundle.Tests.ps1](../../tests/pester/PageBridge/ContractAndBundle.Tests.ps1) | 契約結果の判定、スクリプトの連結と ack |
| [PageConnection.Tests.ps1](../../tests/pester/PageBridge/PageConnection.Tests.ps1) | タブの選び方（0個・1個・複数、接続できないタブ）、接続 |

## この文書を更新するとき

- 公開関数・タブの選び方・カタログの書式と Kind・待機の振る舞い・エラーの分類・ファイル構成が変わったとき
