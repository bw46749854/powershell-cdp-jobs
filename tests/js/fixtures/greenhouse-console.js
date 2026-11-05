'use strict';

// 温室コンソール「区画」一覧の静的な DOM（モック画面 mock/site/greenhouse-console と同じ契約要素）。
// 仮想スクロールなどの動きは持たない。動きは E2E テスト（実ブラウザ + モック画面）で確認する。

const COLUMNS = ['区画コード', '担当者', '稼働状態', '最終計測日時', '土壌分析の依頼', '土壌分析の完了', '作物', '制御器Ver.'];

function plot(index, overrides) {
    const code = 'GH1-A' + String(index + 1).padStart(2, '0');
    return Object.assign({
        id: 'p-' + String(index + 1).padStart(4, '0'),
        code,
        owner: 'staff' + (index + 1),
        status: '稼働中',
        measured: '2026-04-10 08:00:00',
        requested: '-',
        completed: '2026-04-01 09:00:00',
        crop: 'トマト',
        version: '3.2.1',
        selected: false
    }, overrides || {});
}

function selectionCell(role, label, checked) {
    return `<div role="${role}" class="gc-cell"><label class="gc-check"><input type="checkbox" aria-label="${label}"${checked ? ' checked' : ''}></label></div>`;
}

function row(item, columns) {
    const values = { 区画コード: item.code, 担当者: item.owner, 稼働状態: item.status, 最終計測日時: item.measured, '土壌分析の依頼': item.requested, '土壌分析の完了': item.completed, 作物: item.crop, '制御器Ver.': item.version };
    const cells = columns.map(column => `<div role="gridcell" class="gc-cell">${values[column]}</div>`).join('');
    return `<div role="row" class="gc-row" data-row-id="${item.id}" aria-selected="${item.selected}">${selectionCell('gridcell', item.code + ' を選択', item.selected)}${cells}</div>`;
}

function headerRow(columns) {
    const cells = columns.map(column => `<div role="columnheader" class="gc-cell">${column}</div>`).join('');
    return `<div role="row" class="gc-row gc-row--head">${selectionCell('columnheader', 'すべて選択', false)}${cells}</div>`;
}

function greenhouseConsoleHtml(options) {
    const settings = Object.assign({ plots: [plot(0), plot(1), plot(2)], count: null, title: '区画一覧 - 全区画（既定） | 温室コンソール' }, options || {});
    const count = settings.count === null ? settings.plots.length : settings.count;
    const pinnedColumns = ['区画コード'];

    return `<!doctype html>
<html lang="ja"><head><title>${settings.title}</title></head>
<body>
<div class="gc-app" data-app="greenhouse-console">
  <header class="gc-header" role="banner"><span class="gc-brand">温室コンソール</span></header>
  <nav class="gc-nav" aria-label="メインメニュー">
    <a href="#" class="gc-nav__item" data-nav="dashboard">ダッシュボード</a>
    <a href="#" class="gc-nav__item is-current" data-nav="plots" aria-current="page">区画</a>
    <a href="#" class="gc-nav__item" data-nav="records">記録</a>
  </nav>
  <aside class="gc-groups">
    <ul role="tree" aria-label="区画グループ">
      <li role="treeitem" aria-selected="true" data-group="all"><span>全区画（既定）</span></li>
      <li role="treeitem" aria-selected="false" data-group="house-1"><span>第1温室</span></li>
    </ul>
  </aside>
  <main class="gc-main">
    <h1>全区画（既定）</h1>
    <div class="gc-toolbar" role="toolbar">
      <div class="gc-menu" data-menu="actions">
        <button type="button" class="gc-button" aria-haspopup="menu" aria-expanded="false" aria-controls="menu-actions">操作</button>
        <div id="menu-actions" class="gc-menu__list" role="menu" hidden>
          <div class="gc-menu__wrap"><div role="menuitem" data-command="export">CSV出力</div></div>
          <div class="gc-menu__wrap"><div role="menuitem" data-command="move">グループへ移動</div></div>
        </div>
      </div>
      <div class="gc-menu" data-menu="analysis">
        <button type="button" class="gc-button" aria-haspopup="menu" aria-expanded="false" aria-controls="menu-analysis">分析</button>
        <div id="menu-analysis" class="gc-menu__list" role="menu" hidden>
          <div role="group" aria-label="選択区画">
            <div role="menuitem" data-command="request-analysis" aria-disabled="true">土壌分析を依頼</div>
            <div role="menuitem" data-command="cancel-analysis" aria-disabled="true">依頼を取り消す</div>
          </div>
        </div>
      </div>
      <input type="search" id="plot-search" aria-label="区画コードで絞り込み" placeholder="区画コードで絞り込み">
      <span class="gc-count" data-count="plots">区画: ${count}</span>
    </div>
    <div class="gc-table" role="grid" aria-label="区画一覧">
      <div class="gc-table__scroll">
        <div class="gc-pane gc-pane--pinned" role="rowgroup" data-pinned="start">
          ${headerRow(pinnedColumns)}
          ${settings.plots.map(item => row(item, pinnedColumns)).join('\n          ')}
        </div>
        <div class="gc-pane" role="rowgroup">
          ${headerRow(COLUMNS)}
          ${settings.plots.map(item => row(item, COLUMNS)).join('\n          ')}
        </div>
      </div>
    </div>
  </main>
</div>
</body></html>`;
}

// メニューボタンの開閉（モック画面の app.js と同じ振る舞いの最小版）。
function wireMenus(window) {
    for (const button of window.document.querySelectorAll('[aria-haspopup="menu"]')) {
        button.addEventListener('click', () => {
            const menu = window.document.getElementById(button.getAttribute('aria-controls'));
            const open = menu.hasAttribute('hidden');
            menu.toggleAttribute('hidden', !open);
            button.setAttribute('aria-expanded', String(open));
        });
    }
}

// チェックボックスの変更を、同じ区画の行（固定列側・通常列側の両方）へ反映する。
function wireSelection(window) {
    window.document.addEventListener('change', event => {
        const input = event.target;
        const rowElement = input.closest('[role="row"][data-row-id]');
        if (!rowElement) return;
        const id = rowElement.getAttribute('data-row-id');
        for (const sibling of window.document.querySelectorAll(`[role="row"][data-row-id="${id}"]`)) {
            sibling.setAttribute('aria-selected', String(input.checked));
            sibling.querySelector('input[type="checkbox"]').checked = input.checked;
        }
        const anySelected = window.document.querySelectorAll('[role="row"][data-row-id][aria-selected="true"]').length > 0;
        const request = window.document.querySelector('[data-command="request-analysis"]');
        if (anySelected) request.removeAttribute('aria-disabled'); else request.setAttribute('aria-disabled', 'true');
    });
}

module.exports = { COLUMNS, plot, greenhouseConsoleHtml, wireMenus, wireSelection };
