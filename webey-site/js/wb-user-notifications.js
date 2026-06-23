(function () {
  'use strict';

  const PANEL_ID = 'wbUserNotifPanel';
  const BADGE_SELECTOR = '.wb-notif-badge';
  let _pollTimer = null;
  let _loading = false;

  function $(sel, root) {
    return (root || document).querySelector(sel);
  }
  function $$(sel, root) {
    return Array.from((root || document).querySelectorAll(sel));
  }
  function esc(s) {
    return String(s || '').replace(/[&<>"']/g, function (m) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m] || m;
    });
  }

  function apiGet(path, params) {
    if (window.WbApi && typeof window.WbApi.get === 'function') {
      return window.WbApi.get(path, params);
    }
    const u = new URL(path, location.origin);
    if (params && typeof params === 'object') {
      Object.keys(params).forEach(function (k) {
        if (params[k] !== undefined && params[k] !== null) u.searchParams.set(k, params[k]);
      });
    }
    return fetch(u.toString(), { credentials: 'include' }).then(function (r) { return r.json(); });
  }

  function apiPost(path, body) {
    if (window.WbApi && typeof window.WbApi.post === 'function') {
      return window.WbApi.post(path, body || {});
    }
    return fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(body || {})
    }).then(function (r) { return r.json(); });
  }

  function unwrap(x) {
    if (!x) return null;
    if (x.ok === true && x.data !== undefined) return x.data;
    return x;
  }

  function fmtDT(v) {
    if (!v) return '';
    const d = new Date(String(v).replace(' ', 'T'));
    if (isNaN(d.getTime())) return String(v);
    return d.toLocaleString('tr-TR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function typeIcon(t) {
    const s = String(t || '').toLowerCase();
    if (s === 'appt_approved') return 'fa-circle-check';
    if (s === 'appt_cancelled' || s === 'appt_rejected') return 'fa-circle-xmark';
    return 'fa-circle-info';
  }

  function setBadges(unread) {
    const n = Math.max(0, Number(unread || 0));
    $$(BADGE_SELECTOR).forEach(function (b) {
      b.textContent = String(n);
      b.classList.toggle('hidden', n <= 0);
    });
  }

  function render(items) {
    const panel = document.getElementById(PANEL_ID);
    if (!panel) return;

    if (!Array.isArray(items) || items.length === 0) {
      panel.innerHTML = '<div style="text-align:center;padding:40px;color:#9ca3af">Henüz bildiriminiz yok.</div>';
      return;
    }

    panel.innerHTML = items.map(function (it) {
      const isRead = !!it.isRead;
      return (
        '<article class="wb-un-card' + (isRead ? '' : ' wb-un-card--unread') + '" data-id="' + esc(it.id) + '"' +
        ' style="border:1px solid #e5e7eb;border-radius:12px;padding:12px 14px;margin-bottom:10px;background:' + (isRead ? '#fff' : '#f0f9ff') + '">' +
        '<div style="display:flex;justify-content:space-between;gap:10px;align-items:flex-start">' +
        '<div style="display:flex;gap:10px;align-items:flex-start">' +
        '<i class="fa-solid ' + typeIcon(it.type) + '" style="margin-top:2px;color:' + (isRead ? '#6b7280' : '#0ea5b3') + '"></i>' +
        '<div>' +
        '<div style="font-weight:700;color:#111827">' + esc(it.title || 'Bildirim') + '</div>' +
        '<div style="font-size:13px;color:#374151;margin-top:3px">' + esc(it.message || '') + '</div>' +
        (it.businessName ? '<div style="font-size:12px;color:#6b7280;margin-top:4px">' + esc(it.businessName) + '</div>' : '') +
        '<div style="font-size:12px;color:#9ca3af;margin-top:6px">' + esc(fmtDT(it.createdAt)) + '</div>' +
        '</div></div>' +
        (!isRead ? '<button type="button" class="wb-un-read-btn" style="border:none;background:#e0f2fe;color:#0369a1;border-radius:8px;padding:6px 10px;font-size:12px;cursor:pointer">Okundu</button>' : '') +
        '</div></article>'
      );
    }).join('');

    $$('.wb-un-read-btn', panel).forEach(function (btn) {
      btn.addEventListener('click', async function (e) {
        const card = e.currentTarget.closest('[data-id]');
        if (!card) return;
        const id = card.getAttribute('data-id');
        try {
          await apiPost('/api/user/notifications/mark-read.php', { id: id });
          await loadPanelData();
        } catch (err) {
          console.warn('[wbUserNotif mark-read]', err);
        }
      });
    });
  }

  async function loadPanelData() {
    if (_loading) return;
    _loading = true;
    try {
      const raw = await apiGet('/api/user/notifications/list.php', { limit: 50, offset: 0 });
      const data = unwrap(raw) || {};
      const items = data.items || data.notifications || [];
      render(items);
      setBadges(data.unreadCount || data.unread || 0);
    } catch (e) {
      console.warn('[wbUserNotif load]', e);
      const panel = document.getElementById(PANEL_ID);
      if (panel) panel.innerHTML = '<div style="text-align:center;padding:40px;color:#ef4444">Bildirimler yüklenemedi.</div>';
    } finally {
      _loading = false;
    }
  }

  async function markAllRead() {
    try {
      await apiPost('/api/user/notifications/mark-all-read.php', {});
      await loadPanelData();
    } catch (e) {
      console.warn('[wbUserNotif mark-all-read]', e);
    }
  }

  function startPolling() {
    stopPolling();
    _pollTimer = setInterval(function () {
      const visible = !document.hidden;
      if (visible) loadPanelData();
    }, 15000);
  }

  function stopPolling() {
    if (_pollTimer) clearInterval(_pollTimer);
    _pollTimer = null;
  }

  window.wbUserNotif = {
    loadPanelData: loadPanelData,
    markAllRead: markAllRead,
    start: startPolling,
    stop: stopPolling
  };

  document.addEventListener('DOMContentLoaded', function () {
    loadPanelData();
    startPolling();
  });
})();

