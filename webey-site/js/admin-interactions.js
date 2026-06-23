/**
 * admin-interactions.js — Admin Sayfaları Mikro İnteraksiyon Sistemi
 * v1.1 — conflict-free, calendar.html · staff.html · settings.html
 *
 * Bu dosya yalnızca admin sayfalarında yüklenir.
 * wb-transitions.js'den SONRA yüklenmeli.
 */
(function () {
  'use strict';

  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => [...(r || document).querySelectorAll(s)];

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn, { once: true });
    } else {
      fn();
    }
  }

  /* ══════════════════════════════════════
     1. SETTINGS NAV — smooth scroll + aktif indicator
  ══════════════════════════════════════ */
  function initSettingsNav() {
    const navLinks = $$('.settings-nav__link[href^="#"]');
    if (!navLinks.length) return;

    navLinks.forEach(link => {
      link.addEventListener('click', function(e) {
        e.preventDefault();
        const target = $(this.getAttribute('href'));
        if (!target) return;

        navLinks.forEach(l => l.classList.remove('is-active'));
        this.classList.add('is-active');

        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        history.replaceState(null, '', this.getAttribute('href'));
      });
    });

    const sections = navLinks.map(l => $(l.getAttribute('href'))).filter(Boolean);
    if (!sections.length) return;

    let _scrollTimer = null;
    function updateActiveSection() {
      const topbarH = parseInt(getComputedStyle(document.documentElement)
        .getPropertyValue('--topbar-h') || '56');
      let activeIdx = 0;
      sections.forEach((sec, i) => {
        const rect = sec.getBoundingClientRect();
        if (rect.top <= topbarH + 40) activeIdx = i;
      });
      navLinks.forEach((l, i) => l.classList.toggle('is-active', i === activeIdx));
    }

    window.addEventListener('scroll', () => {
      clearTimeout(_scrollTimer);
      _scrollTimer = setTimeout(updateActiveSection, 60);
    }, { passive: true });
  }

  /* ══════════════════════════════════════
     2. BUTON LOADING STATE
     Kullanım:
       const reset = wb.btnLoading(btn);
       await doSomething();
       reset();
  ══════════════════════════════════════ */
  function btnLoading(btn) {
    if (!btn) return () => {};
    const origHTML = btn.innerHTML;
    const origW    = btn.offsetWidth + 'px';
    btn.style.minWidth = origW;
    btn.classList.add('wb-loading');
    btn.disabled = true;
    return function reset(newHTML) {
      btn.classList.remove('wb-loading');
      btn.disabled = false;
      btn.style.minWidth = '';
      btn.innerHTML = newHTML !== undefined ? newHTML : origHTML;
    };
  }

  /* ══════════════════════════════════════
     3. CONFIRM DIALOG
     Kullanım:
       const ok = await wb.confirm('Silmek istiyor musunuz?', 'Sil', 'İptal');
       if (ok) { ... }
  ══════════════════════════════════════ */
  function wbConfirm(msg, confirmLabel, cancelLabel) {
    confirmLabel = confirmLabel || 'Onayla';
    cancelLabel  = cancelLabel  || 'İptal';

    return new Promise(function(resolve) {
      const old = document.getElementById('wb-confirm-overlay');
      if (old) old.remove();

      const overlay = document.createElement('div');
      overlay.id = 'wb-confirm-overlay';
      overlay.style.cssText = [
        'position:fixed', 'inset:0', 'z-index:99990',
        'display:flex', 'align-items:center', 'justify-content:center',
        'background:rgba(9,11,17,.45)',
        'padding:24px',
      ].join(';');

      overlay.innerHTML = `
        <div style="
          background:#fff; border-radius:16px;
          box-shadow:0 30px 80px rgba(0,0,0,.25);
          padding:24px; width:min(360px,96vw);
          animation:wbModalIn .2s cubic-bezier(.22,1,.36,1) both;
          font-family:inherit;
        ">
          <p style="margin:0 0 20px;font-size:14.5px;line-height:1.6;color:#111;font-weight:500;">${msg}</p>
          <div style="display:flex;gap:10px;justify-content:flex-end;">
            <button id="wb-confirm-cancel" style="
              padding:9px 16px; border-radius:10px; border:1px solid #e5e7eb;
              background:#f8fafc; font-weight:700; font-size:13.5px;
              cursor:pointer; font-family:inherit;
            ">${cancelLabel}</button>
            <button id="wb-confirm-ok" style="
              padding:9px 16px; border-radius:10px; border:none;
              background:#dc2626; color:#fff; font-weight:700; font-size:13.5px;
              cursor:pointer; font-family:inherit;
            ">${confirmLabel}</button>
          </div>
        </div>
      `;

      document.body.appendChild(overlay);

      function close(result) {
        overlay.style.opacity = '0';
        overlay.style.transition = 'opacity .15s';
        setTimeout(() => overlay.remove(), 160);
        resolve(result);
      }

      overlay.querySelector('#wb-confirm-cancel').onclick = () => close(false);
      overlay.querySelector('#wb-confirm-ok').onclick     = () => close(true);
      overlay.addEventListener('click', e => { if (e.target === overlay) close(false); });
      document.addEventListener('keydown', function esc(e) {
        if (e.key === 'Escape') { document.removeEventListener('keydown', esc); close(false); }
      });

      setTimeout(() => overlay.querySelector('#wb-confirm-ok')?.focus(), 50);
    });
  }

  /* ══════════════════════════════════════
     4. KLAVYE KISAYOLLARI
  ══════════════════════════════════════ */
  function initKeyboardShortcuts() {
    document.addEventListener('keydown', function(e) {
      const tag = document.activeElement?.tagName;
      const isInput = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'
        || document.activeElement?.isContentEditable;

      // Ctrl+S → Save
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        const saveBtn = $('#saveBtn');
        if (saveBtn && !saveBtn.disabled) {
          e.preventDefault();
          saveBtn.click();
          navigator.vibrate?.(30);
        }
        return;
      }

      if (isInput) return;

      // ← → tarih gezinme (calendar)
      if (e.key === 'ArrowLeft') {
        const prev = $('#prevBtn, .nav-prev, [data-action="prev"]');
        prev?.click();
      }
      if (e.key === 'ArrowRight') {
        const next = $('#nextBtn, .nav-next, [data-action="next"]');
        next?.click();
      }

      // T → Bugün (calendar)
      if (e.key === 't' || e.key === 'T') {
        const todayBtn = $('#todayBtn, [data-action="today"]');
        todayBtn?.click();
      }
    });
  }

  /* ══════════════════════════════════════
     5. POPOVER DIŞ TIKLA KAPAT
     Sadece .view-pop ve .staff-pop gibi liste popoverları —
     #notify, .drawer, .wb-notify-panel DOKUNMUYORUZ,
     onların kendi close logic'leri var.
  ══════════════════════════════════════ */
  function initPopoverClose() {
    document.addEventListener('click', function(e) {
      // Yalnızca küçük açılır listeler
      const openPops = $$('.view-pop.open, .staff-pop.open');
      openPops.forEach(pop => {
        if (!pop.contains(e.target)) {
          const trigger = pop.previousElementSibling
            || pop.parentElement?.querySelector('[aria-expanded]');
          if (trigger && trigger.contains(e.target)) return;
          pop.classList.remove('open');
        }
      });
    }, { capture: true });
  }

  /* ══════════════════════════════════════
     6. POPOVER AÇILMA ANİMASYONU
     view-pop ve staff-pop açılırken animasyon ekle
  ══════════════════════════════════════ */
  function initPopoverAnimation() {
    // MutationObserver ile .open class eklenmesini izle
    const mo = new MutationObserver(mutations => {
      mutations.forEach(m => {
        if (m.type !== 'attributes') return;
        const el = m.target;
        if (el.classList.contains('view-pop') || el.classList.contains('staff-pop')) {
          if (el.classList.contains('open')) {
            el.style.animation = 'none';
            void el.offsetHeight; // reflow
            el.style.animation = 'wbPopIn .18s cubic-bezier(.22,1,.36,1) both';
          }
        }
      });
    });

    $$('.view-pop, .staff-pop').forEach(el => {
      mo.observe(el, { attributes: true, attributeFilter: ['class'] });
    });

    // Dinamik eklenenler için body observer
    const bodyMo = new MutationObserver(mutations => {
      mutations.forEach(m => {
        m.addedNodes.forEach(node => {
          if (node.nodeType !== 1) return;
          if (node.classList?.contains('view-pop') || node.classList?.contains('staff-pop')) {
            mo.observe(node, { attributes: true, attributeFilter: ['class'] });
          }
        });
      });
    });
    bodyMo.observe(document.body, { childList: true });
  }

  /* ══════════════════════════════════════
     7. SETTINGS SECTION SCROLL MARGIN
  ══════════════════════════════════════ */
  function initSectionScrollMargin() {
    const topbarH = parseInt(getComputedStyle(document.documentElement)
      .getPropertyValue('--topbar-h') || '56');
    $$('[id^="sec-"], .settings-section, .settings-card').forEach(el => {
      el.style.scrollMarginTop = (topbarH + 16) + 'px';
    });
  }

  /* ══════════════════════════════════════
     8. BAŞLAT
  ══════════════════════════════════════ */
  onReady(function() {
    initSettingsNav();
    initKeyboardShortcuts();
    initPopoverClose();
    initPopoverAnimation();
    initSectionScrollMargin();
  });

  /* ══════════════════════════════════════
     9. PUBLIC API
  ══════════════════════════════════════ */
  window.wb = window.wb || {};
  window.wb.confirm    = wbConfirm;
  window.wb.btnLoading = btnLoading;

})();