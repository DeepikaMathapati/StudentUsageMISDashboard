// Uses Chrome DevTools Protocol with Node's built-in WebSocket. No npm packages required.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const baseUrl = process.argv[2] || 'http://localhost:5277';
const debugUrl = process.argv[3] || 'http://localhost:9223';
const output = path.resolve(__dirname, '../bin/dashboard-verification');
fs.mkdirSync(output, { recursive: true });
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
    const target = await (await fetch(`${debugUrl}/json/new?about:blank`, { method: 'PUT' })).json();
    const socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
    let sequence = 0, checks = 0;
    const pending = new Map(), errors = [];
    socket.onmessage = event => {
        const message = JSON.parse(event.data);
        if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
        if (message.id) {
            const request = pending.get(message.id);
            if (request) { pending.delete(message.id); clearTimeout(request.timer); message.error ? request.reject(new Error(JSON.stringify(message.error))) : request.resolve(message.result); }
        }
    };
    function call(method, params = {}) {
        return new Promise((resolve, reject) => {
            const id = ++sequence;
            const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timed out: ${method}`)); }, 30000);
            pending.set(id, { resolve, reject, timer }); socket.send(JSON.stringify({ id, method, params }));
        });
    }
    async function evaluate(expression) {
        const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
        if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
        return result.result.value;
    }
    async function waitFor(expression) {
        for (let i = 0; i < 200; i++) { if (await evaluate(expression)) return; await pause(100); }
        throw new Error(`Condition timed out: ${expression}`);
    }
    async function navigate(url) {
        await call('Page.navigate', { url });
        await waitFor('document.readyState === "complete" && !!document.querySelector(".dashboard")');
    }
    async function screenshot(name) {
        const shot = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
        fs.writeFileSync(path.join(output, name), Buffer.from(shot.data, 'base64'));
    }
    function check(condition, message) { assert.ok(condition, message); checks++; }
    try {
        await call('Page.enable'); await call('Runtime.enable');
        await call('Emulation.setDeviceMetricsOverride', { width: 1366, height: 1000, deviceScaleFactor: 1, mobile: false });
        await navigate(baseUrl);
        await waitFor('!!document.querySelector(".donut")');
        check(await evaluate('document.querySelector(".brand img").complete && document.querySelector(".brand img").naturalWidth > 0'), 'Logo loads');
        check(await evaluate('document.querySelectorAll("#district-chart .bar-row").length === 3'), 'Three district bars render');
        check(await evaluate('document.querySelectorAll(".trend-chart svg").length === 2'), 'Both trend charts render');
        const original = await evaluate('JSON.parse(document.getElementById("dashboard-data").textContent)');
        check(original.daily.length === 30, 'Default daily chart includes September data');
        await screenshot('desktop.png');
        for (const id of ['district', 'daily', 'school', 'monthly', 'yearly', 'bucket']) {
            await evaluate(`document.querySelector('[data-tab="${id}"]').click()`);
            check(await evaluate(`!document.getElementById('panel-${id}').hidden && document.querySelectorAll('.tab-panel:not([hidden])').length === 1`), `Tab ${id} works`);
        }
        await evaluate('document.querySelector("#tab-bucket").focus()');
        await call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowRight', code: 'ArrowRight' });
        await call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'ArrowRight', code: 'ArrowRight' });
        check(await evaluate('document.activeElement.id === "tab-district" && !document.getElementById("panel-district").hidden'), 'Keyboard tab navigation works');
        await evaluate('document.querySelector("#from-date").value="2026-09-01"; document.querySelector("#to-date").value="2026-09-07"; document.querySelector("#duration-unit").value="Hours"; document.querySelector("#usage-type").value="Video"; document.querySelector(".filter-bar button").click()');
        await waitFor('location.search.includes("UsageType=Video") && document.readyState === "complete" && !!document.querySelector(".donut")');
        const filtered = await evaluate('JSON.parse(document.getElementById("dashboard-data").textContent)');
        check(filtered.unit === 'Hours' && filtered.daily.length === 7, 'Date, type and unit form filters apply');
        check(filtered.daily[0].usage !== original.daily[0].usage, 'Chart values change with filters');
        check(await evaluate('document.querySelectorAll("#daily-usage-chart circle").length === 7'), 'Filtered daily chart has seven points');
        check(await evaluate('document.querySelector("#daily-usage-chart circle title").textContent.startsWith("2026-09-01:")'), 'Daily chart has data tooltips');
        for (const link of await evaluate('[...document.querySelectorAll(".report-actions a, .section-heading a")].map(a=>a.href)')) {
            const url = new URL(link);
            check(url.searchParams.get('From') === '2026-09-01' && url.searchParams.get('To') === '2026-09-07' && url.searchParams.get('UsageType') === 'Video' && url.searchParams.get('Unit') === 'Hours', 'Export URL preserves all filters');
        }
        await call('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: output });
        await evaluate('document.querySelector(".report-actions a").click()');
        const download = path.join(output, 'student-monthly-20260901-20260907.csv');
        for (let i = 0; i < 100 && !fs.existsSync(download); i++) await pause(100);
        check(fs.existsSync(download), 'CSV download through browser succeeds');
        check(fs.readFileSync(download, 'utf8').includes('2026-09-01,2026-09-07,"Video",Hours'), 'Downloaded CSV has selected filters');
        await evaluate('document.querySelector("[data-nav-tab=daily]").click()');
        check(await evaluate('!document.querySelector("#panel-daily").hidden && location.search.includes("UsageType=Video")'), 'Sidebar keeps selected filters');
        await screenshot('daily-filtered.png');
        await evaluate('document.querySelector(".reset-link").click()');
        await waitFor('location.search === "" && document.readyState === "complete" && !!document.querySelector(".donut")');
        check(await evaluate('document.getElementById("duration-unit").value === "Minutes" && document.getElementById("usage-type").value === "All"'), 'Reset restores defaults');
        const layouts = [];
        for (const width of [1920, 1366, 1024, 768, 390, 360]) {
            await call('Emulation.setDeviceMetricsOverride', { width, height: 1000, deviceScaleFactor: 1, mobile: width < 760 });
            await pause(100);
            const metrics = await evaluate('({ viewport: innerWidth, document: document.documentElement.scrollWidth, cards: [...document.querySelectorAll(".kpi")].map(x=>({width:x.clientWidth,scroll:x.scrollWidth})), panel:document.querySelector("#panel-bucket").clientWidth, panelScroll:document.querySelector("#panel-bucket").scrollWidth })');
            layouts.push({ width, ...metrics });
            check(metrics.document <= metrics.viewport, `No page overflow at ${width}px`);
            check(metrics.cards.every(card => card.scroll <= card.width), `KPI cards fit at ${width}px`);
            check(metrics.panelScroll <= metrics.panel, `Overview content fits at ${width}px`);
            for (const id of ['district', 'daily', 'school', 'monthly', 'yearly']) {
                await evaluate(`document.querySelector('[data-tab="${id}"]').click()`);
                check(await evaluate('document.documentElement.scrollWidth <= innerWidth'), `Report ${id} has no page overflow at ${width}px`);
                if (id === 'district') {
                    check(await evaluate('[...document.querySelectorAll(".bar-row > span:first-child")].every(label => label.scrollWidth <= label.clientWidth)'), `District labels fit their columns at ${width}px`);
                    if (width === 390) await screenshot('district-mobile.png');
                }
            }
            await evaluate('document.querySelector("#tab-bucket").click()');
            if (width === 390) {
                await screenshot('mobile.png');
                await evaluate('document.querySelector(".menu-toggle").click()');
                check(await evaluate('document.body.classList.contains("nav-open") && document.querySelector(".menu-toggle").getAttribute("aria-expanded") === "true"'), 'Mobile menu opens');
                await evaluate('document.querySelector("[data-nav-tab=school]").click()');
                check(await evaluate('!document.body.classList.contains("nav-open") && !document.querySelector("#panel-school").hidden'), 'Mobile navigation selects report and closes');
                await evaluate('document.querySelector("#tab-bucket").click()');
            }
        }
        check(errors.length === 0, 'No browser JavaScript exceptions');
        const summary = { checks, errors, layouts, filteredUnit: filtered.unit, filteredDays: filtered.daily.length };
        fs.writeFileSync(path.join(output, 'browser-results.json'), JSON.stringify(summary, null, 2));
        console.log(`PASS: ${checks} browser assertions. Screenshots and download in ${output}`);
    } finally { socket.close(); await fetch(`${debugUrl}/json/close/${target.id}`); }
})().catch(error => { console.error(error); process.exitCode = 1; });
