/* Headless browser tests for route watching, placement, namespace and recovery. */
'use strict';

const assert = require('assert');
const path = require('path');
const {chromium} = require('playwright');

const scriptPath = path.resolve(__dirname, '../src/www/ts-cert.js');

(async function() {
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage();
  const calls = [];
  let enabled = false;

  await page.route('http://router/**', async route => {
    const request = route.request();
    if (request.url() === 'http://router/rpc') {
      const body = JSON.parse(request.postData());
      calls.push(body);
      const method = body.params[2];
      if (method === 'set_config') enabled = body.params[3].enabled;
      const result = {
        enabled,
        state: enabled ? 'valid' : 'disabled',
        message: enabled ? 'Certificate is valid' : 'Certificate management is disabled',
        fqdn: enabled ? 'router.test-tail.ts.net' : '',
        expiry: enabled ? 'Oct 4 12:00:00 2026 GMT' : '',
        last_success: enabled ? 1785800000 : 0,
        last_renewal: 0,
        version: '0.1.6'
      };
      await route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify({jsonrpc: '2.0', id: body.id, result})});
      return;
    }
    await route.fulfill({status: 200, contentType: 'text/html', body: '<!doctype html><html><head></head><body><div id="app"><div id="view"><ul class="tailscale-config"><li>Native</li></ul></div></div></body></html>'});
  });

  await page.goto('http://router/gl_home.html#/tailscaleview');
  await page.addScriptTag({path: scriptPath});
  await page.waitForSelector('#ts-cert-section');

  assert.strictEqual(await page.locator('.ts-cert-label').textContent(), 'Automatic certificate management');
  assert((await page.locator('.ts-cert-guidance').textContent()).includes('Certificate Transparency logs'));
  await page.waitForFunction(() => document.getElementById('ts-cert-status-state').textContent.includes('Disabled'));
  assert.strictEqual(await page.locator('#ts-cert-message').textContent(), '', 'normal disabled state must not repeat in the action area');

  let placement = await page.evaluate(() => {
    const nativeList = document.querySelector('ul.tailscale-config');
    return nativeList.nextSibling && nativeList.nextSibling.id;
  });
  assert.strictEqual(placement, 'ts-cert-section', 'cert panel should follow native config when ts-fix is absent');

  const ids = await page.locator('#ts-cert-section [id]').evaluateAll(nodes => nodes.map(node => node.id));
  assert(ids.every(id => id.indexOf('ts-cert-') === 0), 'all panel IDs must use the ts-cert namespace');

  await page.evaluate(() => {
    const nativeList = document.querySelector('ul.tailscale-config');
    const fix = document.createElement('section');
    fix.id = 'ts-fix-section';
    nativeList.parentNode.insertBefore(fix, nativeList.nextSibling);
  });
  await page.waitForFunction(() => document.getElementById('ts-fix-section').nextSibling.id === 'ts-cert-section');

  await page.click('#ts-cert-toggle-enabled');
  await page.waitForFunction(() => document.getElementById('ts-cert-toggle-enabled').getAttribute('aria-checked') === 'true');
  const setCall = calls.find(call => call.params[2] === 'set_config');
  assert(setCall, 'toggle must call its own set_config RPC');
  assert.strictEqual(setCall.params[1], 'ts-cert');
  assert.strictEqual(setCall.params[3].enabled, true);

  await page.evaluate(() => {
    const view = document.getElementById('view');
    view.innerHTML = '<ul class="tailscale-config"><li>Native rerender</li></ul><section id="ts-fix-section"></section>';
  });
  await page.waitForFunction(() => {
    const fix = document.getElementById('ts-fix-section');
    return fix && fix.nextSibling && fix.nextSibling.id === 'ts-cert-section';
  });
  assert.strictEqual(await page.locator('#ts-cert-section').count(), 1, 'Vue recovery must remain idempotent');

  await page.evaluate(() => localStorage.setItem('theme', 'dark'));
  await page.evaluate(() => {
    const fix = document.getElementById('ts-fix-section');
    fix.parentNode.insertBefore(document.getElementById('ts-cert-section'), fix.nextSibling);
  });
  await page.waitForFunction(() => document.getElementById('ts-cert-section').classList.contains('ts-cert-dark'));

  assert.strictEqual(await page.locator('#ts-cert-styles').count(), 1, 'styles must be injected once');
  assert.strictEqual(await page.locator('#ts-cert-section').count(), 1, 'panel must be injected once');
  assert.strictEqual(calls.some(call => call.params[1] === 'ts-fix'), false, 'panel must never call ts-fix RPC');

  await browser.close();
  console.log('ok - WebUI placement, RPC namespace, theme and Vue re-render recovery');
})().catch(error => {
  console.error(error.stack || error);
  process.exit(1);
});
