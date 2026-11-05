/*
 * モック画面「作付け台帳」の動き。
 *
 *   - 区画一覧は「固定列側」「通常列側」の2つの表で、仮想スクロール（表示範囲の前後だけを描画する）
 *   - 区画コードのリンクで行を選択し、区画詳細（右側のパネル）を開く。詳細の中身は少し遅れて表示される
 *   - 区画詳細の「作付け記録」タブの「CSV出力」で、その区画の作付け記録を planting_<実行日>.csv でダウンロードする
 */
(function () {
    'use strict';

    const ROW_HEIGHT = 36;
    const OVERSCAN = 3;
    const DETAIL_DELAY_MS = 250;

    const plots = MockData.ledgerPlots();
    const state = { codeSide: 'fixed', selectedId: null, detailId: null, detailTimer: null };

    const scroller = document.getElementById('grid-scroll');
    const drawer = document.querySelector('[role="dialog"]');
    const bodies = {
        fixed: { element: document.getElementById('body-fixed'), cache: new Map() },
        main: { element: document.getElementById('body-main'), cache: new Map() }
    };

    function element(tag, attributes, content) {
        const created = document.createElement(tag);
        for (const name of Object.keys(attributes || {})) created.setAttribute(name, attributes[name]);
        if (content instanceof Node) created.appendChild(content);
        else if (content !== undefined) created.textContent = content;
        return created;
    }

    function codeLink(plot) {
        return element('a', { href: '#', class: 'pl-link' }, plot.code);
    }

    function fixedColumns() {
        return state.codeSide === 'fixed' ? ['select', 'code'] : ['select'];
    }

    function mainColumns() {
        return (state.codeSide === 'main' ? ['code'] : []).concat(['house', 'owner', 'area', 'count']);
    }

    const HEADERS = {
        select: () => element('th', { id: 'plots-col-select', scope: 'col' }, element('input', { type: 'checkbox', 'aria-label': 'すべて選択' })),
        code: () => element('th', { id: 'plots-col-code', scope: 'col' }, '区画コード'),
        house: () => element('th', { id: 'plots-col-house', scope: 'col' }, '温室'),
        owner: () => element('th', { id: 'plots-col-owner', scope: 'col' }, '担当者'),
        area: () => element('th', { id: 'plots-col-area', scope: 'col' }, '面積'),
        count: () => element('th', { id: 'plots-col-count', scope: 'col' }, '記録数')
    };

    const CELLS = {
        select: () => element('td', { headers: 'plots-col-select' }, element('input', { type: 'checkbox', 'aria-label': '選択' })),
        code: plot => element('td', { headers: 'plots-col-code' }, codeLink(plot)),
        house: plot => element('td', { headers: 'plots-col-house' }, plot.house),
        owner: plot => element('td', { headers: 'plots-col-owner' }, plot.owner),
        area: plot => element('td', { headers: 'plots-col-area' }, plot.area),
        count: plot => element('td', { headers: 'plots-col-count' }, String(plot.records.length))
    };

    function renderHeads() {
        for (const [id, columns] of [['head-fixed', fixedColumns()], ['head-main', mainColumns()]]) {
            const row = document.getElementById(id);
            row.textContent = '';
            for (const column of columns) row.appendChild(HEADERS[column]());
        }
    }

    function spacerRow(columnCount) {
        const row = element('tr', { class: 'pl-spacer', 'aria-hidden': 'true' });
        row.appendChild(element('td', { colspan: String(columnCount) }));
        return row;
    }

    function resetBodies() {
        for (const [side, body] of Object.entries(bodies)) {
            const columnCount = (side === 'fixed' ? fixedColumns() : mainColumns()).length;
            body.element.textContent = '';
            body.cache.clear();
            body.top = spacerRow(columnCount);
            body.bottom = spacerRow(columnCount);
            body.element.appendChild(body.top);
            body.element.appendChild(body.bottom);
        }
    }

    function createRow(columns) {
        return function (plot) {
            const row = element('tr', { 'data-row-id': plot.id });
            for (const column of columns) row.appendChild(CELLS[column](plot));
            return row;
        };
    }

    function updateRow(row, plot) {
        row.setAttribute('aria-selected', String(plot.id === state.selectedId));
    }

    function renderRows() {
        const range = MockKit.windowFor(scroller.scrollTop, scroller.clientHeight, ROW_HEIGHT, plots.length, OVERSCAN);
        const slice = plots.slice(range.start, range.end);
        for (const [side, body] of Object.entries(bodies)) {
            body.top.firstChild.style.height = (range.start * ROW_HEIGHT) + 'px';
            body.bottom.firstChild.style.height = ((plots.length - range.end) * ROW_HEIGHT) + 'px';
            body.top.style.display = range.start > 0 ? '' : 'none';
            body.bottom.style.display = range.end < plots.length ? '' : 'none';
            MockKit.renderKeyed(body.element, slice, body.cache, createRow(side === 'fixed' ? fixedColumns() : mainColumns()), updateRow, body.top, body.bottom);
        }
    }

    function renderAll() {
        document.getElementById('plot-total').textContent = String(plots.length);
        renderHeads();
        resetBodies();
        renderRows();
    }

    function showTab(tabId) {
        for (const tab of drawer.querySelectorAll('[role="tab"]')) {
            const active = tab.id === tabId;
            tab.setAttribute('aria-selected', String(active));
            document.getElementById(tab.getAttribute('aria-controls')).toggleAttribute('hidden', !active);
        }
    }

    function openDetail(plot) {
        state.selectedId = plot.id;
        for (const body of Object.values(bodies)) {
            for (const [id, row] of body.cache) row.setAttribute('aria-selected', String(id === plot.id));
        }

        clearTimeout(state.detailTimer);
        state.detailId = null;
        drawer.querySelector('[data-bind="detail.plotCode"]').textContent = '';
        document.getElementById('detail-meta').textContent = '読み込み中…';
        document.getElementById('records-body').textContent = '';
        showTab('tab-summary');
        drawer.removeAttribute('hidden');

        // 実際の画面と同じく、詳細の中身は少し遅れて表示される（ジョブは区画コードが一致するまで待つ）
        state.detailTimer = setTimeout(() => {
            state.detailId = plot.id;
            drawer.querySelector('[data-bind="detail.plotCode"]').textContent = plot.code;
            document.getElementById('detail-meta').textContent = plot.house + ' / 担当: ' + plot.owner + ' / ' + plot.area;
            document.getElementById('panel-summary').textContent = '作付け記録 ' + plot.records.length + ' 件';
            const tbody = document.getElementById('records-body');
            for (const record of plot.records) {
                const row = element('tr');
                for (const value of [record.crop, record.variety, record.planted]) row.appendChild(element('td', {}, value));
                tbody.appendChild(row);
            }
        }, DETAIL_DELAY_MS);
    }

    function exportPlanting() {
        const plot = plots.find(item => item.id === state.detailId);
        if (!plot) {
            MockKit.notify('区画詳細を読み込み中です。');
            return;
        }
        const columns = ['作物名', '品種', '定植日'];
        const rows = plot.records.map(record => ({ 作物名: record.crop, 品種: record.variety, 定植日: record.planted }));
        MockKit.download('planting_' + MockData.stamp(new Date()) + '.csv', MockKit.toCsv(columns, rows));
        MockKit.notify(plot.code + ' の作付け記録を出力しました（' + rows.length + ' 件）。');
    }

    document.addEventListener('click', event => {
        const link = event.target.closest('.pl-link');
        if (link) {
            event.preventDefault();
            const row = link.closest('tr[data-row-id]');
            const plot = plots.find(item => item.id === row.getAttribute('data-row-id'));
            if (plot) openDetail(plot);
            return;
        }

        const tab = event.target.closest('[role="tab"]');
        if (tab) {
            showTab(tab.id);
            return;
        }

        if (event.target.closest('.pl-close')) {
            clearTimeout(state.detailTimer);
            drawer.setAttribute('hidden', '');
            return;
        }

        if (event.target.closest('[data-export="planting"] button')) {
            exportPlanting();
        }
    });

    document.getElementById('code-side').addEventListener('change', event => {
        state.codeSide = event.target.value === 'main' ? 'main' : 'fixed';
        renderAll();
    });

    scroller.addEventListener('scroll', renderRows);
    window.addEventListener('resize', renderRows);

    renderAll();
})();
