# pagekit — ページスクリプトの核

ページへ注入する JavaScript の共通部品です（[app/browser/kernel/pagekit.js](../../app/browser/kernel/pagekit.js)）。注入すると `window.__pagekit` ができ、画面・機能ごとの部品（part）を組み合わせてヘルパー（helper）を作ります。PowerShell 側は、操作カタログに従ってヘルパーのメソッドを呼びます（[PageBridge.md](../modules/PageBridge.md)）。

ここに置くのは「どの画面でも同じ意味を持つ」規則だけです。画面固有の名前・目印は部品に書きます。

## 1. 組み立て方

```text
kernel/pagekit.js                        window.__pagekit を作る（注入のたびに作り直す）
screens/greenhouse-plot-list.js          kit.part('screen.greenhousePlotList', factory)
features/plot-roster-export.js           kit.part('feature.plotRosterExport', factory)
                                         kit.define('plotRosterExport', ['screen.greenhousePlotList', 'feature.plotRosterExport'])
（PowerShell が最後に評価）              __pagekit.ack('plotRosterExport') → { ok, helper, kernelVersion, methods }
```

| API | 内容 |
|---|---|
| `kit.part(name, factory)` | 部品を登録する。`factory(kit)` はメソッドを持つオブジェクトを返す |
| `kit.define(helperName, partNames)` | 部品のメソッドを1つのヘルパーにまとめて `kit.helpers[helperName]` に置く。読み込まれていない部品があれば `[pagekit:part-missing]`、同じ名前のメソッドが2つの部品にあればエラー |
| `kit.ack(helperName)` | ヘルパーが持つメソッド名の一覧（PowerShell がカタログと照合する） |

部品のメソッドの中の `this` はヘルパーです。別の部品のメソッドも `this.<メソッド>` で呼べます（例: 機能の部品が画面の部品の `screenIdentityChecks` を使う）。メソッド以外の状態（`_scope` など）も持てますが、注入し直すと消えます。

## 2. 共通部品

### text — 文字列

| 関数 | 内容 |
|---|---|
| `text.norm(value)` | 空白・全角空白・NBSP・改行を1つの空白にまとめて前後を除く |
| `text.of(element)` | 要素の `textContent` を `norm` したもの |
| `text.attr(element, name)` | 属性の値を `norm` したもの（無ければ空文字） |
| `text.nameOf(element)` | 表示名: `aria-label` → 文字列 → `title` の順 |
| `text.clip(value)` | 診断用に長い文字列を切る |

### view — 状態

| 関数 | 内容 |
|---|---|
| `view.isVisible(element)` | 文書に接続され、大きさがあり、`display:none` / `visibility:hidden` / `opacity:0` でない |
| `view.isDisabled(element)` | `disabled`、祖先の `aria-disabled="true"`、無効な `fieldset` の中 |
| `view.isClickable(element)` | 見えていて無効でない |

CSS クラス名は見ません（構造であり、契約ではないため）。

### locate — 探す

| 関数 | 内容 |
|---|---|
| `locate.all(root, selector)` | `querySelectorAll` の配列 |
| `locate.byName(root, selector, name)` | 表示名（`nameOf`）が一致する要素 |
| `locate.visibleOnly(elements)` | 見えている要素だけ |
| `locate.distinct(elements)` | 重複を除く |
| `locate.unique(candidates)` | **ちょうど1つ**かを判定する。`{ ok, element, count, reason: unique / none / ambiguous, candidates }` |
| `locate.closestScrollable(element)` | 一番近い、スクロールできる祖先（無ければ文書） |

業務上の対象は必ず `unique` で1つに決め、`ok` でなければ契約違反・失敗にします。**候補の先頭を使うような書き方はしません。** `candidates` には `describe` の要約（タグ・id・クラス・role・名前・表示・無効）が入り、エラーの `details` として PowerShell のログに出ます。

### contract — 契約結果

```js
const checks = [
    contract.check('exportScreen.taskButton.unique', button.ok, 'fatal', '「操作」ボタンがちょうど1つあること', button),
    contract.check('postSelection.selectedRows.visible', visible > 0, 'warning', '…', { visible })
];
return contract.result('plotRosterExport.exportScreen', checks, { plotCount });
```

| 関数 | 内容 |
|---|---|
| `contract.check(name, ok, severity, message, details)` | 条件1つ。`severity` は `fatal`（既定）か `warning` |
| `contract.result(scope, checks, details)` | `{ scope, ok, fatalCount, warningCount, checks, details }`。`ok` は fatal が0件のとき `true` |
| `contract.assertNoFatal(result)` | fatal があれば例外（操作の直前にもう一度確かめるときに使う） |

