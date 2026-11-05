'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { SCRIPTS, loadPage, failedChecks, plain } = require('./support/page');
const { greenhouseConsoleHtml, plot, wireMenus, wireSelection } = require('./fixtures/greenhouse-console');

async function openSyncPage(options) {
    const page = await loadPage({
        html: greenhouseConsoleHtml(options),
        scripts: SCRIPTS.soilAnalysisSync,
        setup: window => { wireMenus(window); wireSelection(window); }
    });
    return Object.assign(page, { sync: page.helper('soilAnalysisSync') });
}

function rowsOf(page, plotCode) {
    return Array.from(page.document.querySelectorAll('[role="row"][data-row-id]'))
        .filter(row => Array.from(row.querySelectorAll('[role="gridcell"]')).some(cell => cell.textContent.trim() === plotCode));
}

test('reports the methods the PowerShell catalog relies on', async () => {
    const page = await openSyncPage();
    const methods = page.kit.ack('soilAnalysisSync').methods;
    for (const method of ['detectScreen', 'checkScreen', 'checkList', 'prepareScope', 'readVisibleRows', 'syncSelection', 'checkAnalysisMenu', 'scrollToTop', 'scrollDown']) {
        assert.ok(methods.includes(method), method);
    }
});

test('validates the screen and the list, and operates on the pinned pane', async () => {
    const page = await openSyncPage({ count: 3 });
    const screen = page.sync.checkScreen();
    assert.equal(screen.ok, true, JSON.stringify(failedChecks(screen)));

    const list = page.sync.checkList();
    assert.equal(list.ok, true, JSON.stringify(failedChecks(list)));
    assert.equal(list.details.plotCount, 3);
    assert.equal(list.details.scope.kind, 'pinned');
    assert.equal(list.details.scopeReason, 'single_valid_pinned_pane');

    const rows = plain(page.sync.readVisibleRows());
    assert.deepEqual(rows.map(row => row.plotCode), ['GH1-A01', 'GH1-A02', 'GH1-A03'], 'each plot must be read once, not once per pane');
});

test('absorbs a different column order and wrappers around cells', async () => {
    const page = await openSyncPage();
    const mainPane = page.document.querySelectorAll('[role="rowgroup"]')[1];
    for (const row of mainPane.querySelectorAll('[role="row"]')) {
        const cells = row.querySelectorAll(':scope > [role="gridcell"], :scope > [role="columnheader"]');
        row.insertBefore(cells[3], cells[2]);
        const wrapper = page.document.createElement('div');
        wrapper.className = 'gc-cell-group';
        cells[4].replaceWith(wrapper);
        wrapper.appendChild(cells[4]);
    }

    const list = page.sync.checkList();
    assert.equal(list.ok, true, JSON.stringify(failedChecks(list)));
});

test('refuses to guess between two panes when the pinned marker disappears', async () => {
    const page = await openSyncPage();
    page.document.querySelector('[data-pinned]').removeAttribute('data-pinned');

    const list = page.sync.checkList();
    assert.ok(failedChecks(list).includes('list.scope.unique'));
    assert.equal(list.details.scopeReason, 'multiple_valid_panes_without_pinned');
    assert.equal(page.sync.prepareScope().ok, false);
});

test('rejects a renamed key column header (meaning changed)', async () => {
    const page = await openSyncPage();
    for (const header of page.document.querySelectorAll('[role="columnheader"]')) {
        if (header.textContent.trim() === '区画コード') header.textContent = '区画ID';
    }

    const failed = failedChecks(page.sync.checkList());
    assert.ok(failed.includes('list.header.fullRow.unique'));
    assert.ok(failed.includes('list.scope.unique'));
});

