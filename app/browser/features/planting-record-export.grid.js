/*
 * 機能: 区画ごとの作付け記録 CSV の取得（PlantingRecordExport）— 区画一覧の表
 * 部品名: feature.plantingRecordExport.grid（screen.ledgerPlotList を前提にする）
 *
 * 一覧は「固定列側」と「通常列側」の2つの表に分かれ、同じ区画の行（data-row-id）が両方に描画される。
 * 区画コードの列がどちら側にあるかは画面の設定で変わり得るため、位置ではなく列見出しで決める。
 *
 * 契約（意味）
 *   - 列見出し「区画コード」がちょうど1つあり、id を持つ（セルは headers 属性でこの id を参照する）
 *   - 選択列の見出しに「すべて選択」のチェックボックスがある（区画一覧の表であることの確認）
 *   - 区画コードのセルを持つ本体（tbody）がちょうど1つに決まる
 * 吸収する構造の違い
 *   - 区画コード列が固定列側・通常列側のどちらにあっても、列見出しから辿る
 *   - セル内のリンク（a / button）の有無
 */
(function (kit) {
    'use strict';

    const CODE_HEADER = '区画コード';

    kit.part('feature.plantingRecordExport.grid', function () {
        const { text, view, locate, contract, act, scroll } = kit;

        return {
            gridRoot() {
                const hooked = locate.all(document, '[data-grid="plots"]');
                return hooked.length === 1 ? hooked[0] : document;
            },

            headerCells() {
                return locate.visibleOnly(locate.all(this.gridRoot(), 'th'));
            },

            resolveCodeColumn() {
                const named = this.headerCells().filter(cell => text.of(cell) === CODE_HEADER || text.attr(cell, 'aria-label') === CODE_HEADER);
                const resolution = locate.unique(named);
                const id = resolution.ok ? resolution.element.id : '';
                return Object.assign(resolution, { ok: resolution.ok && !!id, id, hasId: !!id });
            },

            resolveSelectionHeader() {
                return locate.unique(this.headerCells().filter(cell => !!cell.querySelector('input[type="checkbox"]')));
            },

            codeCellOf(row, column) {
                const cells = Array.from(row.querySelectorAll('td')).filter(cell => text.attr(cell, 'headers').split(' ').indexOf(column.id) >= 0);
                return cells.length === 1 ? cells[0] : null;
            },

            resolveRowScope() {
                const column = this.resolveCodeColumn();
                if (!column.ok) return { ok: false, reason: 'code_column_not_resolved', column, scopes: [] };

                const rows = locate.visibleOnly(locate.all(this.gridRoot(), 'tr[data-row-id]'));
                const bodies = locate.distinct(rows.map(row => row.closest('tbody') || row.parentElement));
                const scopes = bodies.map((body, index) => {
                    const bodyRows = rows.filter(row => (row.closest('tbody') || row.parentElement) === body);
                    const withCell = bodyRows.filter(row => !!this.codeCellOf(row, column));
                    const withCode = withCell.filter(row => !!text.of(this.codeCellOf(row, column)));
                    return {
                        name: 'body#' + index,
                        body,
                        rows: bodyRows,
                        valid: bodyRows.length > 0 && withCell.length === bodyRows.length && withCode.length === bodyRows.length,
                        summary: { name: 'body#' + index, rowCount: bodyRows.length, withCodeCell: withCell.length, withCode: withCode.length }
                    };
                });
                const valid = scopes.filter(scope => scope.valid);
                return {
                    ok: valid.length === 1,
                    reason: valid.length === 1 ? 'single_body_with_code_column' : (valid.length === 0 ? 'no_body_with_code_column' : 'multiple_bodies_with_code_column'),
                    column,
                    scope: valid.length === 1 ? valid[0] : null,
                    scopes: scopes.map(scope => scope.summary)
                };
            },

            rowInfo(row, column, index) {
                return {
                    rowId: text.attr(row, 'data-row-id'),
                    plotCode: text.of(this.codeCellOf(row, column)),
                    index,
                    selected: text.attr(row, 'aria-selected') === 'true'
                };
            },

            requireRowScope() {
                const resolution = this.resolveRowScope();
                if (!resolution.ok) throw new Error('区画一覧の行を読む範囲を決められません。理由=' + resolution.reason);
                return resolution;
            },

            readVisibleRows() {
                const resolution = this.requireRowScope();
                return resolution.scope.rows.map((row, index) => this.rowInfo(row, resolution.column, index));
            },

            readSelectedRow() {
                const resolution = this.requireRowScope();
                const selected = resolution.scope.rows.filter(row => text.attr(row, 'aria-selected') === 'true');
                if (selected.length !== 1) return { ok: false, count: selected.length };
                return Object.assign({ ok: true, count: 1 }, this.rowInfo(selected[0], resolution.column, 0));
            },

            checkScreen() {
                const checks = this.ledgerIdentityChecks('screen');
                checks.push(contract.check('screen.grid.headers', this.headerCells().length > 0, 'fatal',
                    '区画一覧の表の見出しが表示されていること', { headerCount: this.headerCells().length }));
                return contract.result('plantingExport.screen', checks, { title: document.title });
            },

            checkList() {
                const selection = this.resolveSelectionHeader();
                const resolution = this.resolveRowScope();
                const infos = resolution.ok ? resolution.scope.rows.map((row, index) => this.rowInfo(row, resolution.column, index)) : [];
                const keys = infos.map(info => info.rowId + '|' + info.plotCode);
                const duplicates = Array.from(new Set(keys.filter((key, index) => keys.indexOf(key) !== index)));
                const total = this.readTotalCount();
                const scroller = resolution.ok ? locate.closestScrollable(resolution.scope.body) : null;

                const checks = [
                    contract.check('list.selectionHeader.unique', selection.ok, 'fatal',
                        '選択列の見出し（すべて選択のチェックボックス）がちょうど1つあること', selection),
                    contract.check('list.codeColumn.unique', resolution.column.ok, 'fatal',
                        '列見出し「' + CODE_HEADER + '」がちょうど1つあり、セルと対応付ける id を持つこと', resolution.column),
                    contract.check('list.rowScope.unique', resolution.ok, 'fatal',
                        '区画コードのセルを持つ表の本体がちょうど1つに決まること（固定列側・通常列側を推測で選ばない）', { reason: resolution.reason, scopes: resolution.scopes }),
                    contract.check('list.rows.exist', infos.length > 0, 'fatal', '区画の行が表示されていること', { rowCount: infos.length }),
                    contract.check('list.rows.rowId', infos.length > 0 && infos.every(info => info.rowId), 'fatal',
                        'すべての行が行識別子（data-row-id）を持つこと', { rows: infos.slice(0, 20) }),
                    contract.check('list.rows.identity.unique', duplicates.length === 0, 'fatal',
                        '表示中の行で「行識別子 + 区画コード」が重複していないこと', { duplicates }),
                    contract.check('list.total.readable', total !== null, 'fatal',
                        '件数表示から一覧の件数を読めること（件数が分からないまま走査を終えない）', { total }),
                    contract.check('list.scroller.found', !!scroller, 'fatal',
                        '一覧をスクロールする領域を決められること', { scroller: kit.describe(scroller) })
                ];

                return contract.result('plantingExport.list', checks, { total, rowCount: infos.length, codeColumnId: resolution.column.id });
            },

            resolveRow(rowId, plotCode) {
                const resolution = this.requireRowScope();
                const rows = resolution.scope.rows.filter(row => text.attr(row, 'data-row-id') === rowId && text.of(this.codeCellOf(row, resolution.column)) === plotCode);
                const row = rows.length === 1 ? rows[0] : null;
                const cell = row ? this.codeCellOf(row, resolution.column) : null;
                return { ok: !!cell && view.isVisible(cell), row, cell, count: rows.length };
            },

            async openDetail(rowId, plotCode) {
                const resolved = this.resolveRow(rowId, plotCode);
                if (resolved.count !== 1) throw new Error('対象の区画の行を1つに決められません。rowId=' + rowId + ' plotCode=' + plotCode + ' count=' + resolved.count);
                if (!resolved.ok) throw new Error('対象の区画の区画コードのセルが表示されていません。rowId=' + rowId);

                const link = resolved.cell.querySelector('a, button, [role="link"]');
                act.click(link || resolved.cell);
                await act.sleep(100);
                return { ok: true, action: 'detail-requested', rowId, plotCode, via: link ? 'link' : 'cell' };
            },

            currentScroller() {
                const resolution = this.resolveRowScope();
                return resolution.ok ? locate.closestScrollable(resolution.scope.body) : (document.scrollingElement || document.documentElement);
            },

            async scrollToTop() {
                const scroller = this.currentScroller();
                scroll.setTop(scroller, 0);
                await act.sleep(300);
                return { ok: true, top: scroll.getTop(scroller) };
            },

            async scrollDown() {
                const scroller = this.currentScroller();
                const moved = scroll.scrollBy(scroller, scroll.pageAmount(scroller));
                await act.sleep(300);
                return { ok: true, before: moved.before, after: scroll.getTop(scroller), moved: scroll.getTop(scroller) !== moved.before };
            }
        };
    });
})(window.__pagekit);
