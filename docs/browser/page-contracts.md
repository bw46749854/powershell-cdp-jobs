# 画面の契約

ジョブが前提にする画面の「意味」（契約）と、吸収する「構造」の違いを、画面ごとにまとめます。考え方は [decisions/0001-dom-as-contract.md](../decisions/0001-dom-as-contract.md)、画面が変わったときの手順は [guides/changing-page-contracts.md](../guides/changing-page-contracts.md) にあります。

各ページスクリプトの冒頭コメントにも同じ内容を書いています（正本はスクリプトの冒頭コメントで、この文書は一覧のための要約です）。条件の名前（`identity.app.name` など）はログ・エラーメッセージに出る名前と同じです。

## ページスクリプトの一覧

| スクリプト | 部品 / ヘルパー | 使うジョブ |
|---|---|---|
| [kernel/pagekit.js](../../app/browser/kernel/pagekit.js) | 核（`window.__pagekit`）。[pagekit.md](pagekit.md) | すべて |
| [screens/greenhouse-plot-list.js](../../app/browser/screens/greenhouse-plot-list.js) | 部品 `screen.greenhousePlotList` | PlotRosterExport, SoilAnalysisTargetSync |
| [features/plot-roster-export.js](../../app/browser/features/plot-roster-export.js) | 部品 `feature.plotRosterExport`、ヘルパー `plotRosterExport` | PlotRosterExport |
| [features/soil-analysis-sync.table.js](../../app/browser/features/soil-analysis-sync.table.js) | 部品 `feature.soilAnalysisSync.table` | SoilAnalysisTargetSync |
| [features/soil-analysis-sync.js](../../app/browser/features/soil-analysis-sync.js) | 部品 `feature.soilAnalysisSync`、ヘルパー `soilAnalysisSync` | SoilAnalysisTargetSync |
| [screens/ledger-plot-list.js](../../app/browser/screens/ledger-plot-list.js) | 部品 `screen.ledgerPlotList` | PlantingRecordExport |
| [features/planting-record-export.grid.js](../../app/browser/features/planting-record-export.grid.js) | 部品 `feature.plantingRecordExport.grid` | PlantingRecordExport |
| [features/planting-record-export.detail.js](../../app/browser/features/planting-record-export.detail.js) | 部品 `feature.plantingRecordExport.detail` | PlantingRecordExport |
| [features/planting-record-export.js](../../app/browser/features/planting-record-export.js) | ヘルパー `plantingRecordExport`（上の3部品を登録） | PlantingRecordExport |

## 温室コンソール「区画」一覧

### 契約（意味）

| 要素 | 契約 | 使う条件 |
|---|---|---|
| 製品名 | 「温室コンソール」が `document.title` かバナー（`role=banner` / `header`）にある | `*.app.name` |
| メインメニューの「区画」 | ちょうど1つ（目印 `data-nav="plots"`、無ければメニュー内の名前「区画」）で、`aria-current` が `page` / `true` | `*.nav.section.unique`、`*.nav.section.current`、`initial.nav.section.clickable` |
| 選択中のグループ | グループツリー（`role=tree`）で `aria-selected="true"` の項目がちょうど1つで、名前が「全区画（既定）」 | `*.group.default.selected` |
| 件数表示 | 「区画: N」から件数を1つに決められる（目印 `data-count="plots"`、無ければ表示文言から探す） | `exportScreen.count.readable`、`screen.count.readable`、`list.count.readable` |
| 「操作」ボタン | 名前「操作」でメニューを開く（`aria-haspopup` が `menu` / `true`）ボタンがちょうど1つ | `exportScreen.taskButton.unique`、`exportScreen.taskButton.clickable` |
| 「CSV出力」 | 「操作」のメニュー内に `role=menuitem`・名前「CSV出力」がちょうど1つ | （操作時に確認） |
| 絞り込み欄 | `aria-label` か `placeholder` が「区画コードで絞り込み」の検索欄がちょうど1つ（ジョブは使わない） | `screen.searchBox.unique` |
| 一覧の表 | `role=row` の行と `gridcell` などのセル。データ行は `data-row-id` を持つ | `list.rows.*` |
| 列 | 見出しの文言で特定する。必須: 区画コード・担当者・稼働状態・最終計測日時・土壌分析の依頼・土壌分析の完了。見出し行の中で重複しない | `list.header.fullRow.unique`、`list.header.required.unique` |
| 選択列 | 見出しのセルにチェックボックス（すべて選択）がある列。各行のその列にチェックボックスがちょうど1つ | `list.rows.checkbox.unique` |
| 選択状態 | 行の `aria-selected="true"` またはチェックボックスの `checked` | （整合の確認） |
| 「土壌分析を依頼」 | 名前「選択区画」の `role=group` の中に `role=menuitem`・名前「土壌分析を依頼」がちょうど1つ。区画を選ぶと有効（`disabled` / `aria-disabled` でない） | `postSelection.requestItem.unique`、`postSelection.requestItem.enabled` |

