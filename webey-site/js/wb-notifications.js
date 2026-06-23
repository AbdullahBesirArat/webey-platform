/**
 * wb-notifications.js — Webey Global Admin Bildirim Modülü
 * Tüm admin sayfalarında çalışır. Eğer sayfada #bellBtn ve #notify
 * elementleri yoksa otomatik olarak ekler.
 * Hem yeni randevu hem iptal taleplerini poll eder.
 */
(function () {
  'use strict';

  // calendar.js gibi modüllerin çift bildirim göstermesini önler.
  window.__WB_NOTIF_ACTIVE = true;

  /* ── Ayarlar ── */
  const POLL_INTERVAL_VISIBLE = 30000;  // 30sn
  const POLL_INTERVAL_HIDDEN  = 120000; // sekme arkadaysa 2dk
  const POLL_RETRY_BASE       = 10000;
  const API_BASE             = '';    // aynı origin
  const APP_BASE             = window.location.pathname.startsWith('/webey/') ? '/webey' : '';

  /* ── Durum ── */
  let _notifLastTs   = Math.floor(Date.now() / 1000) - 300;
  let _seenAppt      = new Set();
  let _seenCancel    = new Set();
  let _seenSub       = new Set();
  let _pollTimer     = null;
  let _pollRetry     = 0;
  let _isAdmin       = false;
  let _initialized   = false;
  let _seenGuide     = new Set();
  let _guideEnsured  = new Set();
  let _panelLoadedAt = 0;

  /* ════════════════════════════════════════════
     DOM HELPERS
  ════════════════════════════════════════════ */
  const $ = id => document.getElementById(id);
  const ap = (u='') => (APP_BASE && u.startsWith('/')) ? (APP_BASE + u) : u;
  const GUIDE_BOOTSTRAP_KEY_PREFIX = 'wb_admin_guides_bootstrapped:v2:';
  let _guideBootstrapKey = GUIDE_BOOTSTRAP_KEY_PREFIX + 'guest';

  function escHtml(s = '') {
    return String(s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  function fmtDT(isoOrSql) {
    if (!isoOrSql) return '';
    const d = new Date(String(isoOrSql).replace(' ','T'));
    if (isNaN(d)) return '';
    const p = n => String(n).padStart(2,'0');
    return `${p(d.getDate())}.${p(d.getMonth()+1)}.${d.getFullYear()} • ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /* ════════════════════════════════════════════
     SES
  ════════════════════════════════════════════ */
  function playSound() {
    const el = $('notiSound');
    if (el) { try { el.play()?.catch(()=>{}); } catch {} }
  }

  function guidesBootstrapped() {
    try {
      return window.localStorage.getItem(_guideBootstrapKey) === '1';
    } catch (_) {
      return false;
    }
  }

  function setGuidesBootstrapped() {
    try {
      window.localStorage.setItem(_guideBootstrapKey, '1');
    } catch (_) {}
  }

  function hiddenGuideStoreKey() {
    return _guideBootstrapKey + ':hidden';
  }

  function getHiddenGuideKeys() {
    try {
      const raw = window.localStorage.getItem(hiddenGuideStoreKey());
      const arr = JSON.parse(raw || '[]');
      return Array.isArray(arr) ? arr : [];
    } catch (_) {
      return [];
    }
  }

  function isGuideHidden(guideKey) {
    if (!guideKey) return false;
    return getHiddenGuideKeys().includes(String(guideKey));
  }

  function hideGuideKey(guideKey) {
    if (!guideKey) return;
    try {
      const next = new Set(getHiddenGuideKeys());
      next.add(String(guideKey));
      window.localStorage.setItem(hiddenGuideStoreKey(), JSON.stringify(Array.from(next)));
    } catch (_) {}
  }

  /* ════════════════════════════════════════════
     BELL / PANEL KURULUMU
  ════════════════════════════════════════════ */
  function setupBellAndPanel() {
    const isMobile = window.matchMedia('(max-width: 768px)').matches;

    // Eğer sayfada zaten bell ve notify varsa sadece event bind et
    // Mobilede floating bell ve panel inject etme
    if (!$('bellBtn') && !isMobile) {
      injectFloatingBell();
    }
    if (!$('notify') && !isMobile) {
      injectNotifyPanel();
    }
    if (!$('notiSound')) {
      const audio = document.createElement('audio');
      audio.id = 'notiSound';
      audio.src = ap('/sounds/notificationSound1.mp3');
      audio.preload = 'auto';
      document.body.appendChild(audio);
    }
    bindBellEvents();
    syncBell();
  }

  function injectFloatingBell() {
    const btn = document.createElement('button');
    btn.id        = 'bellBtn';
    btn.type      = 'button';
    btn.title     = 'Bildirimler';
    btn.setAttribute('aria-haspopup','dialog');
    btn.setAttribute('aria-expanded','false');
    btn.setAttribute('aria-controls','notify');
    btn.innerHTML = `
      <svg viewBox="0 0 24 24" aria-hidden="true" style="width:22px;height:22px">
        <path d="M15 17h5l-1.4-1.4A2 2 0 0 1 18 14.2V11a6 6 0 1 0-12 0v3.2c0 .53-.21 1.04-.59 1.41L4 17h5m6 0a3 3 0 1 1-6 0m6 0H9"
              stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </svg>
      <span id="bellCount" class="wb-bell-count" aria-live="polite" aria-atomic="true">0</span>`;

    // Floating buton stili
    const style = document.createElement('style');
    style.textContent = `
      #bellBtn.wb-floating-bell {
        position: fixed;
        top: 14px;
        right: 16px;
        z-index: 9200;
        width: 44px;
        height: 44px;
        border-radius: 50%;
        border: none;
        background: #1a1d23;
        color: #9ca3af;
        display: flex;
        align-items: center;
        justify-content: center;
        cursor: pointer;
        box-shadow: 0 2px 12px rgba(0,0,0,.3);
        transition: background .18s, color .18s;
      }
      #bellBtn.wb-floating-bell:hover { background: #252830; color: #fff; }
      /* Mobilede floating bell gizle */
      @media (max-width: 768px) {
        #bellBtn.wb-floating-bell { display: none !important; }
      }
      .wb-bell-count {
        position: absolute;
        top: 5px; right: 5px;
        width: 16px; height: 16px;
        border-radius: 50%;
        background: #ef4444;
        color: #fff;
        font-size: 10px;
        font-weight: 700;
        display: none;
        align-items: center;
        justify-content: center;
        line-height: 1;
      }
      .wb-bell-count.show { display: flex; }
      /* calendar sayfasındaki .bell-count için de destek */
      .bell-count { position:absolute; top:5px; right:5px; min-width:16px; height:16px; border-radius:50%; background:#ef4444; color:#fff; font-size:10px; font-weight:700; display:none; align-items:center; justify-content:center; line-height:1; padding:0 2px; }
      .bell-count.show { display:flex; }
    `;
    document.head.appendChild(style);

    // Calendar sayfasında zaten .actions içinde yerleşik bell varsa ekleme
    const existingBtn = document.querySelector('.bell-btn');
    if (!existingBtn) {
      btn.classList.add('wb-floating-bell');
      document.body.appendChild(btn);
    }
  }

  function injectNotifyPanel() {
    // Notify panel CSS (calendar'da zaten varsa tekrar ekleme)
    const hasNotifyStyle = Array.from(document.styleSheets).some(ss => {
      try { return Array.from(ss.cssRules || []).some(r => String(r.cssText).includes('.notify')); } catch { return false; }
    });

    if (!hasNotifyStyle) {
      const style = document.createElement('style');
      style.textContent = `
        .wb-notify-panel {
          position: fixed;
          top: 0; right: 0; bottom: 0;
          width: min(360px, 100vw);
          background: #fff;
          box-shadow: -4px 0 32px rgba(0,0,0,.15);
          display: flex;
          flex-direction: column;
          z-index: 9300;
          transform: translateX(100%);
          transition: transform .28s cubic-bezier(.4,0,.2,1);
          border-radius: 16px 0 0 16px;
        }
        .wb-notify-panel.open { transform: translateX(0); }
        /* Mobilede panel de gizle */
        @media (max-width: 768px) {
          .wb-notify-panel { display: none !important; }
          .wb-notify-overlay { display: none !important; }
        }
        .wb-notify-head {
          display: flex; align-items: center; justify-content: space-between;
          padding: 14px 16px;
          font-weight: 800;
          font-size: 15px;
          border-bottom: 1px solid #e5e7eb;
          flex-shrink: 0;
        }
        .wb-notify-body {
          flex: 1;
          overflow-y: auto;
          padding: 14px 14px calc(env(safe-area-inset-bottom, 0px) + 72px);
        }
        .wb-notify-close {
          width: 32px; height: 32px;
          border-radius: 50%;
          border: none;
          background: #f3f4f6;
          cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          font-size: 16px;
          color: #374151;
        }
        .wb-notify-close:hover { background: #e5e7eb; }
        .wb-notify-overlay {
          position: fixed; inset: 0;
          background: rgba(0,0,0,.35);
          z-index: 9299;
          display: none;
        }
        .wb-notify-overlay.show { display: block; }
        .notif-empty { text-align: center; color: #9ca3af; padding: 40px 20px; font-size: 14px; }
        .noti-card {
          border-radius: 12px;
          padding: 14px 16px;
          margin-bottom: 10px;
          background: #fff;
          box-shadow: 0 2px 10px rgba(0,0,0,.07);
          border-left: 3px solid #6366f1;
        }
        .noti-hd { font-weight: 800; font-size: 13px; color: #111827; margin-bottom: 6px; }
        .noti-meta { font-size: 11px; color: #9ca3af; margin-bottom: 8px; }
        .noti-msg { font-size: 13px; color: #374151; line-height: 1.6; margin-bottom: 10px; }
        .noti-row { display: flex; align-items: center; justify-content: space-between; }
        .noti-row .btns { display: flex; gap: 6px; flex-wrap: wrap; }
        .btn.xs {
          padding: 7px 12px;
          font-size: 11px;
          border-radius: 8px;
          border: 1px solid #d1d5db;
          background: #f3f4f6;
          cursor: pointer;
          font-weight: 700;
          transition: background .15s;
        }
        .btn.xs:hover { background: #e5e7eb; }
        .btn.xs.primary { background: #6366f1; color: #fff; border-color: #6366f1; }
        .btn.xs.primary:hover { background: #4f46e5; }
        .btn.xs.danger { background: #fee2e2; color: #b91c1c; border-color: #fca5a5; }
        .btn.xs.danger:hover { background: #fecaca; }
      `;
      document.head.appendChild(style);
    }

    const overlay = document.createElement('div');
    overlay.className = 'wb-notify-overlay';
    overlay.id = 'wbNotifyOverlay';

    const panel = document.createElement('aside');
    panel.id = 'notify';
    panel.className = 'wb-notify-panel';
    panel.setAttribute('role','dialog');
    panel.setAttribute('aria-hidden','true');
    panel.setAttribute('aria-modal','true');
    panel.setAttribute('aria-label','Bildirimler');
    panel.innerHTML = `
      <div class="wb-notify-head">
        <span>🔔 Bildirimler</span>
        <button class="wb-notify-close" id="notifyClose" title="Kapat" type="button">✕</button>
      </div>
      <div class="wb-notify-body" id="notifyBody">
        <div class="notif-empty">Henüz bildiriminiz yok…</div>
      </div>`;

    document.body.appendChild(overlay);
    document.body.appendChild(panel);
  }

  function bindBellEvents() {
    const bellBtn = $('bellBtn');
    const panel   = $('notify');
    const closeBtn = $('notifyClose');
    const overlay  = $('wbNotifyOverlay');

    if (bellBtn && !bellBtn.dataset.wbBound) {
      bellBtn.dataset.wbBound = '1';
      bellBtn.addEventListener('click', () => openPanel());
    }
    if (closeBtn && !closeBtn.dataset.wbBound) {
      closeBtn.dataset.wbBound = '1';
      closeBtn.addEventListener('click', () => closePanel());
    }
    if (overlay && !overlay.dataset.wbBound) {
      overlay.dataset.wbBound = '1';
      overlay.addEventListener('click', () => closePanel());
    }
  }

  function openPanel() {
    $('notify')?.classList.add('open');
    $('wbNotifyOverlay')?.classList.add('show');
    // calendar sayfasının kendi panel mantığı varsa uyumlu çalış
    $('notify')?.setAttribute('aria-hidden','false');
    $('bellBtn')?.setAttribute('aria-expanded','true');
    bootstrapPanelFromServer();
  }

  function closePanel() {
    $('notify')?.classList.remove('open');
    $('wbNotifyOverlay')?.classList.remove('show');
    $('notify')?.setAttribute('aria-hidden','true');
    $('bellBtn')?.setAttribute('aria-expanded','false');
  }

  /* ════════════════════════════════════════════
     BELL BADGE
  ════════════════════════════════════════════ */
  function countCards() {
    return ($('notifyBody')?.querySelectorAll('.noti-card') || []).length;
  }

  /* Gerçek unread sayısını API'dan çek ve tüm badge'leri güncelle */
  // Global badge uygulayıcı — pollSubNotifications ve diğerleri de kullanabilsin
  function applyBellCount(n) {
    const display = n > 99 ? '99+' : String(n);
    const cnt = $('bellCount');
    if (cnt) { cnt.textContent = display; cnt.classList.toggle('show', n > 0); }
    const barCnt = $('barBellCount');
    if (barCnt) { barCnt.textContent = display; barCnt.classList.toggle('show', n > 0); }
    const bnBadge = $('bnBellBadge');
    if (bnBadge) { bnBadge.textContent = display; bnBadge.classList.toggle('visible', n > 0); }
    if (n === 0) {
      const body = $('notifyBody');
      if (body && !body.querySelector('.noti-card')) {
        body.innerHTML = '<div class="notif-empty">Henüz bildiriminiz yok…</div>';
      }
    }
  }

  function refreshBellCountFromServer() {
    apiFetch(`/api/notifications/summary.php?since=${_notifLastTs}`)
      .then(res => {
        if (!res || !res.ok) {
          applyBellCount(countCards());
          return;
        }
        const payload = res.data || res;
        const unread = Number(payload?.counts?.unread ?? 0);
        applyBellCount(Number.isFinite(unread) ? unread : countCards());
      })
      .catch(() => applyBellCount(countCards()));
  }

  function syncBell(forceCount) {
    // forceCount number ise direkt uygula
    if (typeof forceCount === 'number') {
      applyBellCount(forceCount);
      return;
    }

    if (forceCount === 'server') {
      refreshBellCountFromServer();
      return;
    }

    // Varsayılan: local kart sayısına göre güncelle (gereksiz API çağrısını önle)
    applyBellCount(countCards());
  }

  /* ════════════════════════════════════════════
     API HELPERS
  ════════════════════════════════════════════ */
  async function _getNotifCsrf() {
    try {
      if (window.__csrfToken) return window.__csrfToken;
      const r = await fetch(ap('/api/csrf.php'), { credentials: 'include' });
      const d = await r.json();
      if (d?.ok && d?.data?.token) {
        window.__csrfToken = d.data.token;
        return window.__csrfToken;
      }
    } catch (_) {}
    return null;
  }

  async function apiFetch(url, opts = {}) {
    const method = (opts.method || 'GET').toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') {
      const csrf = await _getNotifCsrf();
      if (csrf) {
        opts.headers = { ...(opts.headers || {}), 'X-CSRF-Token': csrf };
      }
    }
    const res = await fetch(ap(url), { credentials: 'same-origin', ...opts });
    if (res.status === 401) { _isAdmin = false; stopPolling(); return null; }
    if (res.status === 403) {
      window.__csrfToken = null; // token geçersizse temizle
    }
    return res.json();
  }

  async function markNotificationRead(payload = {}) {
    try {
      const body = {};
      if (payload.id) body.id = payload.id;
      if (Array.isArray(payload.ids) && payload.ids.length) body.ids = payload.ids;
      if (payload.appointmentId) body.appointmentId = payload.appointmentId;
      if (payload.type) body.type = payload.type;
      if (!body.id && !body.ids && !body.appointmentId) return null;
      return await apiFetch('/api/notifications/mark-read.php', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
    } catch (_) {
      return null;
    }
  }

  function removeCardsForAppointment(appointmentId) {
    document.querySelectorAll(`[data-id="${appointmentId}"], [data-appt-id="${appointmentId}"]`).forEach(el => el.remove());
    document.querySelectorAll(`[data-cancel-id="cancel_${appointmentId}"]`).forEach(el => el.remove());
  }

  /* ════════════════════════════════════════════
     YENİ RANDEVU BİLDİRİMİ
  ════════════════════════════════════════════ */
  function pushAppointmentNotif(it) {
    const body = $('notifyBody');
    if (!body) return;
    body.querySelector('.notif-empty')?.remove();
    if (body.querySelector(`[data-id="${it.id}"]`)) return;

    const card = document.createElement('div');
    card.className = 'noti-card new';
    card.dataset.id = it.id;
    if (it.notifId) card.dataset.notifId = it.notifId;
    const staffTxt  = it.staffName  ? ` • ${escHtml(it.staffName)}` : '';
    const notifTime = fmtDT(it.createdAt) || fmtDT(new Date().toISOString());

    card.innerHTML = `
      <div class="noti-hd">🔔 Yeni Randevu Talebi</div>
      <div class="noti-meta">${notifTime}</div>
      <div class="noti-msg">
        <strong>${escHtml(it.customerName || '—')}</strong>
        ${it.customerPhone ? ' • ' + escHtml(it.customerPhone) : ''}<br>
        ✂️ ${escHtml(it.serviceName || 'Hizmet')}${staffTxt}<br>
        🗓 ${escHtml(it.startFmt || '')}
      </div>
      <div class="noti-row">
        <div></div>
        <div class="btns">
          <button class="btn xs primary" data-appt-id="${escHtml(it.id)}" data-action="approve">Onayla</button>
          <button class="btn xs"         data-appt-id="${escHtml(it.id)}" data-action="reject">Reddet</button>
          <button class="btn xs"  data-dismiss>Tamam</button>
        </div>
      </div>`;

    card.querySelector('[data-dismiss]')?.addEventListener('click', async () => {
      await markNotificationRead({ id: it.notifId || null, appointmentId: it.id, type: 'booking' });
      card.remove();
      syncBell('server');
    });

    card.querySelector('[data-action="approve"]')?.addEventListener('click', async e => {
      const btn = e.currentTarget; btn.disabled = true; btn.textContent = '⏳';
      try {
        const r = await apiFetch('/api/calendar/update-appointment.php', {
          method: 'POST',
          headers: {'Content-Type':'application/json'},
          body: JSON.stringify({ id: it.id, status: 'approved' })
        });
        if (r && r.ok) {
          card.querySelector('.noti-hd').textContent = '✅ Onaylandı';
          card.querySelector('.btns').innerHTML = '<button class="btn xs" data-dismiss>Tamam</button>';
          card.querySelector('[data-dismiss]')?.addEventListener('click', async () => {
            await markNotificationRead({ id: it.notifId || null, appointmentId: it.id, type: 'booking' });
            card.remove(); syncBell('server');
          });
          // bildirimler.html açıksa onu da yenile
          window.dispatchEvent(new CustomEvent('wb:notif-action', { detail: { appointmentId: it.id, result: 'approved' } }));
          // Takvimi yenile (calendar.js yüklüyse)
          try { window.wbCalendarRefresh?.(); } catch {}
          syncBell('server');
        } else { btn.disabled = false; btn.textContent = 'Onayla'; }
      } catch { btn.disabled = false; btn.textContent = 'Onayla'; }
    });

    card.querySelector('[data-action="reject"]')?.addEventListener('click', async e => {
      const btn = e.currentTarget; btn.disabled = true; btn.textContent = '⏳';
      try {
        const r = await apiFetch('/api/calendar/update-appointment.php', {
          method: 'POST',
          headers: {'Content-Type':'application/json'},
          body: JSON.stringify({ id: it.id, status: 'cancelled' })
        });
        if (r && r.ok) {
          card.querySelector('.noti-hd').textContent = '❌ Reddedildi';
          card.querySelector('.btns').innerHTML = '<button class="btn xs" data-dismiss>Tamam</button>';
          card.querySelector('[data-dismiss]')?.addEventListener('click', async () => {
            await markNotificationRead({ id: it.notifId || null, appointmentId: it.id, type: 'booking' });
            card.remove(); syncBell('server');
          });
          window.dispatchEvent(new CustomEvent('wb:notif-action', { detail: { appointmentId: it.id, result: 'rejected' } }));
          try { window.wbCalendarRefresh?.(); } catch {}
          syncBell('server');
        } else { btn.disabled = false; btn.textContent = 'Reddet'; }
      } catch { btn.disabled = false; btn.textContent = 'Reddet'; }
    });

    body.prepend(card);
    playSound();
    syncBell();
  }

  /* ════════════════════════════════════════════
     İPTAL BİLDİRİMİ
  ════════════════════════════════════════════ */
  function pushCancellationNotif(it) {
    const body = $('notifyBody');
    if (!body) return;
    body.querySelector('.notif-empty')?.remove();

    if (body.querySelector(`[data-cancel-id="cancel_${it.id}"]`)) return;

    const card = document.createElement('div');
    card.className = 'noti-card';
    card.dataset.cancelId = 'cancel_' + it.id;
    if (it.notifId) card.dataset.notifId = it.notifId;
    card.style.borderLeftColor = '#f59e0b';

    const notifTime = fmtDT(it.cancelledAt || new Date().toISOString());
    const staffTxt  = it.staffName ? ` • ${escHtml(it.staffName)}` : '';

    card.innerHTML = `
      <div class="noti-hd" style="color:#92400e">⚠️ Randevu İptal Talebi</div>
      <div class="noti-meta">${notifTime}</div>
      <div class="noti-msg">
        <strong>${escHtml(it.customerName || '—')}</strong>${it.customerPhone ? ' • '+escHtml(it.customerPhone):''}<br>
        🗓 ${escHtml(it.startFmt || '')}${staffTxt}<br>
        ✂️ ${escHtml(it.serviceName || 'Hizmet')}
      </div>
      <div style="font-size:12px;color:#6b7280;margin-bottom:10px">Müşteri bu randevuyu iptal etmek istiyor.</div>
      <div class="btns" style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn xs primary" data-action="approve-cancel" style="flex:1;background:#10b981;border-color:#10b981">✅ Onayla</button>
        <button class="btn xs" data-action="reject-cancel" style="flex:1">❌ Reddet</button>
      </div>
      <div class="cancel-result" style="display:none;margin-top:8px;font-size:12px;font-weight:700;text-align:center"></div>`;

    const setResult = (msg, color, result) => {
      card.querySelector('.btns').style.display = 'none';
      const r = card.querySelector('.cancel-result');
      r.style.display = 'block'; r.style.color = color; r.textContent = msg;
      // bildirimler.html açıksa onu da yenile
      window.dispatchEvent(new CustomEvent('wb:notif-action', { detail: { appointmentId: it.id, result } }));
      markNotificationRead({ id: it.notifId || null, appointmentId: it.id, type: 'cancellation' }).finally(() => {
        syncBell('server');
        setTimeout(() => { card.remove(); syncBell('server'); }, 5000);
      });
    };

    card.querySelector('[data-action="approve-cancel"]')?.addEventListener('click', async e => {
      const btn = e.currentTarget; btn.disabled = true; btn.textContent = '⏳';
      try {
        const r = await apiFetch('/api/calendar/approve-cancellation.php', {
          method: 'POST', headers: {'Content-Type':'application/json'},
          body: JSON.stringify({ id: it.id })
        });
        if (r && r.ok) setResult('✅ İptal onaylandı.', '#10b981', 'cancel_approved');
        else { btn.disabled = false; btn.textContent = '✅ Onayla'; }
      } catch { btn.disabled = false; btn.textContent = '✅ Onayla'; }
    });

    card.querySelector('[data-action="reject-cancel"]')?.addEventListener('click', async e => {
      const btn = e.currentTarget; btn.disabled = true; btn.textContent = '⏳';
      try {
        const r = await apiFetch('/api/calendar/reject-cancellation.php', {
          method: 'POST', headers: {'Content-Type':'application/json'},
          body: JSON.stringify({ id: it.id })
        });
        if (r && r.ok) setResult('🔄 İptal reddedildi.', '#6b7280', 'cancel_rejected');
        else { btn.disabled = false; btn.textContent = '❌ Reddet'; }
      } catch { btn.disabled = false; btn.textContent = '❌ Reddet'; }
    });

    body.prepend(card);
    playSound();
    syncBell();
  }

  function pushGuideNotif(it, autoMarkRead = false, silent = false) {
    const body = $('notifyBody');
    if (!body || !it || !it.id) return;
    body.querySelector('.notif-empty')?.remove();
    if (body.querySelector(`[data-guide-notif-id="${it.id}"]`)) return;

    const title = it.title || it.customerName || 'Bilgi';
    const message = it.message || it.serviceName || '';
    const guideKey = it.guideKey || it.result || '';
    const targetHref = it.linkUrl || it.staffName || 'bildirimler.html';
    const actionLabelMap = {
      calendar: 'Takvime Git',
      staff: 'Personeli Aç',
      settings: 'Dükkanı Yönet',
      notifications: 'Geçmişi Aç',
    };
    const actionLabel = actionLabelMap[guideKey] || 'Aç';
    if (isGuideHidden(guideKey)) return;

    const card = document.createElement('div');
    card.className = 'noti-card';
    card.dataset.guideNotifId = it.id;
    card.style.borderLeftColor = '#0ea5b3';
    card.innerHTML = `
      <div class="noti-hd" style="color:#0b8a96">Bilgi</div>
      <div class="noti-meta">${fmtDT(it.createdAt || new Date().toISOString())}</div>
      <div class="noti-msg">
        <strong>${escHtml(title)}</strong><br>
        ${escHtml(message)}
      </div>
      <div class="noti-row">
        <div></div>
        <div class="btns">
          <a class="btn xs primary" href="${escHtml(targetHref)}" style="text-decoration:none;display:inline-flex;align-items:center;">${actionLabel}</a>
          <button class="btn xs" data-guide-dismiss="${escHtml(it.id)}">Tamam</button>
        </div>
      </div>`;

    const dismiss = async () => {
      hideGuideKey(guideKey);
      await markNotificationRead({ id: it.id });
      card.remove();
      syncBell('server');
    };

    card.querySelector('a.btn.xs.primary')?.addEventListener('click', async () => {
      hideGuideKey(guideKey);
      await markNotificationRead({ id: it.id });
      card.remove();
    });
    card.querySelector('[data-guide-dismiss]')?.addEventListener('click', dismiss);
    body.prepend(card);

    if (autoMarkRead) {
      markNotificationRead({ id: it.id })
        .then(() => {
          window.dispatchEvent(new CustomEvent('wb:notif-action', { detail: { id: it.id, type: 'guide' } }));
          syncBell('server');
        })
        .catch(() => {});
      return;
    }

    if (!silent) {
      playSound();
      syncBell();
    }
  }

  /* ════════════════════════════════════════════
     POLLING
  ════════════════════════════════════════════ */
  async function bootstrapPanelFromServer(force = false) {
    const body = $('notifyBody');
    if (!body) return;
    const now = Date.now();
    if (!force && now - _panelLoadedAt < 15000 && body.querySelector('.noti-card')) return;
    _panelLoadedAt = now;

    try {
      const res = await apiFetch('/api/notifications/list.php?limit=50');
      if (!res || !res.ok) return;

      const items = res.data?.items ?? res.data?.notifications ?? [];
      if (!Array.isArray(items)) return;

      body.innerHTML = '';

      items
        .filter(n => !n.isRead && n.type === 'booking' && n.result === 'pending')
        .reverse()
        .forEach(n => {
          _seenAppt.add(String(n.appointmentId || n.id));
          pushAppointmentNotif({
            id: String(n.appointmentId || ''),
            notifId: String(n.id),
            customerName: n.customerName,
            customerPhone: n.customerPhone,
            serviceName: n.serviceName,
            staffName: n.staffName,
            startFmt: n.startFmt,
            createdAt: n.createdAt,
          });
        });

      items
        .filter(n => !n.isRead && n.type === 'cancellation' && n.result === 'pending')
        .reverse()
        .forEach(n => {
          _seenCancel.add('cancel_' + String(n.appointmentId || n.id));
          pushCancellationNotif({
            id: String(n.appointmentId || ''),
            notifId: String(n.id),
            customerName: n.customerName,
            customerPhone: n.customerPhone,
            serviceName: n.serviceName,
            staffName: n.staffName,
            startFmt: n.startFmt,
            cancelledAt: n.createdAt,
          });
        });

      const SUB_TYPES = new Set(['subscription_expiry_3d', 'subscription_expiry_2d', 'subscription_expiry_1d', 'subscription_expired']);
      items
        .filter(n => !n.isRead && SUB_TYPES.has(n.type))
        .reverse()
        .forEach(n => {
          _seenSub.add(String(n.id));
          pushSubNotif(n);
        });

      if (!body.querySelector('.noti-card')) {
        body.innerHTML = '<div class="notif-empty">Henüz bildiriminiz yok…</div>';
      }

      items
        .filter(n => n.type === 'guide')
        .reverse()
        .forEach(n => {
          _seenGuide.add(String(n.id));
          pushGuideNotif(n, false, true);
        });
      applyBellCount(items.filter(n => !n.isRead).length);
    } catch (_) {}
  }

  function startPolling() {
    stopPolling();
    _pollRetry = 0;
    pollSummary();
  }

  function stopPolling() {
    clearTimeout(_pollTimer);
    _pollTimer = null;
    _pollRetry = 0;
  }

  /* ════════════════════════════════════════════
     ABONELİK BİLDİRİMLERİ
  ════════════════════════════════════════════ */
  async function pollSubNotifications() {
    if (!_isAdmin) return;
    try {
      const res = await apiFetch('/api/notifications/list.php?limit=50');
      if (!res || !res.ok) return;
      const _subItems = res.data?.items ?? res.data?.notifications ?? res.notifications ?? [];
      if (!Array.isArray(_subItems)) return;

      const SUB_TYPES = new Set([
        'subscription_expiry_3d',
        'subscription_expiry_2d',
        'subscription_expiry_1d',
        'subscription_expired',
      ]);

      _subItems
        .filter(n => SUB_TYPES.has(n.type) && !n.isRead && !_seenSub.has(n.id))
        .forEach(n => {
          _seenSub.add(n.id);
          pushSubNotif(n);
        });

      // Her poll'da unread sayısını güncelle (bar-menu inject gecikmesini aşmak için)
      const unread = _subItems.filter(n => !n.isRead).length;
      applyBellCount(unread);
    } catch {}
  }

  function handleSummaryPayload(payload) {
    if (!payload || typeof payload !== 'object') return;

    _notifLastTs = payload.ts || Math.floor(Date.now() / 1000);
    applyBellCount(Number(payload?.counts?.unread ?? 0));

    const appointmentItems = Array.isArray(payload.appointments) ? payload.appointments : [];
    appointmentItems
      .filter(it => !_seenAppt.has(it.id))
      .forEach(it => {
        _seenAppt.add(it.id);
        pushAppointmentNotif(it);
      });

    const cancellationItems = Array.isArray(payload.cancellations) ? payload.cancellations : [];
    const liveCancelIds = new Set(cancellationItems.map(it => `cancel_${it.id}`));
    cancellationItems
      .filter(it => !_seenCancel.has(`cancel_${it.id}`))
      .forEach(it => {
        _seenCancel.add(`cancel_${it.id}`);
        pushCancellationNotif(it);
      });

    document.querySelectorAll('[data-cancel-id]').forEach(card => {
      if (!liveCancelIds.has(card.dataset.cancelId)) {
        card.remove();
      }
    });

    const systemItems = Array.isArray(payload.system) ? payload.system : [];
    const SUB_TYPES = new Set(['subscription_expiry_3d', 'subscription_expiry_2d', 'subscription_expiry_1d', 'subscription_expired']);

    systemItems
      .filter(n => SUB_TYPES.has(n.type) && !_seenSub.has(String(n.id)))
      .forEach(n => {
        _seenSub.add(String(n.id));
        pushSubNotif(n);
      });

    systemItems
      .filter(n => n.type === 'guide' && !_seenGuide.has(String(n.id)))
      .forEach(n => {
        _seenGuide.add(String(n.id));
        pushGuideNotif(n, false, false);
      });
  }

  function nextPollDelay() {
    return document.hidden ? POLL_INTERVAL_HIDDEN : POLL_INTERVAL_VISIBLE;
  }

  function scheduleNextPoll(delay = nextPollDelay()) {
    clearTimeout(_pollTimer);
    _pollTimer = setTimeout(() => {
      pollSummary();
    }, delay);
  }

  async function pollSummary() {
    if (!_isAdmin) return;
    try {
      const res = await apiFetch(`/api/notifications/summary.php?since=${_notifLastTs}`);
      if (!res || !res.ok) {
        _pollRetry = Math.min(_pollRetry + 1, 4);
        scheduleNextPoll(Math.min(POLL_INTERVAL_HIDDEN, POLL_RETRY_BASE * (2 ** _pollRetry)));
        return;
      }

      _pollRetry = 0;
      handleSummaryPayload(res.data || res);
      scheduleNextPoll();
    } catch (_) {
      _pollRetry = Math.min(_pollRetry + 1, 4);
      scheduleNextPoll(Math.min(POLL_INTERVAL_HIDDEN, POLL_RETRY_BASE * (2 ** _pollRetry)));
    }
  }

  function pushSubNotif(n) {
    const body = $('notifyBody');
    if (!body) return;
    body.querySelector('.notif-empty')?.remove();

    // Aynı kart zaten varsa ekleme
    if (body.querySelector(`[data-sub-notif-id="${n.id}"]`)) return;

    const isExpired = n.type === 'subscription_expired';
    const is1d = n.type === 'subscription_expiry_1d';
    const is2d = n.type === 'subscription_expiry_2d';

    const icon = isExpired ? '⚠️' : is1d ? '⏳' : is2d ? '⏰' : '📅';
    const color = isExpired ? '#ef4444' : is1d ? '#f59e0b' : is2d ? '#f97316' : '#0ea5b3';
    const btnLabel = isExpired ? '🚀 Hemen Plan Al' : '🔄 Planı Yenile';

    // customer_name = başlık, service_name = açıklama (cron'dan böyle dolduruldu)
    const title = n.customerName || 'Abonelik Bildirimi';
    const desc  = n.serviceName  || '';
    const time  = fmtDT(n.createdAt);

    const card = document.createElement('div');
    card.className = 'noti-card new';
    card.dataset.subNotifId = n.id;
    card.style.cssText = `border-left: 3px solid ${color};`;

    card.innerHTML = `
      <div class="noti-hd" style="color:${color}">${icon} ${escHtml(title)}</div>
      <div class="noti-meta">${time}</div>
      <div class="noti-msg" style="margin:8px 0;">${escHtml(desc)}</div>
      <div class="noti-row">
        <div></div>
        <div class="btns">
          <a href="admin-profile.html#billing"
             class="btn xs primary"
             style="background:${color};border-color:${color};text-decoration:none;display:inline-flex;align-items:center;"
             onclick="markSubNotifRead(${n.id})">
            ${btnLabel}
          </a>
          <button class="btn xs" data-sub-dismiss="${n.id}">Tamam</button>
        </div>
      </div>`;

    card.querySelector(`[data-sub-dismiss]`)?.addEventListener('click', async () => {
      await markSubNotifRead(n.id);
      card.remove();
      syncBell();
    });

    body.prepend(card);
    playSound();
    syncBell();
  }

  async function markSubNotifRead(notifId) {
    try {
      await apiFetch('/api/notifications/mark-read.php', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: [notifId] }),
      });
    } catch {}
  }

  async function ensureGuideWizardNotifications() {
    if (!_isAdmin || guidesBootstrapped() || _guideEnsured.has('bootstrap')) return;
    _guideEnsured.add('bootstrap');

    try {
      const res = await apiFetch('/api/notifications/guide.php', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ page: 'bootstrap' }),
      });
      const wizardItems = res?.data?.createdItems || res?.createdItems || [];
      if (Array.isArray(wizardItems)) {
        wizardItems.forEach(item => {
          if (!item || _seenGuide.has(String(item.id))) return;
          _seenGuide.add(String(item.id));
          pushGuideNotif(item, true);
        });
      }
      setGuidesBootstrapped();
    } catch {}
  }

  /* ════════════════════════════════════════════
     SESSION KONTROLÜ
  ════════════════════════════════════════════ */
  async function checkSession() {
    try {
      const res = await apiFetch('/api/session/me.php');
      if (!res) { _isAdmin = false; stopPolling(); return; }
      // CSRF token'ı sonraki istekler için sakla
      if (res.ok && res.data?.csrf_token) {
        window.__csrfToken = res.data.csrf_token;
      }
      const guideOwnerId = res?.data?.businessId || res?.data?.business_id || res?.data?.adminId || res?.data?.userId || 'guest';
      _guideBootstrapKey = GUIDE_BOOTSTRAP_KEY_PREFIX + String(guideOwnerId);
      const isAdmin = res.ok && res.data && res.data.role === 'admin';
      if (isAdmin && !_isAdmin) {
        _isAdmin = true;
        if (!_initialized) { _initialized = true; setupBellAndPanel(); }
        startPolling();
        ensureGuideWizardNotifications();
      } else if (!isAdmin) {
        _isAdmin = false;
        stopPolling();
      }
    } catch {}
  }

  /* ════════════════════════════════════════════
     WEB PUSH SUBSCRIBE
  ════════════════════════════════════════════ */

  /**
   * Service Worker ile Web Push bildirimlerine abone ol.
   * api/push/subscribe.php'e kaydeder.
   * VAPID public key: api/_push.php'deki vapid_public_key ile aynı olmalı.
   */
  const VAPID_PUBLIC_KEY = 'BURAYA_VAPID_PUBLIC_KEY'; // _push.php ile eşleşmeli

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64  = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    return Uint8Array.from([...rawData].map(c => c.charCodeAt(0)));
  }

  async function setupWebPush() {
    // Tarayıcı destekliyor mu?
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;
    // VAPID key girilmemiş — hâlâ placeholder
    if (VAPID_PUBLIC_KEY.startsWith('BURAYA')) return;

    try {
      const reg = await navigator.serviceWorker.ready;

      // Zaten abone mi?
      const existing = await reg.pushManager.getSubscription();
      if (existing) return; // Zaten kayıtlı, tekrar kaydetme

      // İzin iste
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') return;

      // Abone ol
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly:      true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
      });

      const subJson = sub.toJSON();

      // Backend'e kaydet
      const _pushCsrf = await _getNotifCsrf();
      await fetch('/api/push/subscribe.php', {
        method:      'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          ...(_pushCsrf ? { 'X-CSRF-Token': _pushCsrf } : {}),
        },
        body: JSON.stringify({
          action:   'subscribe',
          endpoint: subJson.endpoint,
          p256dh:   subJson.keys?.p256dh,
          auth:     subJson.keys?.auth,
        }),
      });

    } catch (err) {
      console.warn('[WebPush] Abone olunamadı:', err.message);
    }
  }

  /* ════════════════════════════════════════════
     INIT
  ════════════════════════════════════════════ */
  function init() {
    checkSession();

    // bar-menu inject edildikten sonra #barBellCount DOM'a giriyor —
    // MutationObserver ile yakalayıp badge'i hemen güncelle
    const _barObserver = new MutationObserver(() => {
      const barCnt = document.getElementById('barBellCount');
      if (barCnt) {
        _barObserver.disconnect();
        // bar-menu hazır, mevcut/pull edilen sayaçla badge'i eşitle
        syncBell('server');
      }
    });
    _barObserver.observe(document.body, { childList: true, subtree: true });

    // Sayfa görünür olunca (tab switch) hemen poll et
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && _isAdmin) {
        pollSummary();
        bootstrapPanelFromServer(true);
      }
    });

    // Admin giriş yaptıktan sonra push subscribe dene
    setTimeout(setupWebPush, 3000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Global erişim için (calendar.js uyumluluğu)
  window.wbNotifications = { openPanel, closePanel, syncBell, applyBellCount };
})();
