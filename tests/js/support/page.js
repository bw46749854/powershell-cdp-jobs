'use strict';

// app/browser のスクリプトを、本番と同じ「文字列として評価する」方法で jsdom に読み込むテスト用の土台。
//
// jsdom はレイアウトを計算しないため、getBoundingClientRect を「hidden 属性・display:none・visibility:hidden が
// 自分か祖先にあれば 0、それ以外は 100x20」と見なす簡易版に置き換える（可視判定の意味だけを再現する）。

const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const repositoryRoot = path.resolve(__dirname, '..', '..', '..');

const SCRIPTS = {
    plotRosterExport: [
        'app/browser/kernel/pagekit.js',
        'app/browser/screens/greenhouse-plot-list.js',
        'app/browser/features/plot-roster-export.js'
    ],
    soilAnalysisSync: [
        'app/browser/kernel/pagekit.js',
        'app/browser/screens/greenhouse-plot-list.js',
        'app/browser/features/soil-analysis-sync.table.js',
        'app/browser/features/soil-analysis-sync.js'
    ],
    plantingRecordExport: [
        'app/browser/kernel/pagekit.js',
        'app/browser/screens/ledger-plot-list.js',
        'app/browser/features/planting-record-export.grid.js',
        'app/browser/features/planting-record-export.detail.js',
        'app/browser/features/planting-record-export.js'
    ]
};

function readRepositoryFile(relativePath) {
    return fs.readFileSync(path.join(repositoryRoot, relativePath), 'utf8');
}

function installLayout(window) {
    const zero = { x: 0, y: 0, left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 };
    const box = { x: 0, y: 0, left: 0, top: 0, right: 100, bottom: 20, width: 100, height: 20 };

    window.Element.prototype.getBoundingClientRect = function getBoundingClientRect() {
        for (let element = this; element && element.nodeType === 1; element = element.parentElement) {
            if (element.hasAttribute('hidden')) return zero;
            const style = window.getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden') return zero;
        }
        return box;
    };
    window.Element.prototype.scrollIntoView = function scrollIntoView() { };
    window.scrollTo = function scrollTo() { };
}

async function loadPage(options) {
    const dom = new JSDOM(options.html, {
        runScripts: 'outside-only',
        url: options.url || 'http://localhost/',
        pretendToBeVisual: true
    });
    const { window } = dom;
    installLayout(window);

    if (window.document.readyState !== 'complete') {
        await new Promise(resolve => window.addEventListener('load', resolve));
    }

    if (typeof options.setup === 'function') options.setup(window);

    const scripts = options.scripts || [];
    for (const script of scripts) {
        window.eval(readRepositoryFile(script));
    }

    return {
        window,
        document: window.document,
        kit: window.__pagekit,
        helper: name => window.__pagekit.helpers[name],
        inject() {
            for (const script of scripts) window.eval(readRepositoryFile(script));
        }
    };
}

// jsdom 側（別 realm）で作られた配列を、Node 側の配列に詰め替えてから比較に使う。
function failedChecks(contractResult) {
    return Array.from(contractResult.checks).filter(check => !check.ok).map(check => check.name);
}

function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

module.exports = { SCRIPTS, loadPage, failedChecks, plain, readRepositoryFile, repositoryRoot };
