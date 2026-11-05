'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { SCRIPTS, loadPage, failedChecks, plain } = require('./support/page');
const { ledgerPlot, plantingLedgerHtml, wireLedger } = require('./fixtures/planting-ledger');

async function openLedger(options) {
    let state = null;
    const page = await loadPage({
        html: plantingLedgerHtml(options),
        scripts: SCRIPTS.plantingRecordExport,
        setup: window => { state = wireLedger(window, options); }
    });
    return Object.assign(page, { ledger: page.helper('plantingRecordExport'), state });
}

async function openDetailFor(page, rowId, plotCode) {
    await page.ledger.openDetail(rowId, plotCode);
    assert.equal(page.ledger.isDetailReadyFor(plotCode), true);
}

test('reports the methods the PowerShell catalog relies on', async () => {
    const page = await openLedger();
    const methods = page.kit.ack('plantingRecordExport').methods;
    for (const method of ['detectScreen', 'checkScreen', 'checkList', 'readTotalCount', 'readVisibleRows', 'openDetail', 'readSelectedRow',
        'isDetailReadyFor', 'checkOpenedDetail', 'openPlantingTab', 'checkPlantingTab', 'readDetailPlotCode', 'clickPlantingCsv',
        'closeDetail', 'isDetailClosed', 'scrollToTop', 'scrollDown']) {
        assert.ok(methods.includes(method), method);
    }
});

test('identifies the plot list view and rejects a similar view of another list', async () => {
    const page = await openLedger();
    assert.equal(page.ledger.detectScreen().ok, true);

    const other = await openLedger({ view: 'material-list' });
    assert.deepEqual(failedChecks(other.ledger.detectScreen()), ['identity.view.plotList']);
});

test('validates the list and reads each plot once even though rows are drawn on both sides', async () => {
    const page = await openLedger();
    const list = page.ledger.checkList();
    assert.equal(list.ok, true, JSON.stringify(failedChecks(list)));
    assert.equal(list.details.total, 2);
    assert.deepEqual(plain(page.ledger.readVisibleRows()).map(row => row.plotCode), ['GH2-B01', 'GH2-B02']);
});

test('follows the plot code column when it moves to the main side (structure change)', async () => {
    const page = await openLedger({ codeSide: 'main' });
    assert.equal(page.ledger.checkList().ok, true);
    assert.deepEqual(plain(page.ledger.readVisibleRows()).map(row => row.plotCode), ['GH2-B01', 'GH2-B02']);
});

test('stops when the plot code column cannot be associated with cells', async () => {
    const page = await openLedger();
    page.document.getElementById('plots-col-code').removeAttribute('id');
    assert.ok(failedChecks(page.ledger.checkList()).includes('list.codeColumn.unique'));
    assert.throws(() => page.ledger.readVisibleRows(), /行を読む範囲を決められません/);
});

test('stops when both sides carry plot code cells (ambiguous scope)', async () => {
    const page = await openLedger();
    for (const row of page.document.querySelectorAll('tbody.main-body tr')) {
        const code = page.document.querySelector(`tbody.fixed-body tr[data-row-id="${row.getAttribute('data-row-id')}"] td[headers="plots-col-code"]`).cloneNode(true);
        row.prepend(code);
    }
    assert.ok(failedChecks(page.ledger.checkList()).includes('list.rowScope.unique'));
});

test('opens the detail of a plot and confirms it shows the same plot', async () => {
    const page = await openLedger();
    await openDetailFor(page, 'r-02', 'GH2-B02');

    const selected = plain(page.ledger.readSelectedRow());
    assert.equal(selected.ok, true);
    assert.equal(selected.plotCode, 'GH2-B02');
    const opened = page.ledger.checkOpenedDetail('r-02', 'GH2-B02');
    assert.equal(opened.ok, true, JSON.stringify(failedChecks(opened)));
    assert.deepEqual(failedChecks(page.ledger.checkOpenedDetail('r-01', 'GH2-B01')), ['openedDetail.selectedRow.matches', 'openedDetail.plotCode.matches']);
});

