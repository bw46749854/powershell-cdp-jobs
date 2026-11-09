# 用語集

このプロジェクトの文書・コード・ログに出てくる言葉です。詳しい説明がある文書へのリンクを付けています。

## 設計の言葉

| 用語 | 意味 | 詳しく |
|---|---|---|
| ジョブ | 1つの定型作業を行う単位。jobs.psd1 に名前で登録し、`-JobName` で起動する | [ARCHITECTURE.md](../ARCHITECTURE.md) |
| 連携ジョブ | 既存のジョブを決まった順に呼び、成果物のパスを受け渡すジョブ（週次・月次） | [modules/JobChains.md](modules/JobChains.md) |
| 子ジョブ | 連携ジョブから呼ばれるジョブ。単独で実行したときと同じ入口を通る | 同上 |
| ジョブ定義（ジョブカタログ） | `app/config/jobs.psd1`。ジョブ名 → モジュール・コマンド・ブラウザを使うか・ページスクリプト | [guides/configuration.md](guides/configuration.md) |
| 設定 | `app/config/settings.psd1`。共通設定（`Common`）とジョブごとの設定（`Jobs.<ジョブ名>`） | 同上 |
| 実行基盤 | JobHost。設定とジョブ定義を読み、Context を組み立ててジョブを呼ぶ | [modules/JobHost.md](modules/JobHost.md) |
| Context | ジョブコマンドが受け取る唯一の引数。そのジョブの設定と、使ってよいサービスの全量 | [ARCHITECTURE.md](../ARCHITECTURE.md#3-context-とサービスポート) |
| サービス | 実行基盤が用意する外の世界への窓口（Log / Clock / Files / Downloads / Lists / Jobs / Browser） | 同上 |
| ポート | 「メンバーが scriptblock のオブジェクト」の形をした窓口。ジョブはポートからだけ外の世界に触れる | [modules/JobKit.md](modules/JobKit.md#ポートの形) |
| ポートの形 | メンバー名と、各メンバーの必須のパラメーター名。`Assert-PortShape` で検証する | 同上 |
| 合成ルート | 各ジョブの `Private/Ports.ps1`。Context のサービスから、そのジョブが使うポートを組み立てる唯一の場所 | [decisions/0002](decisions/0002-ports-and-composition-root.md) |
| Flow | 処理の順序と止まる条件だけを書いたファイル（`Private/Flow*.ps1`） | [guides/design-principles.md](guides/design-principles.md) |
| 純粋関数 | ファイル・時刻・ブラウザに触れず、引数だけから結果を決める関数（Policy・Plan・Records など） | 同上 |
| 結果（結果の約束） | ジョブがちょうど1つ返すオブジェクト（`Job` / `Ok` / `Outputs` / `Summary`）。失敗は例外で表す | [decisions/0003](decisions/0003-job-result-protocol.md) |
| 品質ゲート | 設計の境界・5.1 互換・設定・文字コード・文書を検査するテスト（`tests/pester/Quality`） | [guides/testing.md](guides/testing.md) |
| 不変条件 | どんな理由があっても破らない約束（依頼をクリックしない、など） | [guides/maintenance-rules.md](guides/maintenance-rules.md) |

## ブラウザとの境界の言葉

| 用語 | 意味 | 詳しく |
|---|---|---|
| CDP | Chrome DevTools Protocol。ブラウザをプログラムから操作する仕組み。WebSocket で JSON の命令を送る | [modules/PageBridge.md](modules/PageBridge.md#cdp-の基礎) |
| デバッグ用ポート | `--remote-debugging-port=9222` で開くポート。`http://localhost:9222/json` でタブの一覧が得られる | 同上 |
| タブ（ターゲット） | ブラウザの1つのページ。画面識別に一致するものをちょうど1つ選んで操作する | [modules/PageBridge.md](modules/PageBridge.md#タブの選び方) |
| 画面識別 | タブが対象の画面かを判定すること（操作カタログの `Kind = 'Identity'`） | 同上 |
| ページスクリプト | ページへ注入する JavaScript（`app/browser`）。画面の探し方と操作を持つ | [browser/pagekit.md](browser/pagekit.md) |
| 注入 | ページスクリプトを連結して、ページの中で評価すること | [modules/PageBridge.md](modules/PageBridge.md#注入と呼び出し) |
| pagekit | ページスクリプトの核。`window.__pagekit` を作り、部品からヘルパーを組み立てる | [browser/pagekit.md](browser/pagekit.md) |
| 部品（part） | 画面ごと（screens）・機能ごと（features）のメソッドのまとまり | 同上 |
| ヘルパー | 部品をまとめた、ジョブ1つ分のメソッドの集まり（`window.__pagekit.helpers.<名前>`） | 同上 |
| 操作カタログ | 各ジョブの `PageOperations.psd1`。PowerShell の操作名 → ヘルパーのメソッドと Kind | [modules/PageBridge.md](modules/PageBridge.md#操作カタログ) |
| Kind | 操作の種類（Identity / Contract / Action / Query / Probe / Cleanup）。呼び方とヘルパーが無いときの扱いを決める | 同上 |
| ページポート | 各ジョブの `Private/Page.ps1`。操作カタログの操作を業務の名前で包んだポート | [guides/design-principles.md](guides/design-principles.md) |
| 契約 | 操作の前提として画面が満たすべき条件の集まり。結果は `{ scope, ok, fatalCount, warningCount, checks, details }` | [decisions/0001](decisions/0001-dom-as-contract.md) |
| 意味 / 構造 | 契約で厳格に確かめるもの（名前・状態・件数）と、吸収するもの（タグ・クラス・入れ子・列の並び） | [browser/page-contracts.md](browser/page-contracts.md) |
| fatal / warning | 契約の条件の重さ。fatal が1つでもあれば止まる。warning は記録して続ける | [browser/pagekit.md](browser/pagekit.md) |
| scope | 契約結果の名前。操作カタログの `Scope` と一致しなければ取り違えとして止まる | 同上 |
| 操作スコープ | 区画一覧の、チェック操作に使うペイン（固定列側・通常列側）。最初に1つ決めて保持する | [browser/page-contracts.md](browser/page-contracts.md) |
| エラーの分類 | 例外に付ける `pagebridge.category`。`session-lost` などは「通信を続けられない」 | [modules/PageBridge.md](modules/PageBridge.md#エラーの分類) |

## 業務（題材）の言葉

題材は架空の温室運用です。

| 用語 | 意味 |
|---|---|
| 温室コンソール | 区画の一覧・状態を管理する業務画面（週次の対象） |
| 作付け台帳 | 区画ごとの作付けの記録を管理する業務画面（月次の対象） |
| 区画 / 区画コード | 温室の中の栽培単位と、その識別子（例: `GH2-B01`） |
| 区画一覧 CSV | 温室コンソールが出力する全区画の一覧。週次の判定の入力 |
| 土壌分析の対象 | 区画一覧で、区画のチェックを ON にした状態。担当者が後で「土壌分析を依頼」を押す |
| 最終計測日時 / 土壌分析の完了 | 区画一覧 CSV の列。この2つの日付の差で ON / OFF を決める |
| 作付け記録 | 区画ごとの作物名・品種・定植日などの記録。区画詳細の「作付け記録」タブから CSV で出力する |
| 定植 / 定植日 | 苗を畑（区画）に植えること / その日。月次は先月に定植した作付けを集める |
| CSV データエラー | 週次の入力 CSV で、判定できない行・区画コードの空欄や重複。1件でもあれば画面に触れずに止まる |
| 失敗一覧 | 処理できなかった区画・ファイル・行と理由を書いた CSV。1件でもあればジョブは異常終了する |

## この文書を更新するとき

- 新しい用語を文書・コード・ログで使い始めたとき、用語の意味が変わったとき
