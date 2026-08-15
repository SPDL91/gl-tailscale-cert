/**
 * gl-tailscale-cert WebUI panel
 * SPDX-License-Identifier: GPL-3.0-only
 */
(function() {
'use strict';

var ROUTE = '#/tailscaleview';
var SECTION_ID = 'ts-cert-section';
var STYLE_ID = 'ts-cert-styles';
var STORAGE_KEY = 'ts-cert-panel-collapsed';
var VERSION = '{{VERSION}}';
var refreshTimer = null;
var renewTimer = null;
var routeTimers = [];
var observer = null;
var busy = false;

function rpc(method, params) {
  var token = (document.cookie.match(/Admin-Token=([^;]+)/) || [])[1] || '';
  return fetch('/rpc', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      jsonrpc: '2.0', id: Date.now(), method: 'call',
      params: [token, 'ts-cert', method, params || {}]
    })
  }).then(function(response) { return response.json(); })
    .then(function(payload) {
      if (payload.error) throw new Error(payload.error.message || 'RPC error');
      var result = payload.result || {};
      if (result.err_code) throw new Error(result.err_msg || 'Operation failed');
      return result;
    });
}

function onRoute() {
  return window.location.hash.indexOf(ROUTE) === 0;
}

function safeStorageGet(key) {
  try { return localStorage.getItem(key); } catch (error) { return null; }
}

function safeStorageSet(key, value) {
  try { localStorage.setItem(key, value); } catch (error) {}
}

function injectStyles() {
  if (document.getElementById(STYLE_ID)) return;
  var style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = [
    '#ts-cert-section{margin-top:18px;font-size:14px;color:#3b4652}',
    '#ts-cert-section.ts-cert-dark{color:#d8dee8}',
    '.ts-cert-card{border:1px solid #e1e6eb;border-radius:8px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.06);overflow:hidden}',
    '.ts-cert-dark .ts-cert-card{background:#252b33;border-color:#3b4551}',
    '.ts-cert-heading{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;border-bottom:1px solid #edf0f2;font-weight:600}',
    '.ts-cert-dark .ts-cert-heading{border-color:#3b4551}',
    '.ts-cert-version{font-size:11px;font-weight:500;opacity:.68}',
    '.ts-cert-body{padding:16px}',
    '.ts-cert-row{display:flex;gap:18px;align-items:center;justify-content:space-between;margin-bottom:14px}',
    '.ts-cert-label{font-weight:600;color:inherit}',
    '.ts-cert-guidance{font-size:12px;line-height:1.45;opacity:.76;margin-top:5px;max-width:620px}',
    '.ts-cert-toggle{position:relative;width:42px;height:23px;padding:0;border:0;border-radius:15px;background:#a8b0b8;cursor:pointer;flex:0 0 auto}',
    '.ts-cert-toggle:before{content:"";position:absolute;width:19px;height:19px;left:2px;top:2px;border-radius:50%;background:#fff;transition:transform .18s}',
    '.ts-cert-toggle[aria-checked="true"]{background:#2f7cf6}',
    '.ts-cert-toggle[aria-checked="true"]:before{transform:translateX(19px)}',
    '.ts-cert-toggle:disabled{opacity:.5;cursor:wait}',
    '.ts-cert-status{display:grid;grid-template-columns:minmax(115px,auto) 1fr;gap:8px 14px;padding:12px;border-radius:6px;background:#f5f7f9}',
    '.ts-cert-dark .ts-cert-status{background:#1c2127}',
    '.ts-cert-status dt{font-weight:600;opacity:.72}',
    '.ts-cert-status dd{margin:0;overflow-wrap:anywhere}',
    '.ts-cert-state{display:inline-flex;align-items:center;gap:6px;font-weight:600}',
    '.ts-cert-dot{width:8px;height:8px;border-radius:50%;background:#87919b}',
    '.ts-cert-state-valid .ts-cert-dot{background:#26a269}',
    '.ts-cert-state-error .ts-cert-dot,.ts-cert-state-renewal_due .ts-cert-dot{background:#d64545}',
    '.ts-cert-state-checking .ts-cert-dot,.ts-cert-state-renewing .ts-cert-dot,.ts-cert-state-waiting .ts-cert-dot{background:#e6a700}',
    '.ts-cert-actions{display:flex;align-items:center;gap:12px;margin-top:14px}',
    '.ts-cert-button{border:1px solid #2f7cf6;color:#2f7cf6;background:transparent;border-radius:5px;padding:7px 13px;cursor:pointer;font-weight:600}',
    '.ts-cert-button:hover:not(:disabled){background:#2f7cf6;color:#fff}',
    '.ts-cert-button:disabled{opacity:.45;cursor:not-allowed}',
    '.ts-cert-message{font-size:12px;min-height:18px;opacity:.8}',
    '.ts-cert-collapse{border:0;background:transparent;color:inherit;cursor:pointer;font-size:18px;line-height:1}',
    '.ts-cert-collapsed .ts-cert-body{display:none}',
    '@media(max-width:560px){.ts-cert-status{grid-template-columns:1fr}.ts-cert-status dt{margin-top:4px}}'
  ].join('');
  document.head.appendChild(style);
}