`*` は確認の場面ごとの接頭辞です（画面識別 `identity`、PlotRosterExport の `initial` / `exportScreen`、SoilAnalysisTargetSync の `screen`）。同じ部品の同じ判定を使うため、2つのジョブで画面の識別がずれることはありません。

### 吸収する構造の違い

| 違い | 吸収の仕方 |
|---|---|
| メニュー項目のタグ（`a` / `button` / `li`）、CSS クラス | 役割・名前・目印で探す |
| 括弧の全角・半角（「全区画（既定）」「全区画 (既定)」） | どちらも既定のグループとみなす |
| 件数表示の目印（`data-count`）の有無 | 無ければ表示文言「区画: N」から探す |
| メニューの位置 | `aria-controls` が指すメニューを優先し、無ければボタンを含む最も近い祖先の中のメニュー |
| メニュー項目・セルを包むラッパー要素 | 役割で探すので段数に依存しない |
| 列の並び順 | 見出しの文言で列を特定する |
| チェックボックスを包む `label` の有無 | `label` があれば `label` を押す |
| メニューが閉じているか | 項目の有効・無効は表示状態ではなく属性で判断する |
| 仮想スクロール（表示範囲の行だけが描画される） | 表示中の行を読み、スクロールしながらたどる |

### 操作スコープ（どのペインの行を操作するか）

同じ区画の行が「左固定ペイン」（`role=rowgroup` で `data-pinned` を持つ）と「通常ペイン」の両方に描画される画面があるため、操作に使うペインを1つに決めてから行を読みます（両方を数えると件数が倍になり、片方だけ操作すると状態の確認を誤る）。

1. 表示中のデータ行を含むペインごとに、「区画コード」の見出しがちょうど1つ・選択列がある見出し行がちょうど1つあるかを調べ、行 ID・区画コード・チェックボックスの欠けや重複がないかを確かめる。
2. 問題の無い（有効な）ペインのうち、左固定ペインがちょうど1つならそれを使う（`single_valid_pinned_pane`）。
3. 左固定ペインが無く、有効なペインがちょうど1つならそれを使う（`single_valid_pane`）。
4. それ以外は推測で選ばずに止まる（`no_valid_pane` / `multiple_valid_pinned_panes` / `multiple_valid_panes_without_pinned`）。

ペインごとの問題は `header_row_count=N`、`no_rows`、`row_id_missing`、`plot_code_missing`、`checkbox_not_unique`、`duplicate_rows=…` として `list.scope.unique` の詳細に出ます。決めたペインは保持し、走査中に画面の再描画でペインが失われたら（`scope_not_prepared`）その区画を失敗にします。

### 確認の一覧

| 確認（scope） | 条件 |
|---|---|
| `greenhousePlotList.identity` | `identity.app.name`、`identity.nav.section.unique`、`identity.nav.section.current`、`identity.group.default.selected` |
| `plotRosterExport.initial` | `initial.document.ready`、画面識別と同じ4条件（`initial.*`）、`initial.nav.section.clickable` |
| `plotRosterExport.exportScreen` | 画面識別と同じ4条件（`exportScreen.*`）、`exportScreen.count.readable`、`exportScreen.taskButton.unique`、`exportScreen.taskButton.clickable` |
| `plotRosterExport.postExport` | `postExport.click.accepted`（「CSV出力」のクリックがこのタブで実行された） |
| `soilAnalysisSync.screen` | `screen.document.ready`、画面識別と同じ4条件（`screen.*`）、`screen.searchBox.unique`、`screen.count.readable`、`screen.rows.exist` |
| `soilAnalysisSync.list` | `list.header.fullRow.unique`、`list.header.required.unique`、`list.scope.unique`、`list.rows.exist`、`list.rows.rowId`、`list.rows.plotCode`、`list.rows.checkbox.unique`、`list.count.readable`、`list.scroller.found` |
| `soilAnalysisSync.postSelection` | `postSelection.selectedRows.visible`（warning: 仮想スクロールで表示範囲外にあるだけの場合がある）、`postSelection.requestItem.unique`、`postSelection.requestItem.enabled` |

## 作付け台帳「区画一覧」と区画詳細

### 契約（意味）

