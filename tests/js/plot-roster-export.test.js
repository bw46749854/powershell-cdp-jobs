'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { SCRIPTS, loadPage, failedChecks } = require('./support/page');
const { greenhouseConsoleHtml, wireMenus } = require('./fixtures/greenhouse-console');

async function openRosterPage(options) {
    const page = await loadPage({ html: greenhouseConsoleHtml(options), scripts: SCRIPTS.plotRosterExport, setup: wireMenus });
    return Object.assign(page, { roster: page.helper('plotRosterExport') });
}

test('reports the methods the PowerShell catalog relies on', async () => {
    const page = await openRosterPage();
    const ack = page.kit.ack('plotRosterExport');
    assert.equal(ack.ok, true);
    for (const method of ['detectScreen', 'checkInitialScreen', 'checkExportScreen', 'openTaskMenu', 'isExportItemReady', 'clickExportItem', 'checkExportAccepted']) {
        assert.ok(ack.methods.includes(method), method);
    }
});

test('identifies the plot list screen of the default group', async () => {
    const page = await openRosterPage();
    const identity = page.roster.detectScreen();
    assert.equal(identity.scope, 'greenhousePlotList.identity');
    assert.equal(identity.ok, true, JSON.stringify(failedChecks(identity)));
});

test('does not identify the screen when another group is selected (meaning differs)', async () => {
    const page = await openRosterPage();
    const [all, house] = page.document.querySelectorAll('[role="treeitem"]');
    all.setAttribute('aria-selected', 'false');
    house.setAttribute('aria-selected', 'true');

    const identity = page.roster.detectScreen();
    assert.equal(identity.ok, false);
    assert.deepEqual(failedChecks(identity), ['identity.group.default.selected']);
});

test('accepts half-width parentheses in the default group name (formatting only)', async () => {
    const page = await openRosterPage();
    page.document.querySelector('[role="treeitem"][aria-selected="true"] span').textContent = '全区画 (既定)';
    assert.equal(page.roster.detectScreen().ok, true);
});

test('finds the section menu by its label when the data-nav hook disappears', async () => {
    const page = await openRosterPage();
    page.document.querySelector('[data-nav="plots"]').removeAttribute('data-nav');
    assert.equal(page.roster.detectScreen().ok, true);
});

test('validates the export screen and reads the plot count', async () => {
    const page = await openRosterPage({ count: 40 });
    const screen = page.roster.checkExportScreen();
    assert.equal(screen.ok, true, JSON.stringify(failedChecks(screen)));
    assert.equal(screen.details.plotCount, 40);
});

test('reads the plot count from the visible text when the count hook is removed', async () => {
    const page = await openRosterPage({ count: 40 });
    const count = page.document.querySelector('[data-count="plots"]');
    count.removeAttribute('data-count');
    count.textContent = '区画：40件';
    assert.equal(page.roster.readPlotCount().value, 40);
});

test('opens the task menu and clicks the export item through an extra wrapper', async () => {
    const page = await openRosterPage();
    let exported = 0;
    page.document.querySelector('[data-command="export"]').addEventListener('click', () => { exported++; });
    const item = page.document.querySelector('[data-command="export"]');
    const wrapper = page.document.createElement('span');
    item.replaceWith(wrapper);
    wrapper.appendChild(item);

    assert.equal(page.roster.isExportItemReady(), false);
    const opened = await page.roster.openTaskMenu();
    assert.equal(opened.action, 'menu-opened');
    assert.equal(page.roster.isExportItemReady(), true);

    const again = await page.roster.openTaskMenu();
    assert.equal(again.action, 'menu-already-open', 'an open menu must not be toggled closed');

    const click = await page.roster.clickExportItem();
    assert.equal(click.action, 'export-clicked');
    assert.equal(exported, 1);
    assert.equal(page.roster.checkExportAccepted().ok, true);
});

test('finds the menu next to the button when aria-controls is missing', async () => {
    const page = await openRosterPage();
    page.document.querySelector('[aria-controls="menu-actions"]').removeAttribute('aria-controls');
    page.document.getElementById('menu-actions').removeAttribute('hidden');
    assert.equal(page.roster.resolveExportItem().menuSource, 'nearest-ancestor');
    assert.equal(page.roster.isExportItemReady(), true);
});

test('rejects a renamed export item instead of guessing', async () => {
    const page = await openRosterPage();
    page.document.querySelector('[data-command="export"]').textContent = 'エクスポート';
    await page.roster.openTaskMenu();
    assert.equal(page.roster.isExportItemReady(), false);
    await assert.rejects(() => page.roster.clickExportItem(), /CSV出力」を1つに決められません/);
});

test('rejects two export items (ambiguous target)', async () => {
    const page = await openRosterPage();
    const menu = page.document.getElementById('menu-actions');
    const duplicate = page.document.createElement('div');
    duplicate.setAttribute('role', 'menuitem');
    duplicate.textContent = 'CSV出力';
    menu.appendChild(duplicate);
    await page.roster.openTaskMenu();
    assert.equal(page.roster.resolveExportItem().count, 2);
    assert.equal(page.roster.isExportItemReady(), false);
});

test('rejects a task button that no longer opens a menu', async () => {
    const page = await openRosterPage();
    page.document.querySelector('[aria-controls="menu-actions"]').removeAttribute('aria-haspopup');
    const screen = page.roster.checkExportScreen();
    assert.ok(failedChecks(screen).includes('exportScreen.taskButton.unique'));
});

test('does not accept the export before the export item was clicked', async () => {
    const page = await openRosterPage();
    const accepted = page.roster.checkExportAccepted();
    assert.equal(accepted.ok, false);
    assert.deepEqual(failedChecks(accepted), ['postExport.click.accepted']);
});

test('requires a finished document for the initial contract', async () => {
    const page = await openRosterPage();
    Object.defineProperty(page.document, 'readyState', { value: 'interactive', configurable: true });
    assert.deepEqual(failedChecks(page.roster.checkInitialScreen()), ['initial.document.ready']);
});