`details` は PowerShell へ返せる形に整えられます（DOM 要素は `describe` の要約に、関数は除く、循環参照と深さを制限）。`scope` は操作カタログの `Scope` と一致する必要があります。

### act / scroll — 操作

| 関数 | 内容 |
|---|---|
| `act.click(element)` | 要素を中央に表示し、pointer / mouse の各イベントを送ってから `click()` する（実際の操作に近い順序） |
| `act.sleep(ms)` | Promise で待つ（メソッドを `async` にして `await` する。PowerShell は Promise の解決まで待つ） |
| `scroll.getTop` / `setTop` / `scrollBy` / `pageAmount` | スクロール位置の読み書き。`setTop` は `scroll` イベントを送る（仮想スクロールの再描画を促す） |

## 3. 部品の書き方の約束

1. **冒頭コメント**に「部品名」「契約（意味）」「吸収する構造の違い」を書く（テストで検査）。ヘルパーを登録する部品は「ヘルパー名」と対応する操作カタログも書く。
2. **名前・文言は先頭の定数**にまとめる（`const TASK_BUTTON_NAME = '操作'`）。画面の文言が変わったときに直す場所を1つにする。
3. **意味から探す**: 役割（`role`）・名前・状態（`aria-*`）・画面が用意した目印（`data-*`）で探す。タグや CSS クラス、要素の位置・順番に依存しない。
4. **ちょうど1つ**に決める。決まらなければ契約違反（`fatal`）にし、`details` に候補を載せる。
5. **確認と操作を分ける**: 確認（Contract）は状態を変えない。操作（Action）は1つのことだけをし、結果を `{ ok, action, … }` で返す。操作の前に必要な確認は、操作の中でもう一度行う（`contract.assertNoFatal`）。
6. **失敗の理由は機械的に読める語**で返す（`{ ok: false, reason: 'plot_not_visible', … }`）。PowerShell 側はそれを失敗の記録に載せる。
7. **外へ送らない**: `fetch`・`XMLHttpRequest`・`WebSocket`・`localStorage` などを使わない。`eval` もしない（テストで検査）。
8. **してはいけない操作は書かない**: 例えば「土壌分析を依頼」をクリックするメソッドは作らない。存在しない操作は呼び出せない。

## 4. PowerShell との約束

- ヘルパーのメソッドは JSON にできる値を返す（DOM 要素は返さない）。Promise を返してよい。
- 操作カタログの `Kind` に応じて、ヘルパーが無いときの扱いが変わる（[PageBridge.md](../modules/PageBridge.md#操作カタログ)）。メソッドの中で `[pagekit:helper-missing]` の目印付きの例外を投げると、PowerShell は「続行不能」として扱う。
- `Identity` の操作は副作用を持たない（すべてのタブで実行されるため）。

## 5. 部品を読む順番

1. **冒頭コメント**: 部品名・ヘルパー名・契約（意味）・吸収する構造の違い。ここで「何を厳格に確かめ、何を吸収するか」が分かります。
2. **先頭の定数**: 画面の文言（ボタン名・見出し・製品名）。画面が変わったときに直すのはまずここです。
3. **`resolve…` / `read…` のメソッド**: 要素を探して `locate.unique` の結果を返す部分。探し方（role・名前・`data-*`）がここにあります。
4. **`check…` のメソッド（Contract）**: `contract.check` を並べて `contract.result` を返します。条件名（`exportScreen.taskButton.unique` など）はログ・テストと共通の名前です。
5. **操作のメソッド（Action）**: 直前に契約を確かめ直してから操作し、結果を返します。

メソッドが返す値の形:

| 種類 | 形 |
|---|---|
| 要素を探した結果 | `{ ok, element, count, reason: unique / none / ambiguous, candidates }`（`element` はページの中だけで使い、PowerShell へは返さない） |
| 契約結果（Contract / Identity） | `{ scope, ok, fatalCount, warningCount, checks: [{ name, ok, severity, message, details }], details }` |
| 操作の結果（Action） | `{ ok: true, action: '<したこと>', … }`、失敗は `{ ok: false, reason: '<機械的に読める語>', … }` |
| 読み取り（Query） | 行の配列など、JSON にできる値 |
| 待機の条件（Probe） | `true` / `false` |

## この文書を更新するとき

- kernel の API、部品の組み立て方、部品の書き方の約束が変わったとき
