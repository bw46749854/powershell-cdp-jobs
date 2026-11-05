/*
 * 機能: 土壌分析対象チェックの整合（SoilAnalysisTargetSync）— 一覧表の読み取り
 * 部品名: feature.soilAnalysisSync.table
 *
 * 一覧は ARIA の grid として読む。
 *   行     : role=row（データ行は data-row-id を持つ）
 *   セル   : role=gridcell / cell / columnheader / rowheader（行との間にラッパーがあってもよい）
 *   ペイン : 行を含む role=rowgroup。左固定のペインは data-pinned を持つ
 * 同じ区画の行が「左固定ペイン」と「通常ペイン」の両方に描画されるため、操作に使うペイン（操作スコープ）を
 * 1つに決めてから行を読む。両方を数えると件数が倍になり、片方だけ操作すると状態の確認を誤る。
 *
 * 契約（意味）
 *   - 列は見出しの文言で特定する（位置では特定しない）。区画コード列 =「区画コード」
 *   - 選択列 = 見出しにチェックボックス（すべて選択）がある列。行の選択チェックボックスはその列のセルに1つだけ
 *   - 行の選択状態 = aria-selected="true" またはチェックボックスの checked
 * 吸収する構造の違い
 *   - 列の並び順、セルを包むラッパー、ペインの CSS クラス
 */
