/**
 * wb-email-banner.js
 * Ortak admin email doğrulama bannerı.
 */
(function initEmailBanner() {
  'use strict';
  var hasShownUnverified = false;
  var reloadTriggered = false;
  var pollTimer = null;
  var storageKey = 'wb_email_verified_at';

  function waitForApi(cb, attempts) {
    if (window.WbApi) {
      cb();
      return;
    }
    if ((attempts || 0) > 20) return;
    setTimeout(function () { waitForApi(cb, (attempts || 0) + 1); }, 150);
  }

  waitForApi(async function () {
    await refreshBannerState(false);
    bindRealtimeWatchers();
    startPolling();
  });

  async function refreshBannerState(reloadOnVerified) {
    hideAllBanners();
    try {
      var data = await window.WbApi.get('/api/profile/me.php');
      var verified = !!(data && data.ok && data.data && data.data.emailVerified);
      if (verified) {
        hideAllBanners();
        if (reloadOnVerified && hasShownUnverified && !reloadTriggered) {
          reloadTriggered = true;
          try { sessionStorage.setItem('wb_email_banner_reloaded', '1'); } catch (_) {}
          window.location.reload();
        }
        return;
      }
      if (!data || !data.ok) {
        hideAllBanners();
        return;
      }
      var email = (data.data && data.data.email) || '';
      hasShownUnverified = true;
      mountBanner(email);
    } catch (_) {
      hideAllBanners();
    }
  }

  function hideAllBanners() {
    var dynamic = document.getElementById('wb-email-verify-banner');
    if (dynamic) dynamic.remove();

    var legacy = document.getElementById('emailVerifyBanner');
    if (legacy) {
      legacy.hidden = true;
      legacy.style.display = 'none';
    }
  }

  function mountBanner(email) {
    if (document.getElementById('wb-email-verify-banner')) return;

    var banner = document.createElement('div');
    banner.id = 'wb-email-verify-banner';
    banner.setAttribute('role', 'alert');
    banner.style.cssText = [
      'background:#fef3c7',
      'border-bottom:2px solid #fbbf24',
      'padding:11px 20px',
      'font-size:13.5px',
      'color:#92400e',
      'display:flex',
      'align-items:center',
      'justify-content:space-between',
      'gap:12px',
      'flex-wrap:wrap',
      'position:relative',
      'z-index:9999'
    ].join(';');

    banner.innerHTML = '' +
      '<div style="display:flex;align-items:center;gap:10px;">' +
      '  <span style="font-size:18px;">📧</span>' +
      '  <span><strong>Email adresiniz henüz doğrulanmadı.</strong> Gönderilen doğrulama linkine tıklayın.</span>' +
      '</div>' +
      '<div style="display:flex;gap:8px;align-items:center;">' +
      '  <button id="wb-resend-verify-btn" type="button" style="background:#f59e0b;color:#fff;border:none;border-radius:8px;padding:7px 14px;font-size:12.5px;font-weight:600;cursor:pointer;transition:opacity .2s;">Tekrar Gönder</button>' +
      '  <button id="wb-banner-close-btn" type="button" aria-label="Kapat" style="background:none;border:none;cursor:pointer;color:#92400e;font-size:20px;padding:4px 8px;line-height:1;">×</button>' +
      '</div>';

    document.body.insertAdjacentElement('afterbegin', banner);

    var closeBtn = document.getElementById('wb-banner-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        banner.style.display = 'none';
      });
    }

    var resendBtn = document.getElementById('wb-resend-verify-btn');
    if (resendBtn) {
      resendBtn.addEventListener('click', async function () {
        if (resendBtn.disabled) return;
        resendBtn.textContent = 'Gönderiliyor...';
        resendBtn.disabled = true;
        resendBtn.style.opacity = '0.7';

        try {
          var res = await window.WbApi.post('/api/auth/resend-verification.php', { email: email });
          if ((!res || !res.ok) && (res && (res.code === 'rate_limited' || res.wait))) {
            startCooldown(resendBtn, Number(res.wait || 60));
            return;
          }
          resendBtn.textContent = '✓ Gönderildi';
          resendBtn.style.opacity = '1';
          setTimeout(function () {
            resendBtn.textContent = 'Tekrar Gönder';
            resendBtn.disabled = false;
          }, 5000);
        } catch (_) {
          resendBtn.textContent = 'Hata, tekrar dene';
          resendBtn.disabled = false;
          resendBtn.style.opacity = '1';
        }
      });
    }
  }

  function startCooldown(btn, seconds) {
    var remaining = Number(seconds || 60);
    btn.style.opacity = '0.7';

    function tick() {
      btn.textContent = String(remaining) + 'sn bekleyin';
      remaining -= 1;
      if (remaining <= 0) {
        btn.textContent = 'Tekrar Gönder';
        btn.disabled = false;
        btn.style.opacity = '1';
        return;
      }
      setTimeout(tick, 1000);
    }

    tick();
  }

  function bindRealtimeWatchers() {
    window.addEventListener('storage', function (e) {
      if (e && e.key === storageKey) {
        refreshBannerState(true);
      }
    });

    window.addEventListener('focus', function () {
      refreshBannerState(true);
    });

    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) refreshBannerState(true);
    });
  }

  function startPolling() {
    if (pollTimer) return;
    pollTimer = setInterval(function () {
      refreshBannerState(true);
    }, 15000);
  }
})();
