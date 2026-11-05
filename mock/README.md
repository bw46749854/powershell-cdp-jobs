# モック画面

ジョブの動作確認と E2E テストのための、架空の業務画面です。実在の製品・組織・人物とは関係ありません。データは開いた日を基準に決定的に作られ（同じ日に開けば同じデータ）、操作はどこにも送信されません。

| 画面 | URL | 対象のジョブ |
|---|---|---|
| 温室コンソール — 区画一覧 | http://localhost:8080/greenhouse-console/ | PlotRosterExport、SoilAnalysisTargetSync（週次） |
| 作付け台帳 — 区画一覧 | http://localhost:8080/planting-ledger/ | PlantingRecordExport（月次） |

## 使い方（Windows）

1. `start-mock-site.bat` — `server.ps1` で `site/` を http://localhost:8080/ に配信する（ウィンドウを閉じるまで。管理者権限は不要）。
2. `open-browser.bat` — リモートデバッグ（ポート 9222）を有効にした Edge を、専用のプロファイルで開き、2つの画面を表示する。
3. リポジトリ直下の `週次_土壌分析対象の整合.bat` / `月次_定植レポート.bat` を実行する。

PowerShell 7 なら `pwsh -File mock/server.ps1 -Port 8181` のようにポートを変えて起動できます。

## 画面の作り

どちらの画面も、ジョブが前提にする契約（意味）を満たし、ジョブが吸収すべき構造の違いを含むように作っています（[docs/browser/page-contracts.md](../docs/browser/page-contracts.md)）。

| 画面 | 含めている構造・振る舞い |
|---|---|
| 温室コンソール | 仮想スクロール（表示範囲の前後の行だけ描画）、左固定ペインと通常ペインの両方に同じ区画の行、チェックボックスを包む label、メニュー項目を包むラッパー、グループの切り替え（「全区画（既定）」以外では画面識別に一致しない）、絞り込み欄、「土壌分析を依頼」（押しても送信しない） |
| 作付け台帳 | 固定列側・通常列側の2つの表、仮想スクロール、少し遅れて表示される区画詳細、タブとラジオ、画面上部の「区画コード列の位置」で区画コード列を固定列側・通常列側に切り替えられる |

データの特徴:

- 温室コンソールは3棟 × 20区画。土壌分析の完了と最終計測日時の差が、しきい値（7日）の前後に散らばる。分析したことがない区画もある。チェックの初期状態はばらばら。
- 作付け台帳は24区画。先月・今月・それより前の定植が混ざり、1件だけ定植日が空欄の記録がある（集計の失敗一覧に載る）。
- CSV は UTF-8（BOM 付き）・CRLF・全項目を引用符で囲む。ダウンロード名は温室コンソールが `plots_yyyyMMdd.csv`、作付け台帳が `planting_yyyyMMdd.csv`。

E2E テスト向けに、温室コンソールは `window.mockConsole`（選択中の区画コード・「土壌分析を依頼」が押された回数）を公開しています。ジョブはこれを使いません。

## ファイル

| ファイル | 役割 |
|---|---|
| [server.ps1](server.ps1) | 静的ファイルの配信（localhost だけ、GET / HEAD だけ、`site` の外は返さない、キャッシュしない） |
| [start-mock-site.bat](start-mock-site.bat) / [open-browser.bat](open-browser.bat) | 起動用 |
| [site/index.html](site/index.html) | 画面の一覧 |
| [site/shared/mock-data.js](site/shared/mock-data.js) | 決定的なデータの生成 |
| [site/shared/mock-kit.js](site/shared/mock-kit.js) | CSV の作成とダウンロード、仮想スクロール、通知 |
| [site/shared/base.css](site/shared/base.css) | 共通のスタイル |
| [site/greenhouse-console](site/greenhouse-console) | 温室コンソール（`index.html` / `app.js` / `style.css`） |
| [site/planting-ledger](site/planting-ledger) | 作付け台帳（同上） |

画面の見た目（クラス名・色・配置）は契約ではありません。構造の違いへの強さを試すときは、自由に変えてかまいません。契約（意味）を変えるときは、ページスクリプト・テストの fixture・[page-contracts.md](../docs/browser/page-contracts.md) と合わせて直してください。

## この文書を更新するとき

- 画面・データ・起動方法・公開している確認用の関数が変わったとき
