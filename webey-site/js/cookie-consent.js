/**
 * Webey – Cookie Consent Manager
 * KVKK & AB GDPR uyumlu çerez onay sistemi
 */

(function () {
  'use strict';

  const STORAGE_KEY  = 'webey_cookie_consent';
  const VERSION      = '1.0';   // versiyon değişirse mevcut onayı geçersiz kılar

  /* ── Mevcut onayı oku ── */
  function getSaved() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      if (data.version !== VERSION) return null;   // eski versiyon → tekrar sor
      return data;
    } catch { return null; }
  }

  /* ── Onayı kaydet ── */
  function saveConsent(prefs) {
    const data = {
      version: VERSION,
      date: new Date().toISOString(),
      ...prefs
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    dispatchConsentEvent(data);
  }

  /* ── Consent event ── */
  function dispatchConsentEvent(data) {
    window.dispatchEvent(new CustomEvent('webey:consent', { detail: data }));
    // Google Consent Mode v2 entegrasyonu (isteğe bağlı)
    if (typeof window.gtag === 'function') {
      window.gtag('consent', 'update', {
        analytics_storage:    data.analytics ? 'granted' : 'denied',
        ad_storage:           data.marketing ? 'granted' : 'denied',
        ad_user_data:         data.marketing ? 'granted' : 'denied',
        ad_personalization:   data.marketing ? 'granted' : 'denied',
        functionality_storage: data.functional ? 'granted' : 'denied',
      });
    }
  }

  /* ── Banner HTML oluştur ── */
  function buildBanner() {
    const el = document.createElement('div');
    el.id = 'cookieConsent';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'false');
    el.setAttribute('aria-label', 'Çerez onay bildirimi');
    el.innerHTML = `
      <div class="ck-card">
        <div class="ck-icon" aria-hidden="true">🍪</div>

        <div class="ck-body">
          <p class="ck-title">Çerez Tercihleriniz</p>
          <p class="ck-desc">
            Webey olarak siteyi çalışır tutmak için zorunlu çerezler,
            deneyiminizi iyileştirmek için tercih ve analiz çerezleri kullanıyoruz.
            Ayrıntılar için
            <a href="cerez-politikasi.html" target="_blank" rel="noopener">Çerez Politikamızı</a>
            ve <a href="gizlilik-politikasi.html" target="_blank" rel="noopener">KVKK Aydınlatma Metnimizi</a>
            inceleyebilirsiniz.
          </p>

          <!-- Tercihler paneli (gizli başlar) -->
          <div class="ck-prefs" id="ckPrefs">
            <div class="ck-pref-row">
              <div class="ck-pref-info">
                <p class="ck-pref-label">Zorunlu Çerezler</p>
                <p class="ck-pref-sub">Sitenin çalışması için gereklidir. Devre dışı bırakılamaz.</p>
              </div>
              <label class="ck-toggle">
                <input type="checkbox" checked disabled aria-label="Zorunlu çerezler — her zaman açık">
                <span class="ck-slider"></span>
              </label>
            </div>
            <div class="ck-pref-row">
              <div class="ck-pref-info">
                <p class="ck-pref-label">Analiz &amp; Performans</p>
                <p class="ck-pref-sub">Hangi sayfaların en çok ziyaret edildiğini anlamamıza yardımcı olur.</p>
              </div>
              <label class="ck-toggle">
                <input type="checkbox" id="ckAnalytics" checked aria-label="Analiz çerezlerine onay">
                <span class="ck-slider"></span>
              </label>
            </div>
            <div class="ck-pref-row">
              <div class="ck-pref-info">
                <p class="ck-pref-label">Pazarlama &amp; Reklam</p>
                <p class="ck-pref-sub">İlgi alanlarınıza göre içerik ve reklam göstermek için kullanılır.</p>
              </div>
              <label class="ck-toggle">
                <input type="checkbox" id="ckMarketing" aria-label="Pazarlama çerezlerine onay">
                <span class="ck-slider"></span>
              </label>
            </div>
            <div class="ck-pref-row">
              <div class="ck-pref-info">
                <p class="ck-pref-label">Fonksiyonellik</p>
                <p class="ck-pref-sub">Dil, tema gibi tercihlerinizin hatırlanmasını sağlar.</p>
              </div>
              <label class="ck-toggle">
                <input type="checkbox" id="ckFunctional" checked aria-label="Fonksiyonel çerezlere onay">
                <span class="ck-slider"></span>
              </label>
            </div>
            <button class="ck-save-prefs" id="ckSavePrefs" type="button">Seçimlerimi Kaydet</button>
          </div>
        </div>

        <div class="ck-actions">
          <button class="ck-btn ck-btn-primary" id="ckAcceptAll" type="button">Tümünü Kabul Et</button>
          <button class="ck-btn ck-btn-secondary" id="ckRejectAll" type="button">Yalnızca Zorunlu</button>
          <button class="ck-btn-text" id="ckManage" type="button">Tercihlerimi Yönet</button>
        </div>
      </div>
    `;
    return el;
  }

  /* ── Banner'ı kapat ── */
  function hideBanner(banner) {
    banner.classList.add('hiding');
    setTimeout(() => banner.remove(), 450);
  }

  /* ── Banner'ı göster ── */
  function showBanner() {
    const banner = buildBanner();
    document.body.appendChild(banner);

    // Bir tick bekle → transition tetiklensin
    requestAnimationFrame(() => {
      requestAnimationFrame(() => banner.classList.add('visible'));
    });

    /* Tümünü kabul et */
    banner.querySelector('#ckAcceptAll').addEventListener('click', () => {
      saveConsent({ necessary: true, analytics: true, marketing: true, functional: true });
      hideBanner(banner);
    });

    /* Yalnızca zorunlu */
    banner.querySelector('#ckRejectAll').addEventListener('click', () => {
      saveConsent({ necessary: true, analytics: false, marketing: false, functional: false });
      hideBanner(banner);
    });

    /* Tercihlerimi yönet / kapat */
    const manageBtn  = banner.querySelector('#ckManage');
    const prefsPanel = banner.querySelector('#ckPrefs');
    manageBtn.addEventListener('click', () => {
      const open = prefsPanel.classList.toggle('open');
      manageBtn.textContent = open ? 'Gizle' : 'Tercihlerimi Yönet';
    });

    /* Seçimlerimi kaydet */
    banner.querySelector('#ckSavePrefs').addEventListener('click', () => {
      saveConsent({
        necessary: true,
        analytics:  banner.querySelector('#ckAnalytics').checked,
        marketing:  banner.querySelector('#ckMarketing').checked,
        functional: banner.querySelector('#ckFunctional').checked,
      });
      hideBanner(banner);
    });
  }

  /* ── Karar zaten verilmiş mi? ── */
  function init() {
    const saved = getSaved();
    if (saved) {
      // Daha önce onay verilmiş → sadece event yayınla (skript yüklemek için kullanılabilir)
      dispatchConsentEvent(saved);
      return;
    }

    // Splash ekranı kapandıktan sonra göster (varsa), yoksa 600ms gecikme
    const splash = document.getElementById('splashOverlay');
    if (splash) {
      const observer = new MutationObserver(() => {
        const hidden = splash.hidden || splash.style.display === 'none'
          || splash.classList.contains('hide') || splash.getAttribute('aria-hidden') === 'true';
        if (hidden) {
          observer.disconnect();
          setTimeout(showBanner, 800);
        }
      });
      observer.observe(splash, { attributes: true, attributeFilter: ['hidden', 'style', 'class', 'aria-hidden'] });
      // Splash zaten gizliyse direkt göster
      if (splash.hidden) {
        observer.disconnect();
        setTimeout(showBanner, 600);
      }
    } else {
      setTimeout(showBanner, 600);
    }
  }

  /* ── Dışa aç: manuel sıfırlama için (settings sayfasında kullanılabilir) ── */
  window.WebeyConsent = {
    reset() { localStorage.removeItem(STORAGE_KEY); },
    get()   { return getSaved(); },
    open()  { showBanner(); }
  };

  /* ── Başlat ── */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();