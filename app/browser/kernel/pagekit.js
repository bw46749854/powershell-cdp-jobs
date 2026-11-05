/*
 * pagekit kernel — ページへ注入するスクリプトの共通部品。
 *
 * ここに置くのは「どの画面でも同じ意味を持つ」規則だけ。
 *   text      文字列の正規化（空白・全角空白・改行を1つの空白に）と、要素の表示名
 *   view      可視・無効・操作可能の判定（意味のある属性だけを見る。CSS クラス名は見ない）
 *   describe  診断用の要素の要約（契約違反の調査に使う）
 *   contract  契約結果（PowerShell の PageBridge と共有する形）
 *   locate    候補を集めて「ちょうど1つ」を要求する解決
 *   act       ユーザー操作に近いクリック、待機
 *   scroll    スクロール位置の読み書き
 *   part / define / ack   画面・機能ごとの部品を1つのヘルパーへ組み立て、PowerShell へ報告する
 *
 * DOM は契約である。
 *   - 意味（表示文言、ARIA の役割と状態、画面が提供する data-* の目印）は契約として厳密に照合し、
 *     変わっていたら推測で補わず契約違反にする。
 *   - 構造（タグ名、CSS クラス、ラッパーの段数、列の並び順）は契約に含めず、
 *     意味から候補を集めることで多少の変化を吸収する。
 *   - 業務上の対象は必ず「ちょうど1つ」に解決する。0件・複数件は停止理由になる。
 */
