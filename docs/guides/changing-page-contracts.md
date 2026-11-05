# 画面が変わったとき

対象の画面が変わってジョブが止まった、または画面の変更が予告されたときの判断と手順です。考え方は [decisions/0001-dom-as-contract.md](../decisions/0001-dom-as-contract.md)、画面ごとの契約は [browser/page-contracts.md](../browser/page-contracts.md) にあります。

## 1. まず「意味」か「構造」かを判断する

| 変更 | 区分 | ジョブの振る舞い | すること |
|---|---|---|---|
| CSS クラス名、タグ（`a` → `button`）、ラッパー要素の追加、列の並び替え、区画コード列が固定列側から通常列側へ移動 | 構造 | 吸収して動く | 何もしない（必要ならテストに構造の違いを追加する） |
| 全角・半角の括弧の違い（「全区画（既定）」と「全区画 (既定)」） | 構造 | 吸収して動く | 同上 |
| ボタン・メニュー・タブ・列見出しの**名前**が変わった | 意味 | 止まる | 新しい名前が同じ意味かを業務担当と確認し、契約を更新する |
| 選択状態・有効状態の表し方が変わった（`aria-selected` を使わなくなった等） | 意味 | 止まる | 状態を正しく読める新しい手がかりを契約に加える |
| 件数表示・目印（`data-*`）が無くなった | 意味 | 止まる | 代わりの手がかりを契約に加える（無ければ画面側に目印の追加を依頼する） |
| 画面の流れが変わった（詳細がダイアログから別ページに、など） | 意味 | 止まる | ページスクリプトとジョブの Flow を設計し直す |

**意味の変更を「吸収する」ように直してはいけません。** 例えば「区画コード」の見出しが見つからないときに「左から2列目」で代用すると、列が増えたときに別の列を区画コードとして読み、誤った区画を操作します。名前が本当に変わったと確認できたときだけ、新しい名前で契約を更新します。

## 2. どの条件で止まったかを特定する

止まったときのログには、満たしていない条件の名前と説明が出ます。

```text
[WARNING] 対象の画面と一致するタブが見つかりません。
  - [不一致] 区画一覧 - 第1温室 | 温室コンソール <http://.../greenhouse-console/>
      理由: 画面識別に一致しません。満たしていない条件: identity.group.default.selected「グループツリーで「全区画（既定）」だけが選択されていること」
```

```text
[ERROR] … ページ契約違反: CSV 出力前の画面
scope=plotRosterExport.exportScreen ok=False fatal=1 warning=0
[fatal] exportScreen.taskButton.unique: ツールバーの「操作」ボタン（メニューを開くボタン）がちょうど1つあること details={"ok":false,"count":0,...}
```

`details` には、候補になった要素の一覧（タグ・role・名前・表示状態）が入っています。0件なら目的の要素が無く、2件以上ならどれか決められなかったことを表します。

## 3. ページスクリプトを直す

1. 条件名から部品を探す。`identity.*` は画面の部品（`app/browser/screens`）、それ以外は機能の部品（`app/browser/features`）にあります。条件名で検索すれば `contract.check('<条件名>', …)` が見つかります。
2. 部品の冒頭コメントの「契約（意味）」「吸収する構造の違い」を読み、変更がどちらに当たるかを確かめる。
3. 直す。
   - 名前・文言は部品の先頭の定数（`const SECTION_NAME = '区画'` など）にまとめてあります。名前の変更は定数だけを直します。
   - 要素の探し方は `kit.locate`（`all` / `visibleOnly` / `unique` / `byName`）を使い、**ちょうど1つ**に決まることを確かめます。決まらないときに先頭の要素を使うような書き方はしません。
4. 冒頭コメントの「契約（意味）」「吸収する構造の違い」と、[browser/page-contracts.md](../browser/page-contracts.md) を更新する。
5. 新しい画面の形をテストに加える（次節）。
6. モック画面（[mock/site](../../mock/site)）も同じ意味を満たすように直す。E2E テストで通しの動きを確かめます。

PowerShell 側（ジョブのモジュール）には画面の探し方を書きません（テストで検査しています）。操作の追加・名前の変更が必要なときだけ、操作カタログ（`PageOperations.psd1`）とページポート（`Private/Page.ps1`）を直します。

## 4. テストを足す

ブラウザスクリプトのテスト（`tests/js/*.test.js`）は、jsdom 上に画面の DOM を作って部品を動かします。

- **構造の違いを吸収できること**: 新しい形の DOM を fixture（`tests/js/fixtures`）の引数で作り、契約が通ること・操作できることを確かめます。
- **意味の違いで止まること**: 名前や状態を変えた DOM で、該当する条件だけが `ok: false` になることを確かめます（`failedChecks` 補助関数）。

```js
test('「操作」ボタンの名前が変わったら、CSV 出力前の画面の契約を満たさない', async () => {
    const page = await loadPage({ html: greenhouseConsoleHtml().replace('>操作<', '>アクション<'), scripts: SCRIPTS.plotRosterExport });
    const result = page.helper('plotRosterExport').checkExportScreen();
    assert.deepEqual(failedChecks(result), ['exportScreen.taskButton.unique', 'exportScreen.taskButton.clickable']);
});
```

実行は `npm test`、または `pwsh -File tools/Invoke-Tests.ps1 -Suite Js` です。詳しくは [testing.md](testing.md) を参照してください。

## この文書を更新するとき

- 契約の考え方、ページスクリプトの書き方、テストの補助関数が変わったとき
