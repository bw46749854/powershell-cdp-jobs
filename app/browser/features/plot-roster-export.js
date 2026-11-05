/*
 * 機能: 区画一覧の CSV 出力（PlotRosterExport）
 * 部品名: feature.plotRosterExport（screen.greenhousePlotList を前提にする）
 * ヘルパー名: plotRosterExport（app/modules/PlotRosterExport/PageOperations.psd1 と対応）
 *
 * 契約（意味）
 *   - ツールバーの「操作」ボタンがちょうど1つ（メニューを開くボタン: aria-haspopup）
 *   - そのボタンが開くメニュー内に「CSV出力」項目（role=menuitem）がちょうど1つ
 * 吸収する構造の違い
 *   - メニューの位置: aria-controls で指すメニューを優先し、無ければボタンとメニューを両方含む最も近い祖先から探す
 *   - メニュー項目を包むラッパー要素の有無（role=menuitem で探すため段数に依存しない）
 */
(function (kit) {
    'use strict';

    const TASK_BUTTON_NAME = '操作';
    const EXPORT_ITEM_NAME = 'CSV出力';

    kit.part('feature.plotRosterExport', function () {
        const { text, view, locate, contract, act } = kit;

        function opensMenu(button) {
            const popup = text.attr(button, 'aria-haspopup');
            return popup === 'true' || popup === 'menu';
        }

        return {
            _lastExportClick: null,

            resolveTaskButton() {
                const buttons = locate.all(document, 'button, [role="button"]')
                    .filter(button => text.nameOf(button) === TASK_BUTTON_NAME && opensMenu(button));
                return locate.unique(locate.visibleOnly(buttons));
            },

            resolveTaskMenu(button) {
                if (!button) return { ok: false, element: null, source: 'none' };

                const controlsId = text.attr(button, 'aria-controls');
                if (controlsId) {
                    const controlled = document.getElementById(controlsId);
                    if (controlled) return { ok: true, element: controlled, source: 'aria-controls' };
                }

                for (let ancestor = button.parentElement; ancestor && ancestor !== document.documentElement; ancestor = ancestor.parentElement) {
                    const menus = locate.all(ancestor, '[role="menu"]');
                    if (menus.length === 1) return { ok: true, element: menus[0], source: 'nearest-ancestor' };
                    if (menus.length > 1) return { ok: false, element: null, source: 'ambiguous-ancestor', count: menus.length };
                }

                return { ok: false, element: null, source: 'not-found' };
            },

            resolveExportItem() {
                const button = this.resolveTaskButton();
                const menu = this.resolveTaskMenu(button.element);
                if (!button.ok || !menu.ok) {
                    return { ok: false, element: null, count: 0, reason: button.ok ? 'menu_not_resolved' : 'task_button_not_resolved', button, menuSource: menu.source };
                }

                const items = locate.byName(menu.element, '[role="menuitem"]', EXPORT_ITEM_NAME);
                return Object.assign(locate.unique(locate.visibleOnly(items)), {
                    hiddenCount: items.filter(item => !view.isVisible(item)).length,
                    menuSource: menu.source
                });
            },

            checkInitialScreen() {
                const checks = [
                    contract.check('initial.document.ready', document.readyState === 'complete', 'fatal',
                        '画面の読み込みが完了していること', { readyState: document.readyState })
                ].concat(this.screenIdentityChecks('initial'));

                const nav = this.resolveSectionNavItem();
                checks.push(contract.check('initial.nav.section.clickable', nav.ok && view.isClickable(nav.element), 'fatal',
                    'メインメニューの「区画」が表示され、操作できること', { nav: nav.candidates }));

                return contract.result('plotRosterExport.initial', checks, { title: document.title });
            },

            checkExportScreen() {
                const checks = this.screenIdentityChecks('exportScreen');
                const count = this.readPlotCount();
                const button = this.resolveTaskButton();

                checks.push(contract.check('exportScreen.count.readable', count.ok, 'fatal',
                    '件数表示「区画: <件数>」から件数を1つに決められること', count));
                checks.push(contract.check('exportScreen.taskButton.unique', button.ok, 'fatal',
                    'ツールバーの「' + TASK_BUTTON_NAME + '」ボタン（メニューを開くボタン）がちょうど1つあること', button));
                checks.push(contract.check('exportScreen.taskButton.clickable', button.ok && view.isClickable(button.element), 'fatal',
                    '「' + TASK_BUTTON_NAME + '」ボタンが操作できること', { button: button.candidates }));

                return contract.result('plotRosterExport.exportScreen', checks, { plotCount: count.value });
            },

            async openTaskMenu() {
                const button = this.resolveTaskButton();
                if (!button.ok) throw new Error('「' + TASK_BUTTON_NAME + '」ボタンを1つに決められません。count=' + button.count);
                if (!view.isClickable(button.element)) throw new Error('「' + TASK_BUTTON_NAME + '」ボタンが操作できません。');

                const menu = this.resolveTaskMenu(button.element);
                const alreadyOpen = menu.ok && view.isVisible(menu.element);
                if (!alreadyOpen) {
                    act.click(button.element);
                    await act.sleep(200);
                }

                return { ok: true, action: alreadyOpen ? 'menu-already-open' : 'menu-opened', expanded: text.attr(button.element, 'aria-expanded') };
            },

            isExportItemReady() {
                const item = this.resolveExportItem();
                return item.ok && view.isClickable(item.element);
            },

            async clickExportItem() {
                const item = this.resolveExportItem();
                if (!item.ok) {
                    throw new Error('メニューの「' + EXPORT_ITEM_NAME + '」を1つに決められません。count=' + item.count + ' reason=' + item.reason);
                }
                if (!view.isClickable(item.element)) throw new Error('メニューの「' + EXPORT_ITEM_NAME + '」が操作できません。');

                act.click(item.element);
                await act.sleep(300);

                this._lastExportClick = { ok: true, action: 'export-clicked', item: kit.describe(item.element), at: new Date().toISOString() };
                return this._lastExportClick;
            },

            checkExportAccepted() {
                const last = this._lastExportClick;
                const checks = [
                    contract.check('postExport.click.accepted', !!last && last.ok === true && last.action === 'export-clicked', 'fatal',
                        '「' + EXPORT_ITEM_NAME + '」のクリックがこのタブで実行されたこと', { last })
                ];
                return contract.result('plotRosterExport.postExport', checks, { last });
            }
        };
    });

    kit.define('plotRosterExport', ['screen.greenhousePlotList', 'feature.plotRosterExport']);
})(window.__pagekit);