test('rejects rows whose selection cell has more than one checkbox', async () => {
    const page = await openSyncPage();
    const pinnedRow = page.document.querySelector('[data-pinned] [role="row"][data-row-id]');
    const extra = page.document.createElement('input');
    extra.type = 'checkbox';
    pinnedRow.querySelector('[role="gridcell"]').appendChild(extra);

    const list = page.sync.checkList();
    assert.equal(list.details.scope.kind, 'main', 'the broken pinned pane must not be used');
    assert.equal(list.ok, true, 'the main pane is still a valid single scope');

    const mainRow = page.document.querySelectorAll('[role="rowgroup"]')[1].querySelector('[role="row"][data-row-id]');
    mainRow.querySelector('[role="gridcell"]').appendChild(extra.cloneNode());
    assert.ok(failedChecks(page.sync.checkList()).includes('list.scope.unique'));
});

test('turns a checkbox on and verifies the state after the click', async () => {
    const page = await openSyncPage();
    page.sync.prepareScope();

    const result = await page.sync.syncSelection('GH1-A02', true);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.changed, true);
    assert.equal(result.effectiveCheckedNow, true);
    assert.ok(rowsOf(page, 'GH1-A02').every(row => row.getAttribute('aria-selected') === 'true'));
});

test('does not click when the plot is already in the desired state', async () => {
    const page = await openSyncPage({ plots: [plot(0, { selected: true }), plot(1)] });
    page.sync.prepareScope();
    let clicks = 0;
    for (const label of page.document.querySelectorAll('label')) label.addEventListener('click', () => { clicks++; });

    const on = await page.sync.syncSelection('GH1-A01', true);
    const off = await page.sync.syncSelection('GH1-A02', false);
    assert.equal(on.ok && on.alreadyAligned, true);
    assert.equal(off.ok && off.alreadyAligned, true);
    assert.equal(clicks, 0);
});

test('fails safely when the row selection and the checkbox disagree after the click', async () => {
    const page = await openSyncPage({ plots: [plot(0)] });
    page.sync.prepareScope();
    for (const row of rowsOf(page, 'GH1-A01')) row.setAttribute('aria-selected', 'true');

    const result = await page.sync.syncSelection('GH1-A01', false);
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'state_not_aligned_after_click');
});

test('reports plots that are not visible or not operable instead of throwing', async () => {
    const page = await openSyncPage();
    assert.equal((await page.sync.syncSelection('GH1-A01', true)).reason, 'scope_not_prepared');

    page.sync.prepareScope();
    assert.equal((await page.sync.syncSelection('GH9-Z99', true)).reason, 'plot_not_visible');

    page.document.querySelector('[data-pinned] [role="row"][data-row-id] input').disabled = true;
    assert.equal((await page.sync.syncSelection('GH1-A01', true)).reason, 'checkbox_disabled');
});

test('throws instead of returning an empty row list when the scope is not prepared', async () => {
    const page = await openSyncPage();
    assert.throws(() => page.sync.readVisibleRows(), /操作スコープが準備されていない/);
});

test('confirms the analysis request item became enabled without ever clicking it', async () => {
    const page = await openSyncPage();
    let requestClicks = 0;
    page.document.querySelector('[data-command="request-analysis"]').addEventListener('click', () => { requestClicks++; });
    page.sync.prepareScope();

    const before = page.sync.checkAnalysisMenu();
    assert.ok(failedChecks(before).includes('postSelection.requestItem.enabled'));

    await page.sync.syncSelection('GH1-A03', true);
    const after = page.sync.checkAnalysisMenu();
    assert.equal(after.ok, true, JSON.stringify(failedChecks(after)));
    assert.equal(requestClicks, 0);
});

test('rejects a request item outside the selected-plots group', async () => {
    const page = await openSyncPage();
    page.document.querySelector('[role="group"][aria-label="選択区画"]').setAttribute('aria-label', '全区画');
    assert.ok(failedChecks(page.sync.checkAnalysisMenu()).includes('postSelection.requestItem.unique'));
});

test('scroll actions report whether the position changed', async () => {
    const page = await openSyncPage();
    page.sync.prepareScope();
    const down = await page.sync.scrollDown();
    assert.equal(down.ok, true);
    assert.equal(typeof down.changed, 'boolean');
    assert.equal((await page.sync.scrollToTop()).ok, true);
});
