/*
 * 機能: 区画ごとの作付け記録 CSV の取得（PlantingRecordExport）— 区画詳細
 * 部品名: feature.plantingRecordExport.detail
 *
 * 契約（意味）
 *   - 区画詳細は role=dialog・名前「区画詳細」。表示中の区画コードは data-bind="detail.plotCode"
 *   - タブ（role=tab）「作付け記録」がちょうど1つ。押した後は選択中（aria-selected=true）
 *   - 記録の種類のラジオ「作付け記録」が選択済み（未選択は想定外なので停止する。こちらから切り替えない）
 *   - 記録の表に見出し「作物名」「品種」「定植日」がある（順序は問わない）
 *   - CSV 出力の領域（data-export="planting"）がちょうど1つで、中の「CSV出力」ボタンがちょうど1つ
 *   - 閉じるボタン（名前「閉じる」）で区画詳細を閉じる
 * 吸収する構造の違い
 *   - タブが指すパネル（aria-controls）を探索範囲にする。パネルを辿れない場合は区画詳細全体を範囲にする（warning）
 *   - ラジオのラベルが label[for] か、ラジオを包む label か
 */
(function (kit) {
    'use strict';

    const DIALOG_NAME = '区画詳細';
    const TAB_NAME = '作付け記録';
    const RADIO_NAME = '作付け記録';
    const CSV_BUTTON_NAME = 'CSV出力';
    const CLOSE_NAME = '閉じる';
    const REQUIRED_RECORD_HEADERS = ['作物名', '品種', '定植日'];

    kit.part('feature.plantingRecordExport.detail', function () {
        const { text, view, locate, contract, act } = kit;

        return {
            drawer() {
                const dialogs = locate.byName(document, '[role="dialog"]', DIALOG_NAME);
                return dialogs.length === 1 ? dialogs[0] : null;
            },

            isDetailVisible() {
                return view.isVisible(this.drawer());
            },

            readDetailPlotCode() {
                const drawer = this.drawer();
                if (!view.isVisible(drawer)) return '';
                const codes = locate.visibleOnly(locate.all(drawer, '[data-bind="detail.plotCode"]'));
                return codes.length === 1 ? text.of(codes[0]) : '';
            },

            isDetailReadyFor(plotCode) {
                return this.isDetailVisible() && this.readDetailPlotCode() === text.norm(plotCode);
            },

            checkOpenedDetail(rowId, plotCode) {
                const selected = this.readSelectedRow();
                const detailCode = this.readDetailPlotCode();
                const checks = [
                    contract.check('openedDetail.selectedRow.unique', selected.ok, 'fatal', '一覧で選択中の行がちょうど1つであること', selected),
                    contract.check('openedDetail.selectedRow.matches', selected.ok && selected.rowId === rowId && selected.plotCode === plotCode, 'fatal',
                        '選択中の行がクリックした区画（行識別子 + 区画コード）であること', { selected, expected: { rowId, plotCode } }),
                    contract.check('openedDetail.drawer.visible', this.isDetailVisible(), 'fatal', '区画詳細が表示されていること', { drawer: kit.describe(this.drawer()) }),
                    contract.check('openedDetail.plotCode.matches', detailCode === plotCode, 'fatal',
                        '区画詳細に表示された区画コードがクリックした区画と一致すること', { expected: plotCode, actual: detailCode })
                ];
                return contract.result('plantingExport.openedDetail', checks, { rowId, plotCode, detailCode });
            },

            resolvePlantingTab() {
                const drawer = this.drawer();
                const lists = drawer ? locate.visibleOnly(locate.all(drawer, '[role="tablist"]')) : [];
                const tabs = lists.length === 1 ? locate.byName(lists[0], '[role="tab"]', TAB_NAME) : [];
                const resolution = locate.unique(locate.visibleOnly(tabs));
                return Object.assign(resolution, {
                    tablistCount: lists.length,
                    active: resolution.ok && text.attr(resolution.element, 'aria-selected') === 'true'
                });
            },

            plantingTabChecks(requireActive) {
                const tab = this.resolvePlantingTab();
                return [
                    contract.check('plantingTab.drawer.visible', this.isDetailVisible(), 'fatal', '区画詳細が表示されていること', {}),
                    contract.check('plantingTab.tablist.unique', tab.tablistCount === 1, 'fatal', '区画詳細のタブ一覧がちょうど1つあること', { count: tab.tablistCount }),
                    contract.check('plantingTab.tab.unique', tab.ok, 'fatal', 'タブ「' + TAB_NAME + '」がちょうど1つあること', tab),
                    contract.check('plantingTab.tab.enabled', tab.ok && !view.isDisabled(tab.element), 'fatal', 'タブ「' + TAB_NAME + '」が押せること', {}),
                    contract.check('plantingTab.tab.active', tab.active, requireActive ? 'fatal' : 'warning',
                        requireActive ? 'タブ「' + TAB_NAME + '」が選択中であること' : '押す前は未選択でもよい（押した後の契約で確認する）', { active: tab.active })
                ];
            },

            async openPlantingTab() {
                const checks = this.plantingTabChecks(false);
                contract.assertNoFatal(contract.result('plantingExport.plantingTab.beforeClick', checks, {}));
                const tab = this.resolvePlantingTab();
                if (!tab.active) {
                    act.click(tab.element);
                    await act.sleep(100);
                }
                return { ok: true, action: tab.active ? 'tab-already-active' : 'tab-clicked' };
            },

            resolvePlantingScope() {
                const drawer = this.drawer();
                const tab = this.resolvePlantingTab();
                const panelId = tab.ok ? text.attr(tab.element, 'aria-controls') : '';
                const panel = panelId ? document.getElementById(panelId) : null;
                if (panel && view.isVisible(panel) && drawer && drawer.contains(panel)) return { scope: panel, source: 'tabpanel' };
                return { scope: drawer, source: 'drawer' };
            },

            resolveRecordKindRadio(scope) {
                const radios = scope ? locate.all(scope, 'input[type="radio"]') : [];
                const named = radios.filter(radio => {
                    const label = (radio.id && document.querySelector('label[for="' + radio.id + '"]')) || radio.closest('label');
                    return !!label && text.of(label) === RADIO_NAME;
                });
                const resolution = locate.unique(named);
                const radio = resolution.element;
                const label = radio ? ((radio.id && document.querySelector('label[for="' + radio.id + '"]')) || radio.closest('label')) : null;
                return Object.assign(resolution, {
                    visible: !!radio && (view.isVisible(radio) || view.isVisible(label)),
                    enabled: !!radio && !view.isDisabled(radio),
                    checked: !!radio && radio.checked === true
                });
            },

            recordHeaders(scope) {
                return scope ? locate.visibleOnly(locate.all(scope, 'th')).map(cell => text.of(cell)) : [];
            },

            resolveExportButton(scope) {
                const areas = scope ? locate.all(scope, '[data-export="planting"]') : [];
                const area = locate.unique(areas);
                const buttons = area.ok ? locate.byName(area.element, 'button, [role="button"]', CSV_BUTTON_NAME).filter(view.isClickable) : [];
                return Object.assign(locate.unique(buttons), { areaCount: area.count });
            },

            checkPlantingTab() {
                const { scope, source } = this.resolvePlantingScope();
                const headers = this.recordHeaders(scope);
                const missing = REQUIRED_RECORD_HEADERS.filter(name => headers.indexOf(name) < 0);
                const radio = this.resolveRecordKindRadio(scope);
                const button = this.resolveExportButton(scope);

                const checks = this.plantingTabChecks(true).concat([
                    contract.check('plantingTab.scope.panel', source === 'tabpanel', 'warning',
                        'タブが指すパネル（aria-controls）を探索範囲にできること。できない場合は区画詳細全体で確認する。', { source }),
                    contract.check('plantingTab.records.headers', missing.length === 0, 'fatal',
                        '記録の表に見出し「' + REQUIRED_RECORD_HEADERS.join('」「') + '」があること（順序は問わない）', { headers, missing }),
                    contract.check('plantingTab.recordKind.unique', radio.ok, 'fatal', '記録の種類「' + RADIO_NAME + '」のラジオがちょうど1つあること', radio),
                    contract.check('plantingTab.recordKind.usable', radio.ok && radio.visible && radio.enabled, 'fatal', '記録の種類「' + RADIO_NAME + '」が表示され、有効であること', {}),
                    contract.check('plantingTab.recordKind.checked', radio.ok && radio.checked, 'fatal',
                        '記録の種類が「' + RADIO_NAME + '」になっていること（別の種類が選ばれていたら停止する）', { checked: radio.checked }),
                    contract.check('plantingTab.export.area.unique', button.areaCount === 1, 'fatal', '作付け記録の CSV 出力領域がちょうど1つあること', { count: button.areaCount }),
                    contract.check('plantingTab.export.button.unique', button.ok, 'fatal', 'CSV 出力領域に、押せる「' + CSV_BUTTON_NAME + '」ボタンがちょうど1つあること', button)
                ]);

                return contract.result('plantingExport.plantingTab', checks, { scopeSource: source, headers, radioChecked: radio.checked });
            },

            async clickPlantingCsv() {
                contract.assertNoFatal(this.checkPlantingTab());
                const { scope } = this.resolvePlantingScope();
                const button = this.resolveExportButton(scope);
                act.click(button.element);
                await act.sleep(100);
                return { ok: true, action: 'csv-clicked' };
            },

            closeDetail() {
                const drawer = this.drawer();
                if (!view.isVisible(drawer)) {
                    return { ok: true, alreadyClosed: true, action: 'detail-already-closed' };
                }

                const buttons = locate.byName(drawer, 'button, [role="button"]', CLOSE_NAME).filter(view.isClickable);
                if (buttons.length !== 1) {
                    return { ok: false, severity: 'warning', reason: 'close_button_not_unique', count: buttons.length };
                }

                act.click(buttons[0]);
                return { ok: true, alreadyClosed: false, action: 'detail-close-requested' };
            },

            isDetailClosed() {
                return !this.isDetailVisible();
            }
        };
    });
})(window.__pagekit);