function element(tag, className, text) {
  var node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function addStatusRow(list, label, id) {
  list.appendChild(element('dt', '', label));
  var value = element('dd');
  value.id = id;
  value.textContent = '—';
  list.appendChild(value);
}

function buildSection() {
  var section = element('section');
  section.id = SECTION_ID;

  var card = element('div', 'ts-cert-card');
  var heading = element('div', 'ts-cert-heading');
  var title = element('div', '', 'Tailscale HTTPS certificate');
  title.appendChild(element('div', 'ts-cert-version', 'gl-tailscale-cert v' + VERSION));
  var collapse = element('button', 'ts-cert-collapse', '⌃');
  collapse.id = 'ts-cert-collapse';
  collapse.type = 'button';
  collapse.setAttribute('aria-label', 'Collapse certificate panel');
  heading.appendChild(title);
  heading.appendChild(collapse);

  var body = element('div', 'ts-cert-body');
  var toggleRow = element('div', 'ts-cert-row');
  var toggleText = element('div');
  toggleText.appendChild(element('div', 'ts-cert-label', 'Automatic certificate management'));
  toggleText.appendChild(element('div', 'ts-cert-guidance', 'Requires MagicDNS and HTTPS Certificates. Issuance publishes this hostname in Certificate Transparency logs.'));
  var toggle = element('button', 'ts-cert-toggle');
  toggle.id = 'ts-cert-toggle-enabled';
  toggle.type = 'button';
  toggle.setAttribute('role', 'switch');
  toggle.setAttribute('aria-checked', 'false');
  toggle.setAttribute('aria-label', 'Automatic Tailscale HTTPS certificate management');
  toggleRow.appendChild(toggleText);
  toggleRow.appendChild(toggle);

  var status = element('dl', 'ts-cert-status');
  addStatusRow(status, 'Status', 'ts-cert-status-state');
  addStatusRow(status, 'Hostname', 'ts-cert-status-fqdn');
  addStatusRow(status, 'Expires', 'ts-cert-status-expiry');
  addStatusRow(status, 'Last successful check', 'ts-cert-status-success');
  addStatusRow(status, 'Last renewal', 'ts-cert-status-renewal');

  var actions = element('div', 'ts-cert-actions');
  var renew = element('button', 'ts-cert-button', 'Renew now');
  renew.id = 'ts-cert-renew';
  renew.type = 'button';
  var message = element('div', 'ts-cert-message');
  message.id = 'ts-cert-message';
  actions.appendChild(renew);
  actions.appendChild(message);

  body.appendChild(toggleRow);
  body.appendChild(status);
  body.appendChild(actions);
  card.appendChild(heading);
  card.appendChild(body);
  section.appendChild(card);

  var collapsed = safeStorageGet(STORAGE_KEY) === '1';
  if (collapsed) section.classList.add('ts-cert-collapsed');
  collapse.textContent = collapsed ? '⌄' : '⌃';
  collapse.addEventListener('click', function() {
    collapsed = !collapsed;
    section.classList.toggle('ts-cert-collapsed', collapsed);
    collapse.textContent = collapsed ? '⌄' : '⌃';
    collapse.setAttribute('aria-label', collapsed ? 'Expand certificate panel' : 'Collapse certificate panel');
    safeStorageSet(STORAGE_KEY, collapsed ? '1' : '0');
  });

  toggle.addEventListener('click', function() {
    if (busy) return;
    var enabled = toggle.getAttribute('aria-checked') !== 'true';
    setBusy(true, enabled ? 'Enabling…' : 'Disabling…');
    rpc('set_config', {enabled: enabled}).then(function(result) {
      render(result);
      setBusy(false, '');
      scheduleRefresh(900);
    }).catch(showError);
  });

  renew.addEventListener('click', function() {
    if (busy || toggle.getAttribute('aria-checked') !== 'true') return;
    setBusy(true, 'Starting renewal…');
    rpc('renew_now', {}).then(function() {
      pollRenewal(0);
    }).catch(showError);
  });
  return section;
}

function formatEpoch(value) {
  var number = Number(value || 0);
  return number > 0 ? new Date(number * 1000).toLocaleString() : '—';
}

function formatExpiry(value) {
  if (!value) return '—';
  var parsed = new Date(value);
  if (isNaN(parsed.getTime())) return value;
  var days = Math.ceil((parsed.getTime() - Date.now()) / 86400000);
  return parsed.toLocaleString() + ' (' + days + ' days)';
}

function setText(id, value) {
  var node = document.getElementById(id);
  if (node) node.textContent = value || '—';
}

function setMessage(value) {
  var node = document.getElementById('ts-cert-message');
  if (node) node.textContent = value || '';
}

function render(data) {
  var section = document.getElementById(SECTION_ID);
  if (!section) return;
  syncTheme(section);
  var enabled = data.enabled === true;
  var toggle = document.getElementById('ts-cert-toggle-enabled');
  toggle.setAttribute('aria-checked', enabled ? 'true' : 'false');

  var state = data.state || (enabled ? 'unknown' : 'disabled');
  var status = document.getElementById('ts-cert-status-state');
  status.className = 'ts-cert-state ts-cert-state-' + state.replace(/[^a-z_]/g, '');
  status.textContent = '';
  status.appendChild(element('span', 'ts-cert-dot'));
  var stateLabel = state.replace(/_/g, ' ');
  status.appendChild(document.createTextNode(' ' + stateLabel.charAt(0).toUpperCase() + stateLabel.slice(1)));

  setText('ts-cert-status-fqdn', data.fqdn);
  setText('ts-cert-status-expiry', formatExpiry(data.expiry));
  setText('ts-cert-status-success', formatEpoch(data.last_success));
  setText('ts-cert-status-renewal', formatEpoch(data.last_renewal));
  var showMessage = state === 'error' || state === 'renewal_due' || state === 'waiting' ||
    state === 'checking' || state === 'renewing';
  setMessage(showMessage ? (data.message || '') : '');
  document.getElementById('ts-cert-renew').disabled = busy || !enabled;
  toggle.disabled = busy;
  try {
    window.dispatchEvent(new CustomEvent('ts-cert:updated', {detail: {state: state, enabled: enabled}}));
  } catch (error) {}
}

function setBusy(value, message) {
  busy = value;
  var toggle = document.getElementById('ts-cert-toggle-enabled');
  var renew = document.getElementById('ts-cert-renew');
  if (toggle) toggle.disabled = value;
  if (renew) renew.disabled = value || (toggle && toggle.getAttribute('aria-checked') !== 'true');
  setMessage(message || '');
}

function showError(error) {
  setBusy(false, error && error.message ? error.message : 'Operation failed');
  scheduleRefresh(1200);
}

function refresh() {
  if (!onRoute() || !document.getElementById(SECTION_ID)) return;
  rpc('get_config', {}).then(render).catch(function(error) {
    setMessage(error.message || 'Status unavailable');
  });
}

function scheduleRefresh(delay) {
  var timer = setTimeout(refresh, delay);
  routeTimers.push(timer);
}

function pollRenewal(attempt) {
  if (!onRoute() || attempt >= 60) {
    setBusy(false, attempt >= 60 ? 'Renewal is still running; status will continue to refresh.' : '');
    return;
  }
  rpc('get_status', {}).then(function(status) {
    render(status);
    if (attempt < 2 || status.state === 'checking' || status.state === 'renewing' || status.action === 'request') {
      renewTimer = setTimeout(function() { pollRenewal(attempt + 1); }, 2000);
    } else {
      setBusy(false, status.state === 'error' || status.state === 'renewal_due' ? (status.message || 'Renewal failed.') : '');
      refresh();
    }
  }).catch(function(error) {
    if (attempt < 5) renewTimer = setTimeout(function() { pollRenewal(attempt + 1); }, 2000);
    else showError(error);
  });
}

function syncTheme(section) {
  var dark = safeStorageGet('theme') === 'dark' || document.documentElement.classList.contains('dark');
  section.classList.toggle('ts-cert-dark', dark);
}

function placeSection() {
  if (!onRoute()) return;
  var nativeList = document.querySelector('ul.tailscale-config');
  if (!nativeList) return;
  injectStyles();
  var section = document.getElementById(SECTION_ID);
  var changed = false;
  if (!section) {
    section = buildSection();
    changed = true;
  }
  var anchor = document.getElementById('ts-fix-section') || nativeList;
  if (anchor.nextSibling !== section) {
    anchor.parentNode.insertBefore(section, anchor.nextSibling);
    changed = true;
  }
  syncTheme(section);
  if (changed) refresh();
}

function clearRouteTimers() {
  routeTimers.forEach(clearTimeout);
  routeTimers = [];
  if (renewTimer) { clearTimeout(renewTimer); renewTimer = null; }
}

function startRefresh() {
  if (refreshTimer) return;
  refreshTimer = setInterval(function() {
    if (onRoute()) {
      placeSection();
      refresh();
    }
  }, 15000);
}

function stopRefresh() {
  if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
  clearRouteTimers();
}

function routeChanged() {
  if (!onRoute()) {
    stopRefresh();
    return;
  }
  [250, 700, 1400].forEach(function(delay) {
    var timer = setTimeout(placeSection, delay);
    routeTimers.push(timer);
  });
  startRefresh();
}

function startObserver() {
  if (observer) return;
  observer = new MutationObserver(function() {
    if (!onRoute()) return;
    var nativeList = document.querySelector('ul.tailscale-config');
    if (!nativeList) return;
    var section = document.getElementById(SECTION_ID);
    var anchor = document.getElementById('ts-fix-section') || nativeList;
    if (!section || anchor.nextSibling !== section) placeSection();
  });
  observer.observe(document.getElementById('app') || document.body, {childList: true, subtree: true});
}

window.addEventListener('hashchange', routeChanged);
routeChanged();
startObserver();

})();
