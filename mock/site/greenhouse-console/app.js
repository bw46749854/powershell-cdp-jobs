/*
 * モック画面「温室コンソール」の動き。
 *
 *   - 区画一覧は仮想スクロール（表示範囲の前後だけを描画する）。左固定ペインと通常ペインの両方に同じ区画の行を描く
 *   - 行のチェックボックスで区画を選択する。選択は両ペインに反映し、「土壌分析を依頼」の有効・無効を切り替える
 *   - 「操作」→「CSV出力」で、表示中のグループ・絞り込みに一致する区画を CSV でダウンロードする
 *   - 「土壌分析を依頼」は押しても何も送信しない（通知を出すだけ）
 *
 * 自動化の確認用に window.mockConsole を公開する（E2E テストが結果の確認に使う。ジョブは使わない）。
 */
(function () {
    'use strict';

    const ROW_HEIGHT = 36;
    const OVERSCAN = 4;
    const PINNED_COLUMNS = ['区画コード'];
    const MAIN_COLUMNS = ['区画コード', '担当者', '稼働状態', '最終計測日時', '土壌分析の依頼', '土壌分析の完了', '作物', '制御器Ver.'];
    const WIDE_COLUMNS = ['最終計測日時', '土壌分析の依頼', '土壌分析の完了'];
    const GROUPS = [
        { id: 'all', name: '全区画（既定）', house: null },
        { id: 'gh1', name: '第1温室', house: '第1温室' },
        { id: 'gh2', name: '第2温室', house: '第2温室' },
        { id: 'gh3', name: '第3温室', house: '第3温室' }
    ];

    const plots = MockData.greenhousePlots();
    const state = { group: GROUPS[0], filter: '', requestClicks: 0 };

    const scroller = document.getElementById('table-scroll');
    const panes = [
        { element: document.getElementById('pane-pinned'), columns: PINNED_COLUMNS, cache: new Map() },
        { element: document.getElementById('pane-main'), columns: MAIN_COLUMNS, cache: new Map() }
    ];

    function valueOf(plot, column) {
        switch (column) {
            case '区画コード': return plot.code;
            case '担当者': return plot.owner;
            case '稼働状態': return plot.status;
            case '最終計測日時': return plot.measured;
            case '土壌分析の依頼': return plot.requested;
            case '土壌分析の完了': return plot.completed;
            case '作物': return plot.crop;
            case '制御器Ver.': return plot.version;
            default: return '';
        }
    }

    function viewRows() {
        const filter = state.filter.trim().toUpperCase();
        return plots.filter(plot => (!state.group.house || plot.house === state.group.house) && (!filter || plot.code.toUpperCase().indexOf(filter) >= 0));
    }

    function cell(role, content, extraClass) {
        const element = document.createElement('div');
        element.setAttribute('role', role);
        element.className = 'gc-cell' + (extraClass ? ' ' + extraClass : '');
        if (content instanceof Node) element.appendChild(content); else element.textContent = content;
        return element;
    }

    function checkbox(label) {
        const wrapper = document.createElement('label');
        wrapper.className = 'gc-check';
        const input = document.createElement('input');
        input.type = 'checkbox';
        input.setAttribute('aria-label', label);
        wrapper.appendChild(input);
        return wrapper;
    }

    function headerRow(columns) {
        const row = document.createElement('div');
        row.setAttribute('role', 'row');
        row.className = 'gc-row gc-row--head';
        const selectAll = checkbox('すべて選択');
        selectAll.querySelector('input').dataset.selectAll = 'true';
        row.appendChild(cell('columnheader', selectAll, 'gc-cell--select'));
        for (const column of columns) row.appendChild(cell('columnheader', column, WIDE_COLUMNS.indexOf(column) >= 0 ? 'gc-cell--wide' : ''));
        return row;
    }

    function createRow(columns) {
        return function (plot) {
            const row = document.createElement('div');
            row.setAttribute('role', 'row');
            row.className = 'gc-row';
            row.setAttribute('data-row-id', plot.id);
            row.appendChild(cell('gridcell', checkbox(plot.code + ' を選択'), 'gc-cell--select'));
            for (const column of columns) row.appendChild(cell('gridcell', valueOf(plot, column), WIDE_COLUMNS.indexOf(column) >= 0 ? 'gc-cell--wide' : ''));
            return row;
        };
    }

    function updateRow(row, plot) {
        row.setAttribute('aria-selected', String(plot.selected));
        row.querySelector('input[type="checkbox"]').checked = plot.selected;
    }

    function spacer() {
        const element = document.createElement('div');
        element.className = 'gc-spacer';
        return element;
    }

    for (const pane of panes) {
        pane.element.appendChild(headerRow(pane.columns));
        pane.top = spacer();
        pane.bottom = spacer();
        pane.element.appendChild(pane.top);
        pane.element.appendChild(pane.bottom);
    }

    function renderRows() {
        const rows = viewRows();
        const range = MockKit.windowFor(scroller.scrollTop, scroller.clientHeight - ROW_HEIGHT, ROW_HEIGHT, rows.length, OVERSCAN);
        const slice = rows.slice(range.start, range.end);
        for (const pane of panes) {
            pane.top.style.height = (range.start * ROW_HEIGHT) + 'px';
            pane.bottom.style.height = ((rows.length - range.end) * ROW_HEIGHT) + 'px';
            MockKit.renderKeyed(pane.element, slice, pane.cache, createRow(pane.columns), updateRow, pane.top, pane.bottom);
        }
    }

    function renderSelectionState() {
        const selected = plots.filter(plot => plot.selected).length;
        document.getElementById('selected-count').textContent = String(selected);
        for (const command of ['request-analysis', 'cancel-analysis']) {
            const item = document.querySelector('[data-command="' + command + '"]');
            if (selected > 0) item.removeAttribute('aria-disabled'); else item.setAttribute('aria-disabled', 'true');
        }
        const rows = viewRows();
        for (const input of document.querySelectorAll('input[data-select-all]')) {
            input.checked = rows.length > 0 && rows.every(plot => plot.selected);
        }
    }

    function renderGroups() {
        const tree = document.getElementById('group-tree');
        tree.textContent = '';
        for (const group of GROUPS) {
            const item = document.createElement('li');
            item.setAttribute('role', 'treeitem');
            item.setAttribute('aria-selected', String(group === state.group));
            item.dataset.group = group.id;
            const label = document.createElement('span');
            label.textContent = group.name;
            item.appendChild(label);
            tree.appendChild(item);
        }
        document.title = '区画一覧 - ' + state.group.name + ' | 温室コンソール';
        document.getElementById('page-title').textContent = state.group.name;
    }

    function renderAll() {
        renderGroups();
        document.getElementById('plot-count').textContent = '区画: ' + viewRows().length;
        renderRows();
        renderSelectionState();
    }

    function setSelected(plotId, selected) {
        const plot = plots.find(item => item.id === plotId);
        if (!plot) return;
        plot.selected = selected;
        for (const pane of panes) {
            const row = pane.cache.get(plotId);
            if (row) updateRow(row, plot);
        }
    }

    function closeMenus(except) {
        for (const button of document.querySelectorAll('[aria-haspopup="menu"]')) {
            const menu = document.getElementById(button.getAttribute('aria-controls'));
            if (menu === except) continue;
            menu.setAttribute('hidden', '');
            button.setAttribute('aria-expanded', 'false');
        }
    }

    function exportCsv() {
        const rows = viewRows().map(plot => {
            const record = {};
            for (const column of MAIN_COLUMNS) record[column] = valueOf(plot, column);
            return record;
        });
        MockKit.download('plots_' + MockData.stamp(new Date()) + '.csv', MockKit.toCsv(MAIN_COLUMNS, rows));
        MockKit.notify('区画一覧の CSV を出力しました（' + rows.length + ' 件）。');
    }

    document.addEventListener('click', event => {
        const button = event.target.closest('[aria-haspopup="menu"]');
        if (button) {
            const menu = document.getElementById(button.getAttribute('aria-controls'));
            const open = menu.hasAttribute('hidden');
            closeMenus(menu);
            menu.toggleAttribute('hidden', !open);
            button.setAttribute('aria-expanded', String(open));
            return;
        }

        const item = event.target.closest('[role="menuitem"]');
        if (item) {
            if (item.getAttribute('aria-disabled') === 'true') return;
            closeMenus(null);
            const command = item.dataset.command;
            if (command === 'export') exportCsv();
            else if (command === 'request-analysis') {
                state.requestClicks++;
                MockKit.notify('モック: 土壌分析の依頼は送信されません。');
            }
            else if (command === 'cancel-analysis') MockKit.notify('モック: 依頼の取り消しは送信されません。');
            return;
        }

        const group = event.target.closest('[role="treeitem"]');
        if (group) {
            state.group = GROUPS.find(candidate => candidate.id === group.dataset.group) || GROUPS[0];
            scroller.scrollTop = 0;
            renderAll();
            return;
        }

        const nav = event.target.closest('.gc-nav__item');
        if (nav) {
            event.preventDefault();
            if (nav.dataset.nav !== 'plots') MockKit.notify('モックでは「区画」画面だけを用意しています。');
            return;
        }

        if (!event.target.closest('.gc-menu')) closeMenus(null);
    });

    document.addEventListener('change', event => {
        const input = event.target;
        if (!(input instanceof HTMLInputElement) || input.type !== 'checkbox') return;

        if (input.dataset.selectAll) {
            for (const plot of viewRows()) setSelected(plot.id, input.checked);
        }
        else {
            const row = input.closest('[role="row"][data-row-id]');
            if (row) setSelected(row.getAttribute('data-row-id'), input.checked);
        }
        renderSelectionState();
    });

    document.getElementById('plot-search').addEventListener('input', event => {
        state.filter = event.target.value;
        scroller.scrollTop = 0;
        renderAll();
    });

    scroller.addEventListener('scroll', renderRows);
    window.addEventListener('resize', renderRows);

    window.mockConsole = {
        selectedPlotCodes() {
            return plots.filter(plot => plot.selected).map(plot => plot.code).sort();
        },
        plotCount() {
            return plots.length;
        },
        requestClicks() {
            return state.requestClicks;
        }
    };

    renderAll();
})();