test('switches to the planting tab and clicks the planting CSV button', async () => {
    const page = await openLedger();
    await openDetailFor(page, 'r-01', 'GH2-B01');

    const before = page.ledger.checkPlantingTab();
    assert.ok(failedChecks(before).includes('plantingTab.tab.active'));

    assert.equal((await page.ledger.openPlantingTab()).action, 'tab-clicked');
    assert.equal((await page.ledger.openPlantingTab()).action, 'tab-already-active');
    const tab = page.ledger.checkPlantingTab();
    assert.equal(tab.ok, true, JSON.stringify(failedChecks(tab)));
    assert.equal(tab.details.scopeSource, 'tabpanel');

    assert.equal((await page.ledger.clickPlantingCsv()).action, 'csv-clicked');
    assert.equal(page.state.csvClicks, 1);
});

test('stops instead of switching when another record kind is selected', async () => {
    const page = await openLedger();
    await openDetailFor(page, 'r-01', 'GH2-B01');
    await page.ledger.openPlantingTab();
    page.document.querySelector('input[value="harvest"]').checked = true;

    assert.ok(failedChecks(page.ledger.checkPlantingTab()).includes('plantingTab.recordKind.checked'));
    await assert.rejects(() => page.ledger.clickPlantingCsv(), /ページ契約違反/);
    assert.equal(page.state.csvClicks, 0);
});

test('accepts a radio labelled through label[for] and a panel without aria-controls (warning only)', async () => {
    const page = await openLedger();
    await openDetailFor(page, 'r-01', 'GH2-B01');
    await page.ledger.openPlantingTab();
    const radio = page.document.querySelector('input[value="planting"]');
    const label = radio.closest('label');
    radio.id = 'kind-planting';
    label.replaceWith(radio);
    const separate = page.document.createElement('label');
    separate.setAttribute('for', 'kind-planting');
    separate.textContent = '作付け記録';
    radio.after(separate);
    page.document.getElementById('tab-planting').removeAttribute('aria-controls');

    const tab = page.ledger.checkPlantingTab();
    assert.equal(tab.ok, true, JSON.stringify(failedChecks(tab)));
    assert.equal(tab.details.scopeSource, 'drawer');
    assert.equal(tab.warningCount, 1);
});

test('rejects a missing required record header and a duplicated CSV button', async () => {
    const page = await openLedger();
    await openDetailFor(page, 'r-01', 'GH2-B01');
    await page.ledger.openPlantingTab();
    page.document.querySelector('.pl-records th:nth-child(3)').textContent = '植付日';
    page.document.querySelector('[data-export="planting"]').append(page.document.createElement('button'));
    page.document.querySelector('[data-export="planting"] button:last-child').textContent = 'CSV出力';

    const failed = failedChecks(page.ledger.checkPlantingTab());
    assert.ok(failed.includes('plantingTab.records.headers'));
    assert.ok(failed.includes('plantingTab.export.button.unique'));
});

test('closes the detail as cleanup and reports a broken close button as a warning, not an exception', async () => {
    const page = await openLedger();
    assert.equal(page.ledger.closeDetail().alreadyClosed, true);

    await openDetailFor(page, 'r-01', 'GH2-B01');
    const closed = page.ledger.closeDetail();
    assert.equal(closed.ok, true);
    assert.equal(page.ledger.isDetailClosed(), true);

    await openDetailFor(page, 'r-02', 'GH2-B02');
    page.document.querySelector('.pl-close').remove();
    const broken = page.ledger.closeDetail();
    assert.equal(broken.ok, false);
    assert.equal(broken.severity, 'warning');
});

test('refuses to open a plot that is not uniquely visible', async () => {
    const page = await openLedger({ plots: [ledgerPlot(0)] });
    await assert.rejects(() => page.ledger.openDetail('r-09', 'GH2-B09'), /1つに決められません/);
});
