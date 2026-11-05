/*
 * モック画面の共通部品: CSV の作成とダウンロード、仮想スクロールの表示範囲、通知。
 */
(function (global) {
    'use strict';

    function csvField(value) {
        return '"' + String(value === null || value === undefined ? '' : value).replace(/"/g, '""') + '"';
    }

    // UTF-8（BOM 付き）・CRLF・全項目を引用符で囲む CSV
    function toCsv(columns, rows) {
        const lines = [columns.map(csvField).join(',')];
        for (const row of rows) lines.push(columns.map(column => csvField(row[column])).join(','));
        return '﻿' + lines.join('\r\n') + '\r\n';
    }

    function download(fileName, text) {
        const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = fileName;
        anchor.style.display = 'none';
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
        setTimeout(() => URL.revokeObjectURL(url), 10000);
    }

    // 仮想スクロール: スクロール位置から、描画する行の範囲 [start, end) を決める
    function windowFor(scrollTop, viewportHeight, rowHeight, total, overscan) {
        const first = Math.floor(scrollTop / rowHeight);
        const visible = Math.ceil(viewportHeight / rowHeight);
        const start = Math.max(0, first - overscan);
        const end = Math.min(total, first + visible + overscan);
        return { start, end };
    }

    // 行の要素を行 ID で使い回しながら、範囲内の行だけを順に並べる（範囲外の行は取り除く）
    function renderKeyed(container, items, cache, create, update, before, after) {
        const wanted = new Set(items.map(item => item.id));
        for (const [id, element] of cache) {
            if (!wanted.has(id)) {
                element.remove();
                cache.delete(id);
            }
        }
        let anchor = before;
        for (const item of items) {
            let element = cache.get(item.id);
            if (!element) {
                element = create(item);
                cache.set(item.id, element);
            }
            update(element, item);
            if (anchor.nextSibling !== element) container.insertBefore(element, anchor.nextSibling);
            anchor = element;
        }
        if (anchor.nextSibling !== after) container.insertBefore(after, anchor.nextSibling);
    }

    function notify(message) {
        let area = document.getElementById('mock-toast');
        if (!area) {
            area = document.createElement('div');
            area.id = 'mock-toast';
            area.className = 'mock-toast';
            area.setAttribute('role', 'status');
            document.body.appendChild(area);
        }
        area.textContent = message;
        area.classList.add('is-shown');
        clearTimeout(notify.timer);
        notify.timer = setTimeout(() => area.classList.remove('is-shown'), 2500);
    }

    global.MockKit = { toCsv, download, windowFor, renderKeyed, notify };
})(window);