| 要素 | 契約 | 使う条件 |
|---|---|---|
| 製品名 | 「作付け台帳」が `document.title` かバナーにある | `*.app.name` |
| 画面の本体 | `data-view` を持つ要素がちょうど1つで、値が `plot-list`（同じ部品で作られた別の一覧を取り違えない） | `*.view.unique`、`*.view.plotList` |
| 画面の名前 | 見出し・パンくず・`document.title` のどれかに「区画一覧」 | `*.title.plotList` |
| 件数 | `data-bind="plotList.total"` がちょうど1つで数字 | `list.total.readable` |
| 選択列 | 見出し（`th`）に「すべて選択」のチェックボックスがちょうど1つ | `list.selectionHeader.unique` |
| 区画コード列 | 見出し「区画コード」がちょうど1つで `id` を持つ。セルは `headers` 属性でその `id` を参照する | `list.codeColumn.unique` |
| 行 | `tr[data-row-id]`。区画コードのセルを持つ本体（`tbody`）がちょうど1つに決まる。「行 ID + 区画コード」が重複しない | `list.rowScope.unique`、`list.rows.*` |
| 選択中の行 | 区画詳細を開くと、その行が `aria-selected="true"` になり、選択中の行はちょうど1つ | `openedDetail.selectedRow.*` |
| 区画詳細 | `role=dialog`・名前「区画詳細」。表示中の区画コードは `data-bind="detail.plotCode"` | `openedDetail.drawer.visible`、`openedDetail.plotCode.matches` |
| 「作付け記録」タブ | `role=tablist` がちょうど1つ、その中の `role=tab`・名前「作付け記録」がちょうど1つで押せる。押した後は `aria-selected="true"` | `plantingTab.tablist.unique`、`plantingTab.tab.*` |
| 記録の種類 | ラジオ「作付け記録」がちょうど1つで、選択済み（別の種類が選ばれていたら停止する。こちらから切り替えない） | `plantingTab.recordKind.*` |
| 記録の表 | 見出し「作物名」「品種」「定植日」がある（順序は問わない） | `plantingTab.records.headers` |
| CSV 出力 | `data-export="planting"` の領域がちょうど1つで、中の押せる「CSV出力」ボタンがちょうど1つ | `plantingTab.export.area.unique`、`plantingTab.export.button.unique` |
| 閉じる | 区画詳細の中の、名前「閉じる」の押せるボタンがちょうど1つ | （後始末。決まらなければ warning） |

### 吸収する構造の違い

| 違い | 吸収の仕方 |
|---|---|
| 区画コード列が固定列側・通常列側のどちらにあるか | 列見出しの `id` とセルの `headers` で辿る（位置を見ない） |
| 区画コードのセル内のリンク（`a` / `button`）の有無 | リンクがあればリンクを、無ければセルを押す |
| 見出し・パンくずのタグ・クラス、件数表示の前後の文言 | 意味のある要素・目印だけを見る |
| タブが指すパネル（`aria-controls`）を辿れない | 区画詳細全体を探索範囲にする（`plantingTab.scope.panel` が warning） |
| ラジオのラベルが `label[for]` か、ラジオを包む `label` か | どちらでも名前を読む |
| 区画詳細の中身が少し遅れて表示される | 対象の区画コードが表示されるまで待つ（`IsDetailReadyFor`） |
| 仮想スクロール | 表示中の行を読み、スクロールしながらたどる |

### 確認の一覧

| 確認（scope） | 条件 |
|---|---|
| `ledgerPlotList.identity` | `identity.app.name`、`identity.view.unique`、`identity.view.plotList`、`identity.title.plotList` |
| `plantingExport.screen` | 画面識別と同じ4条件（`screen.*`）、`screen.grid.headers` |
| `plantingExport.list` | `list.selectionHeader.unique`、`list.codeColumn.unique`、`list.rowScope.unique`、`list.rows.exist`、`list.rows.rowId`、`list.rows.identity.unique`、`list.total.readable`、`list.scroller.found` |
| `plantingExport.openedDetail` | `openedDetail.selectedRow.unique`、`openedDetail.selectedRow.matches`、`openedDetail.drawer.visible`、`openedDetail.plotCode.matches` |
| `plantingExport.plantingTab` | `plantingTab.drawer.visible`、`plantingTab.tablist.unique`、`plantingTab.tab.unique`、`plantingTab.tab.enabled`、`plantingTab.tab.active`、`plantingTab.scope.panel`（warning）、`plantingTab.records.headers`、`plantingTab.recordKind.unique`、`plantingTab.recordKind.usable`、`plantingTab.recordKind.checked`、`plantingTab.export.area.unique`、`plantingTab.export.button.unique` |

タブを押す前の確認（`plantingExport.plantingTab.beforeClick`）では、`plantingTab.tab.active` は warning です（押す前は未選択でよい）。

## モック画面との対応

[mock/site](../../mock/site) の2つの画面は、この文書の契約（意味）をすべて満たすように作っています。構造の違い（区画コード列の位置、仮想スクロール、詳細の遅延表示、ラッパー要素）も含めてあり、E2E テストで通しの動きを確かめます。ブラウザスクリプトのテストの fixture（[tests/js/fixtures](../../tests/js/fixtures)）も同じ契約要素を持ちます。

## この文書を更新するとき

- ページスクリプトを追加したとき（一覧への掲載漏れはテストで検出される）
- 契約（意味）・吸収する構造の違い・条件の名前・確認の一覧が変わったとき