(function (kit) {
    'use strict';

    const KEY_HEADER = '区画コード';
    const REQUIRED_HEADERS = ['区画コード', '担当者', '稼働状態', '最終計測日時', '土壌分析の依頼', '土壌分析の完了'];
    const CELL_SELECTOR = '[role="gridcell"], [role="cell"], [role="columnheader"], [role="rowheader"]';

    kit.part('feature.soilAnalysisSync.table', function () {
        const { text, view, locate } = kit;

        return {
            requiredHeaders() {
                return REQUIRED_HEADERS.slice();
            },

            cellsOf(row) {
                return locate.all(row, CELL_SELECTOR).filter(cell => cell.closest('[role="row"]') === row);
            },

            isHeaderRow(row) {
                return !row.hasAttribute('data-row-id') && this.cellsOf(row).some(cell => cell.getAttribute('role') === 'columnheader');
            },

            headerTexts(row) {
                return this.cellsOf(row).map(cell => text.of(cell));
            },

            selectionColumnIndex(headerRow) {
                const indexes = [];
                this.cellsOf(headerRow).forEach((cell, index) => {
                    if (cell.querySelector('input[type="checkbox"]')) indexes.push(index);
                });
                return indexes.length === 1 ? indexes[0] : -1;
            },

            visibleHeaderRows(root) {
                return locate.visibleOnly(locate.all(root || document, '[role="row"]')).filter(row => this.isHeaderRow(row));
            },

            visibleDataRows(root) {
                return locate.visibleOnly(locate.all(root || document, '[role="row"][data-row-id]'));
            },

            paneOf(row) {
                return row.closest('[role="rowgroup"]') || row.closest('[role="grid"]') || row.parentElement;
            },

            resolveFullHeaderRow() {
                const rows = this.visibleHeaderRows(document).map(row => {
                    const headers = this.headerTexts(row);
                    return {
                        row,
                        headers,
                        hasRequired: REQUIRED_HEADERS.every(name => headers.indexOf(name) >= 0),
                        selectionIndex: this.selectionColumnIndex(row)
                    };
                });
                const full = rows.filter(item => item.hasRequired && item.selectionIndex >= 0);
                const target = full.length === 1 ? full[0] : null;
                const duplicated = target ? REQUIRED_HEADERS.filter(name => target.headers.filter(header => header === name).length !== 1) : [];

                return {
                    ok: !!target,
                    headersUnique: !!target && duplicated.length === 0,
                    duplicated,
                    count: full.length,
                    headers: target ? target.headers : [],
                    candidates: rows.map(item => ({ headers: item.headers, hasRequired: item.hasRequired, selectionIndex: item.selectionIndex }))
                };
            },

            checkboxesOf(row, selectionIndex) {
                const cell = this.cellsOf(row)[selectionIndex];
                return cell ? locate.all(cell, 'input[type="checkbox"]') : [];
            },

            rowInfo(row, scope) {
                const cells = this.cellsOf(row);
                const checkboxes = this.checkboxesOf(row, scope.selectionIndex);
                const checkbox = checkboxes.length === 1 ? checkboxes[0] : null;
                const selected = text.attr(row, 'aria-selected') === 'true';
                const checked = !!checkbox && checkbox.checked === true;
                return {
                    rowId: text.attr(row, 'data-row-id'),
                    plotCode: cells.length > scope.keyIndex ? text.of(cells[scope.keyIndex]) : '',
                    selected,
                    checked,
                    effectiveChecked: selected || checked,
                    checkboxCount: checkboxes.length,
                    checkboxDisabled: checkbox ? view.isDisabled(checkbox) : null
                };
            },

            buildScope(pane, index) {
                const pinned = pane.hasAttribute('data-pinned');
                const scope = {
                    name: (pinned ? 'pinned' : 'main') + '#' + index,
                    kind: pinned ? 'pinned' : 'main',
                    pane,
                    keyIndex: -1,
                    selectionIndex: -1,
                    rows: [],
                    infos: [],
                    problems: []
                };

                const headerRows = this.visibleHeaderRows(pane);
                const usable = headerRows.filter(row => this.headerTexts(row).filter(header => header === KEY_HEADER).length === 1 && this.selectionColumnIndex(row) >= 0);
                if (usable.length !== 1) {
                    scope.problems.push('header_row_count=' + usable.length);
                    return scope;
                }

                scope.keyIndex = this.headerTexts(usable[0]).indexOf(KEY_HEADER);
                scope.selectionIndex = this.selectionColumnIndex(usable[0]);
                scope.rows = this.visibleDataRows(pane);
                scope.infos = scope.rows.map(row => this.rowInfo(row, scope));

                const keys = scope.infos.map(info => info.rowId + '|' + info.plotCode);
                const duplicates = Array.from(new Set(keys.filter((key, position) => keys.indexOf(key) !== position)));
                if (scope.rows.length === 0) scope.problems.push('no_rows');
                if (scope.infos.some(info => !info.rowId)) scope.problems.push('row_id_missing');
                if (scope.infos.some(info => !info.plotCode)) scope.problems.push('plot_code_missing');
                if (scope.infos.some(info => info.checkboxCount !== 1)) scope.problems.push('checkbox_not_unique');
                if (duplicates.length > 0) scope.problems.push('duplicate_rows=' + duplicates.join(','));
                return scope;
            },

            summarizeScope(scope) {
                if (!scope) return null;
                return {
                    name: scope.name,
                    kind: scope.kind,
                    keyIndex: scope.keyIndex,
                    selectionIndex: scope.selectionIndex,
                    rowCount: scope.rows.length,
                    problems: scope.problems,
                    pane: kit.describe(scope.pane)
                };
            },

            resolveOperationScope() {
                const panes = locate.distinct(this.visibleDataRows(document).map(row => this.paneOf(row)));
                const scopes = panes.map((pane, index) => this.buildScope(pane, index));
                const valid = scopes.filter(scope => scope.problems.length === 0);
                const pinned = valid.filter(scope => scope.kind === 'pinned');

                let selected = null;
                let reason;
                if (pinned.length === 1) {
                    selected = pinned[0];
                    reason = 'single_valid_pinned_pane';
                }
                else if (pinned.length > 1) {
                    reason = 'multiple_valid_pinned_panes';
                }
                else if (valid.length === 1) {
                    selected = valid[0];
                    reason = 'single_valid_pane';
                }
                else {
                    reason = valid.length === 0 ? 'no_valid_pane' : 'multiple_valid_panes_without_pinned';
                }

                return { ok: !!selected, selected, reason, scopes: scopes.map(scope => this.summarizeScope(scope)) };
            },

            scrollerOf(pane) {
                return locate.closestScrollable(pane);
            }
        };
    });
})(window.__pagekit);