(function (global) {
    'use strict';

    const VERSION = '1.0.0';
    const MAX_CANDIDATES = 20;
    const MAX_TEXT = 80;

    // ---- text ----------------------------------------------------------

    function norm(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/[\s 　]+/g, ' ')
            .trim();
    }

    function textOf(element) {
        return element ? norm(element.textContent) : '';
    }

    function attrOf(element, name) {
        return element ? norm(element.getAttribute(name)) : '';
    }

    function nameOf(element) {
        if (!element) return '';
        return attrOf(element, 'aria-label') || textOf(element) || attrOf(element, 'title');
    }

    function clip(value) {
        const text = norm(value);
        return text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) + '…' : text;
    }

    // ---- view ----------------------------------------------------------

    function isVisible(element) {
        if (!element || !element.isConnected) return false;
        const rect = element.getBoundingClientRect();
        if (!(rect.width > 0 && rect.height > 0)) return false;
        const style = global.getComputedStyle(element);
        return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
    }

    function isDisabled(element) {
        if (!element) return true;
        if (element.disabled === true || element.hasAttribute('disabled')) return true;
        if (element.closest('[aria-disabled="true"]')) return true;
        if (element.closest('fieldset[disabled]')) return true;
        return false;
    }

    function isClickable(element) {
        return isVisible(element) && !isDisabled(element);
    }

    // ---- diagnostics ---------------------------------------------------

    function describe(element) {
        if (!element || typeof element.getAttribute !== 'function') return null;
        return {
            tag: element.tagName,
            id: element.id || '',
            className: clip(typeof element.className === 'string' ? element.className : ''),
            role: element.getAttribute('role') || '',
            name: clip(nameOf(element)),
            visible: isVisible(element),
            disabled: isDisabled(element)
        };
    }

    function isNode(value) {
        return !!value && typeof global.Node === 'function' && value instanceof global.Node;
    }

    function sanitize(value, depth, seen) {
        const level = depth || 0;
        const visited = seen || new WeakSet();

        if (value === null || value === undefined) return value;
        const type = typeof value;
        if (type === 'string' || type === 'number' || type === 'boolean') return value;
        if (type === 'bigint') return String(value);
        if (type === 'function' || type === 'symbol') return undefined;
        if (isNode(value)) return describe(value);
        if (level >= 8) return '[depth]';
        if (Array.isArray(value)) return value.map(item => sanitize(item, level + 1, visited));
        if (type === 'object') {
            if (visited.has(value)) return '[circular]';
            visited.add(value);
            const out = {};
            for (const key of Object.keys(value)) {
                const item = sanitize(value[key], level + 1, visited);
                if (item !== undefined) out[key] = item;
            }
            return out;
        }
        return String(value);
    }

    // ---- contract ------------------------------------------------------

    function check(name, ok, severity, message, details) {
        return {
            name,
            ok: !!ok,
            severity: severity === 'warning' ? 'warning' : 'fatal',
            message: message || '',
            details: sanitize(details || {})
        };
    }

    function result(scope, checks, details) {
        const fatalCount = checks.filter(item => !item.ok && item.severity === 'fatal').length;
        const warningCount = checks.filter(item => !item.ok && item.severity === 'warning').length;
        return {
            scope,
            ok: fatalCount === 0,
            fatalCount,
            warningCount,
            checks: sanitize(checks),
            details: sanitize(details || {})
        };
    }

    function assertNoFatal(contractResult) {
        if (!contractResult || contractResult.fatalCount === 0) return;
        const failed = contractResult.checks
            .filter(item => !item.ok && item.severity === 'fatal')
            .map(item => item.name + ': ' + item.message);
        throw new Error('ページ契約違反: ' + contractResult.scope + ' / ' + failed.join(' / '));
    }

    // ---- locate --------------------------------------------------------

    function all(root, selector) {
        return Array.from((root || global.document).querySelectorAll(selector));
    }

    function distinct(elements) {
        return Array.from(new Set(elements.filter(Boolean)));
    }

    function visibleOnly(elements) {
        return elements.filter(isVisible);
    }

    function unique(candidates) {
        const items = distinct(candidates);
        const reason = items.length === 1 ? 'unique' : (items.length === 0 ? 'none' : 'ambiguous');
        return {
            ok: items.length === 1,
            element: items.length === 1 ? items[0] : null,
            count: items.length,
            reason,
            candidates: items.slice(0, MAX_CANDIDATES).map(describe)
        };
    }

    function byName(root, selector, name) {
        const expected = norm(name);
        return all(root, selector).filter(element => nameOf(element) === expected);
    }

    function isDocumentScroller(element) {
        const document = global.document;
        return element === document.scrollingElement || element === document.documentElement || element === document.body;
    }

    function closestScrollable(element) {
        for (let current = element ? element.parentElement : null; current; current = current.parentElement) {
            if (isDocumentScroller(current)) break;
            const overflow = global.getComputedStyle(current).overflowY;
            if ((overflow === 'auto' || overflow === 'scroll') && current.scrollHeight > current.clientHeight) {
                return current;
            }
        }
        return global.document.scrollingElement || global.document.documentElement;
    }

    // ---- act -----------------------------------------------------------

    function click(element) {
        if (!element) throw new Error('クリック対象の要素がありません。');
        if (typeof element.scrollIntoView === 'function') {
            element.scrollIntoView({ block: 'center', inline: 'nearest' });
        }

        const rect = element.getBoundingClientRect();
        const options = {
            bubbles: true,
            cancelable: true,
            view: global,
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2
        };
        for (const type of ['pointerover', 'mouseover', 'pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
            const EventType = type.startsWith('pointer') && typeof global.PointerEvent === 'function' ? global.PointerEvent : global.MouseEvent;
            element.dispatchEvent(new EventType(type, options));
        }
        element.click();
    }

    function sleep(milliseconds) {
        return new Promise(resolve => global.setTimeout(resolve, milliseconds));
    }

    // ---- scroll --------------------------------------------------------

    function getTop(scroller) {
        if (isDocumentScroller(scroller)) {
            return global.scrollY || global.document.documentElement.scrollTop || 0;
        }
        return scroller.scrollTop;
    }

    function setTop(scroller, value) {
        if (isDocumentScroller(scroller)) {
            global.scrollTo(0, value);
        }
        else {
            scroller.scrollTop = value;
        }
        const target = isDocumentScroller(scroller) ? global : scroller;
        target.dispatchEvent(new global.Event('scroll', { bubbles: true }));
    }

    function scrollBy(scroller, amount) {
        const before = getTop(scroller);
        setTop(scroller, before + amount);
        const after = getTop(scroller);
        return { before, after, moved: after !== before, amount };
    }

    function pageAmount(scroller) {
        const height = isDocumentScroller(scroller) ? global.innerHeight : scroller.clientHeight;
        return height ? Math.max(Math.floor(height * 0.75), 300) : 500;
    }

    // ---- helper assembly -----------------------------------------------

    const kit = {
        version: VERSION,
        helpers: {},
        parts: {},
        text: { norm, of: textOf, attr: attrOf, nameOf, clip },
        view: { isVisible, isDisabled, isClickable },
        describe,
        sanitize,
        contract: { check, result, assertNoFatal },
        locate: { all, distinct, visibleOnly, unique, byName, closestScrollable, isDocumentScroller },
        act: { click, sleep },
        scroll: { getTop, setTop, scrollBy, pageAmount },

        part(name, factory) {
            if (typeof factory !== 'function') throw new Error('pagekit: part の factory は関数で指定してください: ' + name);
            kit.parts[name] = factory;
        },

        define(helperName, partNames) {
            const helper = {};
            const owners = {};
            for (const partName of partNames) {
                const factory = kit.parts[partName];
                if (!factory) throw new Error('[pagekit:part-missing] 部品が読み込まれていません: ' + partName);
                const methods = factory(kit);
                for (const key of Object.keys(methods)) {
                    if (Object.prototype.hasOwnProperty.call(helper, key)) {
                        throw new Error('pagekit: メソッド ' + key + ' が ' + owners[key] + ' と ' + partName + ' で重複しています。');
                    }
                    helper[key] = methods[key];
                    owners[key] = partName;
                }
            }
            kit.helpers[helperName] = helper;
            return helper;
        },

        ack(helperName) {
            const helper = kit.helpers[helperName];
            if (!helper) return { ok: false, helper: helperName, reason: 'helper_not_defined', methods: [] };
            const methods = Object.keys(helper).filter(key => typeof helper[key] === 'function').sort();
            return { ok: true, helper: helperName, kernelVersion: VERSION, methods };
        }
    };

    global.__pagekit = kit;
})(window);
