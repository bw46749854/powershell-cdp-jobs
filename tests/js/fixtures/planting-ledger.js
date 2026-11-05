'use strict';

// 作付け台帳「区画一覧」の静的な DOM（モック画面 mock/site/planting-ledger と同じ契約要素）。
// 行のクリック・タブ・閉じるの最小限の動きは wireLedger で付ける。

function ledgerPlot(index, overrides) {
    return Object.assign({
        id: 'r-' + String(index + 1).padStart(2, '0'),
        code: 'GH2-B' + String(index + 1).padStart(2, '0'),
        house: '第2温室',
        owner: 'staff' + (index + 1),
        records: [
            { crop: 'トマト', variety: '桃太郎', planted: '2026-03-12' },
            { crop: 'レタス', variety: 'シスコ', planted: '2026-02-03' }
        ]
    }, overrides || {});
}

function plantingLedgerHtml(options) {
    const settings = Object.assign({ plots: [ledgerPlot(0), ledgerPlot(1)], view: 'plot-list', codeSide: 'fixed', title: '区画一覧 | 作付け台帳' }, options || {});
    const codeHeader = '<th id="plots-col-code" scope="col">区画コード</th>';
    const fixedHeaders = '<th id="plots-col-select" scope="col"><input type="checkbox" aria-label="すべて選択"></th>' + (settings.codeSide === 'fixed' ? codeHeader : '');
    const mainHeaders = (settings.codeSide === 'main' ? codeHeader : '') + '<th id="plots-col-house">温室</th><th id="plots-col-owner">担当者</th>';

    const codeCell = item => `<td headers="plots-col-code"><a href="#" class="pl-link">${item.code}</a></td>`;
    const fixedRows = settings.plots.map(item => `<tr data-row-id="${item.id}" aria-selected="false"><td headers="plots-col-select"><input type="checkbox" aria-label="選択"></td>${settings.codeSide === 'fixed' ? codeCell(item) : ''}</tr>`).join('');
    const mainRows = settings.plots.map(item => `<tr data-row-id="${item.id}" aria-selected="false">${settings.codeSide === 'main' ? codeCell(item) : ''}<td headers="plots-col-house">${item.house}</td><td headers="plots-col-owner">${item.owner}</td></tr>`).join('');

    return `<!doctype html>
<html lang="ja"><head><title>${settings.title}</title></head>
<body>
<header role="banner"><span class="pl-brand">作付け台帳</span></header>
<main id="ledger-view" data-view="${settings.view}">
  <nav aria-label="パンくず"><ol><li>ホーム</li><li>圃場</li><li aria-current="page">区画一覧</li></ol></nav>
  <h1>区画一覧</h1>
  <p class="pl-total">表示件数 <strong data-bind="plotList.total">${settings.plots.length}</strong> 件</p>
  <div class="pl-grid" data-grid="plots">
    <div class="pl-grid__fixed">
      <table><thead><tr>${fixedHeaders}</tr></thead></table>
      <div class="pl-grid__body"><table><tbody class="fixed-body">${fixedRows}</tbody></table></div>
    </div>
    <div class="pl-grid__main">
      <table><thead><tr>${mainHeaders}</tr></thead></table>
      <div class="pl-grid__body"><table><tbody class="main-body">${mainRows}</tbody></table></div>
    </div>
  </div>
</main>
<aside class="pl-drawer" role="dialog" aria-label="区画詳細" hidden>
  <div class="pl-drawer__head"><h2 data-bind="detail.plotCode"></h2><button type="button" class="pl-close" aria-label="閉じる">×</button></div>
  <div role="tablist" aria-label="区画詳細のタブ">
    <button type="button" role="tab" id="tab-summary" aria-selected="true" aria-controls="panel-summary">概要</button>
    <button type="button" role="tab" id="tab-planting" aria-selected="false" aria-controls="panel-planting">作付け記録</button>
  </div>
  <section role="tabpanel" id="panel-summary">概要</section>
  <section role="tabpanel" id="panel-planting" hidden>
    <fieldset><legend>記録の種類</legend>
      <label><input type="radio" name="record-kind" value="planting" checked> 作付け記録</label>
      <label><input type="radio" name="record-kind" value="harvest"> 収穫記録</label>
    </fieldset>
    <table class="pl-records"><thead><tr><th>作物名</th><th>品種</th><th>定植日</th></tr></thead><tbody></tbody></table>
    <div class="pl-export" data-export="planting"><button type="button">CSV出力</button></div>
  </section>
</aside>
</body></html>`;
}

function wireLedger(window, options) {
    const document = window.document;
    const settings = Object.assign({ plots: [ledgerPlot(0), ledgerPlot(1)] }, options || {});
    const drawer = document.querySelector('[role="dialog"]');
    const state = { csvClicks: 0, opened: [] };

    function select(id) {
        for (const row of document.querySelectorAll('tr[data-row-id]')) {
            row.setAttribute('aria-selected', String(row.getAttribute('data-row-id') === id));
        }
    }

    function showTab(name) {
        for (const tab of document.querySelectorAll('[role="tab"]')) {
            const active = tab.textContent.trim() === name;
            tab.setAttribute('aria-selected', String(active));
            document.getElementById(tab.getAttribute('aria-controls')).toggleAttribute('hidden', !active);
        }
    }

    document.addEventListener('click', event => {
        const link = event.target.closest('.pl-link');
        if (link) {
            event.preventDefault();
            const row = link.closest('tr[data-row-id]');
            const item = settings.plots.find(plot => plot.id === row.getAttribute('data-row-id'));
            select(item.id);
            state.opened.push(item.code);
            drawer.querySelector('[data-bind="detail.plotCode"]').textContent = item.code;
            drawer.querySelector('.pl-records tbody').innerHTML = item.records.map(record => `<tr><td>${record.crop}</td><td>${record.variety}</td><td>${record.planted}</td></tr>`).join('');
            showTab('概要');
            drawer.removeAttribute('hidden');
            return;
        }
        const tab = event.target.closest('[role="tab"]');
        if (tab) { showTab(tab.textContent.trim()); return; }
        if (event.target.closest('.pl-close')) { drawer.setAttribute('hidden', ''); return; }
        if (event.target.closest('[data-export="planting"] button')) { state.csvClicks++; }
    });

    return state;
}

module.exports = { ledgerPlot, plantingLedgerHtml, wireLedger };
