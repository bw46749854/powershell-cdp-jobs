/*
 * 機能: 土壌分析対象チェックの整合（SoilAnalysisTargetSync）— 契約・同期・スクロール
 * 部品名: feature.soilAnalysisSync（screen.greenhousePlotList と feature.soilAnalysisSync.table を前提にする）
 * ヘルパー名: soilAnalysisSync（app/modules/SoilAnalysisTargetSync/PageOperations.psd1 と対応）
 *
 * このヘルパーは行の選択チェックボックスを目的の状態（ON / OFF）に揃えるだけで、
 * 「土壌分析を依頼」は決してクリックしない（有効になったことの確認だけを行う）。
 *
 * 操作スコープ（どのペインの行を操作するか）は checkList / prepareScope で一度だけ決めて保持し、
 * 走査中は保持したペインの中だけを読む（毎回の再判定で対象がぶれないようにする）。
 */
(function (kit) {
    'use strict';

    const SEARCH_NAME = '区画コードで絞り込み';
    const REQUEST_ITEM_NAME = '土壌分析を依頼';
    const REQUEST_GROUP_NAME = '選択区画';

    kit.part('feature.soilAnalysisSync', function () {
        const { text, view, locate, contract, act, scroll } = kit;

        function failure(reason, details) {
            return Object.assign({ ok: false, reason }, details || {});
        }

        return {
            _scope: null,

            preparedScope() {
                const scope = this._scope;
                if (!scope || !scope.pane || !scope.pane.isConnected) return null;
                return scope;
            },

            requirePreparedScope() {
                const scope = this.preparedScope();
                if (!scope) throw new Error('操作スコープが準備されていないか、画面の再描画で失われました。');
                return scope;
            },

            storeScope(scope) {
                this._scope = scope ? { name: scope.name, kind: scope.kind, pane: scope.pane, keyIndex: scope.keyIndex, selectionIndex: scope.selectionIndex } : null;
                return this._scope;
            },

            resolveSearchBox() {
                const boxes = locate.all(document, 'input[type="search"], [role="searchbox"]')
                    .filter(element => text.attr(element, 'aria-label') === SEARCH_NAME || text.attr(element, 'placeholder') === SEARCH_NAME);
                return locate.unique(locate.visibleOnly(boxes));
            },

            checkScreen() {
                const checks = [
                    contract.check('screen.document.ready', document.readyState === 'complete', 'fatal',
                        '画面の読み込みが完了していること', { readyState: document.readyState })
                ].concat(this.screenIdentityChecks('screen'));

                const search = this.resolveSearchBox();
                const count = this.readPlotCount();
                const rows = this.visibleDataRows(document);
                checks.push(contract.check('screen.searchBox.unique', search.ok, 'fatal',
                    '絞り込み欄「' + SEARCH_NAME + '」がちょうど1つあること（このジョブは絞り込み欄を使わない）', search));
                checks.push(contract.check('screen.count.readable', count.ok, 'fatal',
                    '件数表示「区画: <件数>」から件数を1つに決められること', count));
                checks.push(contract.check('screen.rows.exist', rows.length > 0, 'fatal',
                    '一覧の行が表示されていること', { rowCount: rows.length }));

                return contract.result('soilAnalysisSync.screen', checks, { plotCount: count.value });
            },

            checkList() {
                const header = this.resolveFullHeaderRow();
                const resolution = this.resolveOperationScope();
                const scope = resolution.selected;
                const infos = scope ? scope.infos : [];
                const count = this.readPlotCount();
                const scroller = scope ? this.scrollerOf(scope.pane) : null;
                const checks = [
                    contract.check('list.header.fullRow.unique', header.ok, 'fatal',
                        '必須の列見出し（' + this.requiredHeaders().join(' / ') + '）と選択列を持つ見出し行がちょうど1つあること', header),
                    contract.check('list.header.required.unique', header.headersUnique, 'fatal',
                        '必須の列見出しが、その見出し行の中で重複していないこと', { duplicated: header.duplicated }),
                    contract.check('list.scope.unique', resolution.ok, 'fatal',
                        '操作に使うペインを1つに決められること（左固定ペインが1つだけ有効ならそれを使い、推測では選ばない）', resolution),
                    contract.check('list.rows.exist', infos.length > 0, 'fatal',
                        '操作に使うペインに行が表示されていること', { rowCount: infos.length }),
                    contract.check('list.rows.rowId', infos.length > 0 && infos.every(info => info.rowId), 'fatal',
                        'すべての行が行識別子（data-row-id）を持つこと', { rows: infos.slice(0, 20) }),
                    contract.check('list.rows.plotCode', infos.length > 0 && infos.every(info => info.plotCode), 'fatal',
                        'すべての行で区画コードが空でないこと', { rows: infos.slice(0, 20) }),
                    contract.check('list.rows.checkbox.unique', infos.length > 0 && infos.every(info => info.checkboxCount === 1), 'fatal',
                        'すべての行の選択列に、チェックボックスがちょうど1つあること', { rows: infos.filter(info => info.checkboxCount !== 1).slice(0, 20) }),
                    contract.check('list.count.readable', count.ok, 'fatal',
                        '件数表示から一覧の件数を1つに決められること（件数が分からないまま走査を終えない）', count),
                    contract.check('list.scroller.found', !!scroller, 'fatal',
                        '一覧をスクロールする領域を決められること', { scroller: kit.describe(scroller) })
                ];

                if (resolution.ok) this.storeScope(scope);

                return contract.result('soilAnalysisSync.list', checks, {
                    plotCount: count.value,
                    scope: this.summarizeScope(scope),
                    scopeReason: resolution.reason
                });
            },

            prepareScope() {
                const resolution = this.resolveOperationScope();
                if (!resolution.ok) {
                    this.storeScope(null);
                    return failure(resolution.reason, { scopes: resolution.scopes });
                }
                this.storeScope(resolution.selected);
                return { ok: true, reason: resolution.reason, scope: this.summarizeScope(resolution.selected) };
            },

            readVisibleRows() {
                const scope = this.requirePreparedScope();
                return this.visibleDataRows(scope.pane).map(row => this.rowInfo(row, scope));
            },

            findRowsByPlotCode(scope, plotCode) {
                return this.visibleDataRows(scope.pane)
                    .map(row => ({ row, info: this.rowInfo(row, scope) }))
                    .filter(item => item.info.plotCode === plotCode);
            },

            async syncSelection(plotCode, desiredChecked) {
                const code = text.norm(plotCode);
                const desired = desiredChecked === true;
                const scope = this.preparedScope();
                if (!scope) return failure('scope_not_prepared', { plotCode: code, desiredChecked: desired });

                const before = this.findRowsByPlotCode(scope, code);
                if (before.length !== 1) {
                    return failure(before.length === 0 ? 'plot_not_visible' : 'plot_duplicated_in_view', { plotCode: code, desiredChecked: desired, candidates: before.map(item => item.info) });
                }

                const row = before[0].row;
                const beforeInfo = before[0].info;
                const checkboxes = this.checkboxesOf(row, scope.selectionIndex);
                if (checkboxes.length !== 1) {
                    return failure('checkbox_not_unique', { plotCode: code, rowId: beforeInfo.rowId, desiredChecked: desired, checkboxCount: checkboxes.length });
                }

                const checkbox = checkboxes[0];
                const target = checkbox.closest('label') || checkbox;
                if (view.isDisabled(checkbox) || view.isDisabled(target)) {
                    return failure('checkbox_disabled', { plotCode: code, rowId: beforeInfo.rowId, desiredChecked: desired });
                }

                const alreadyAligned = beforeInfo.effectiveChecked === desired;
                if (!alreadyAligned) {
                    act.click(target);
                    await act.sleep(300);
                }

                const after = this.findRowsByPlotCode(scope, code);
                if (after.length !== 1) {
                    return failure('plot_not_unique_after_click', { plotCode: code, rowId: beforeInfo.rowId, desiredChecked: desired, before: beforeInfo, candidates: after.map(item => item.info) });
                }

                const afterInfo = after[0].info;
                const result = {
                    plotCode: code,
                    rowId: beforeInfo.rowId,
                    desiredChecked: desired,
                    changed: !alreadyAligned,
                    alreadyAligned,
                    effectiveCheckedBefore: beforeInfo.effectiveChecked,
                    effectiveCheckedNow: afterInfo.effectiveChecked,
                    before: beforeInfo,
                    after: afterInfo
                };

                if (afterInfo.checkboxCount !== 1 || afterInfo.effectiveChecked !== desired) {
                    return Object.assign(result, { ok: false, reason: afterInfo.checkboxCount !== 1 ? 'checkbox_not_unique_after_click' : 'state_not_aligned_after_click' });
                }

                return Object.assign(result, { ok: true });
            },

            resolveRequestItem() {
                const items = locate.byName(document, '[role="menuitem"]', REQUEST_ITEM_NAME).filter(item => {
                    const group = item.closest('[role="group"]');
                    return !!group && text.nameOf(group).indexOf(REQUEST_GROUP_NAME) >= 0;
                });
                return locate.unique(items);
            },

            checkAnalysisMenu() {
                const scope = this.preparedScope();
                const selectedVisible = scope ? this.readVisibleRows().filter(info => info.effectiveChecked) : [];
                const item = this.resolveRequestItem();
                const checks = [
                    contract.check('postSelection.selectedRows.visible', selectedVisible.length > 0, 'warning',
                        '表示中の行に選択済みの区画があること（仮想スクロールで表示範囲外にあるだけの場合があるため warning）', { selectedVisibleCount: selectedVisible.length }),
                    contract.check('postSelection.requestItem.unique', item.ok, 'fatal',
                        '「' + REQUEST_GROUP_NAME + '」グループの「' + REQUEST_ITEM_NAME + '」がちょうど1つあること', item),
                    contract.check('postSelection.requestItem.enabled', item.ok && !view.isDisabled(item.element), 'fatal',
                        '区画を選択したことで「' + REQUEST_ITEM_NAME + '」が有効になっていること（このジョブはクリックしない）', { item: item.candidates })
                ];
                return contract.result('soilAnalysisSync.postSelection', checks, { selectedVisibleCount: selectedVisible.length });
            },

            currentScroller() {
                const scope = this.preparedScope();
                return scope ? this.scrollerOf(scope.pane) : (document.scrollingElement || document.documentElement);
            },

            async scrollToTop() {
                const scroller = this.currentScroller();
                const before = scroll.getTop(scroller);
                scroll.setTop(scroller, 0);
                await act.sleep(600);
                return { ok: true, before, after: scroll.getTop(scroller) };
            },

            async scrollDown() {
                const scroller = this.currentScroller();
                const moved = scroll.scrollBy(scroller, scroll.pageAmount(scroller));
                await act.sleep(500);
                const after = scroll.getTop(scroller);
                return { ok: true, before: moved.before, after, changed: after !== moved.before };
            }
        };
    });

    kit.define('soilAnalysisSync', ['screen.greenhousePlotList', 'feature.soilAnalysisSync.table', 'feature.soilAnalysisSync']);
})(window.__pagekit);
