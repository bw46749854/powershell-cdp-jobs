/*
 * 画面: 温室コンソール「区画」一覧（グループ: 全区画（既定））
 * 部品名: screen.greenhousePlotList
 *
 * この画面を対象にする2つのジョブ（PlotRosterExport / SoilAnalysisTargetSync）が同じ部品を読み込むため、
 * 画面識別の基準は1か所にしかない（ジョブごとに識別がずれることが構造的に起きない）。
 *
 * 契約（意味）
 *   - 製品名「温室コンソール」が document.title かバナー（role=banner / header）にある
 *   - メインメニューの「区画」がちょうど1つあり、現在地（aria-current）である
 *   - グループツリーで選択中（aria-selected=true）の項目がちょうど1つで、表示名が「全区画（既定）」
 *   - 件数表示「区画: <件数>」から件数を1つに決められる
 * 吸収する構造の違い
 *   - メニュー項目のタグ（a / button / li）や CSS クラス
 *   - 括弧の全角・半角（「全区画（既定）」と「全区画 (既定)」）
 *   - 件数表示の目印（data-count="plots"）が無い場合は、表示文言から探す
 */
(function (kit) {
    'use strict';

    const PRODUCT_NAME = '温室コンソール';
    const SECTION_NAME = '区画';
    const DEFAULT_GROUP_NAMES = ['全区画（既定）', '全区画 (既定)'];
    const COUNT_PATTERN = /^区画\s*[:：]\s*([\d,]+)\s*件?$/;

    kit.part('screen.greenhousePlotList', function () {
        const { text, locate, contract } = kit;

        return {
            resolveProductName() {
                const banners = locate.visibleOnly(locate.all(document, '[role="banner"], header'));
                const inBanner = banners.some(element => text.of(element).indexOf(PRODUCT_NAME) >= 0);
                const inTitle = text.norm(document.title).indexOf(PRODUCT_NAME) >= 0;
                return { ok: inBanner || inTitle, inBanner, inTitle, title: document.title };
            },

            resolveSectionNavItem() {
                const hooked = locate.visibleOnly(locate.all(document, '[data-nav="plots"]'));
                if (hooked.length > 0) {
                    return Object.assign(locate.unique(hooked), { source: 'data-nav' });
                }

                const navs = locate.all(document, 'nav, [role="navigation"]');
                const named = navs.flatMap(nav => locate.byName(nav, 'a, button, [role="menuitem"], [role="link"], [role="tab"]', SECTION_NAME));
                return Object.assign(locate.unique(locate.visibleOnly(named)), { source: 'name' });
            },

            resolveSelectedGroup() {
                const selected = locate.all(document, '[role="tree"] [role="treeitem"][aria-selected="true"]');
                const resolution = locate.unique(locate.visibleOnly(selected));
                const label = resolution.ok ? text.of(resolution.element) : '';
                return Object.assign(resolution, { label, isDefault: DEFAULT_GROUP_NAMES.indexOf(label) >= 0 });
            },

            readPlotCount() {
                const hooked = locate.all(document, '[data-count="plots"]');
                const elements = hooked.length > 0
                    ? hooked
                    : locate.all(document, 'span, div, p, strong, b, output').filter(element => COUNT_PATTERN.test(text.of(element)));
                const values = [];
                const candidates = [];
                for (const element of locate.visibleOnly(elements)) {
                    const match = COUNT_PATTERN.exec(text.of(element));
                    const value = match ? Number(match[1].replace(/,/g, '')) : null;
                    candidates.push({ text: text.clip(text.of(element)), value });
                    if (value !== null && !Number.isNaN(value)) values.push(value);
                }
                const distinctValues = Array.from(new Set(values));
                return {
                    ok: distinctValues.length === 1,
                    value: distinctValues.length === 1 ? distinctValues[0] : null,
                    values: distinctValues,
                    source: hooked.length > 0 ? 'data-count' : 'text',
                    candidates: candidates.slice(0, 20)
                };
            },

            screenIdentityChecks(prefix) {
                const product = this.resolveProductName();
                const nav = this.resolveSectionNavItem();
                const group = this.resolveSelectedGroup();
                const current = nav.ok ? text.attr(nav.element, 'aria-current') : '';

                return [
                    contract.check(prefix + '.app.name', product.ok, 'fatal',
                        '製品名「' + PRODUCT_NAME + '」が画面タイトルかバナーにあること', product),
                    contract.check(prefix + '.nav.section.unique', nav.ok, 'fatal',
                        'メインメニューの「' + SECTION_NAME + '」がちょうど1つあること', nav),
                    contract.check(prefix + '.nav.section.current', nav.ok && (current === 'page' || current === 'true'), 'fatal',
                        'メインメニューの現在地が「' + SECTION_NAME + '」であること（aria-current）', { current }),
                    contract.check(prefix + '.group.default.selected', group.ok && group.isDefault, 'fatal',
                        'グループツリーで「全区画（既定）」だけが選択されていること', { label: group.label, count: group.count, candidates: group.candidates })
                ];
            },

            detectScreen() {
                const checks = this.screenIdentityChecks('identity');
                return contract.result('greenhousePlotList.identity', checks, { title: document.title, url: location.href });
            }
        };
    });
})(window.__pagekit);
