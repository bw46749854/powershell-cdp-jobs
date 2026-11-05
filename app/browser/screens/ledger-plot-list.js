/*
 * 画面: 作付け台帳「区画一覧」
 * 部品名: screen.ledgerPlotList
 *
 * 契約（意味）
 *   - 製品名「作付け台帳」が document.title かバナーにある
 *   - 画面の本体（data-view を持つ要素）がちょうど1つで、その値が plot-list（区画一覧）である
 *     （同じ部品で作られた「資材一覧」など別の一覧画面を取り違えない）
 *   - パンくず・見出し・document.title のどれかに「区画一覧」がある
 *   - 件数表示（data-bind="plotList.total"）から件数を読める
 * 吸収する構造の違い
 *   - 見出しやパンくずのタグ・クラス、件数表示の前後の文言
 */
(function (kit) {
    'use strict';

    const PRODUCT_NAME = '作付け台帳';
    const SCREEN_NAME = '区画一覧';
    const VIEW_NAME = 'plot-list';

    kit.part('screen.ledgerPlotList', function () {
        const { text, locate, contract } = kit;

        return {
            resolveView() {
                const views = locate.all(document, '[data-view]');
                const resolution = locate.unique(views);
                return Object.assign(resolution, { view: resolution.ok ? text.attr(resolution.element, 'data-view') : '' });
            },

            screenTexts() {
                const elements = locate.visibleOnly(locate.all(document, 'h1, [aria-current="page"], nav[aria-label="パンくず"] li'));
                return elements.map(element => text.of(element)).concat([text.norm(document.title)]).filter(Boolean);
            },

            readTotalCount() {
                const elements = locate.all(document, '[data-bind="plotList.total"]');
                if (elements.length !== 1) return null;
                const digits = text.of(elements[0]).replace(/,/g, '');
                return /^\d+$/.test(digits) ? Number(digits) : null;
            },

            ledgerIdentityChecks(prefix) {
                const banners = locate.visibleOnly(locate.all(document, '[role="banner"], header'));
                const productInBanner = banners.some(element => text.of(element).indexOf(PRODUCT_NAME) >= 0);
                const productInTitle = text.norm(document.title).indexOf(PRODUCT_NAME) >= 0;
                const view = this.resolveView();
                const texts = this.screenTexts();

                return [
                    contract.check(prefix + '.app.name', productInBanner || productInTitle, 'fatal',
                        '製品名「' + PRODUCT_NAME + '」が画面タイトルかバナーにあること', { title: document.title }),
                    contract.check(prefix + '.view.unique', view.ok, 'fatal',
                        '画面の本体（data-view）がちょうど1つあること', view),
                    contract.check(prefix + '.view.plotList', view.ok && view.view === VIEW_NAME, 'fatal',
                        '画面の本体が区画一覧（data-view="' + VIEW_NAME + '"）であること', { view: view.view }),
                    contract.check(prefix + '.title.plotList', texts.some(value => value.indexOf(SCREEN_NAME) >= 0), 'fatal',
                        'パンくず・見出し・画面タイトルのどれかに「' + SCREEN_NAME + '」があること', { texts: texts.slice(0, 10) })
                ];
            },

            detectScreen() {
                return contract.result('ledgerPlotList.identity', this.ledgerIdentityChecks('identity'), { title: document.title, url: location.href });
            }
        };
    });
})(window.__pagekit);
