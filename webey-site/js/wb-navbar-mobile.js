/**
 * wb-navbar-mobile.js — Mobil Navbar Scroll Collapse
 * ─────────────────────────────────────────────────────
 * Düzeltmeler (v2):
 *  1. Sayfa zıplama yok: --mob-navbar-h animasyon BAŞINDA güncellenir,
 *     sayfadaki padding-top CSS transition ile yumuşakça takip eder.
 *  2. Modal filtresi: herhangi bir modal/overlay açıkken scroll navbar'ı
 *     etkilemez. Modal içi scroll da görmezden gelinir.
 *  3. 200ms polling kaldırıldı (hatalı tetikleme kaynağıydı).
 *  4. Animasyon: daha yumuşak cubic-bezier easing.
 */
(function () {
  'use strict';

  /* ── Modal açık mı? ── */
  function anyModalOpen() {
    if (document.querySelector('.modal-ov.show')) return true;
    if (document.querySelector('.modal-overlay:not([hidden])')) return true;
    var authM = document.getElementById('authModal');
    if (authM && (authM.classList.contains('active') || !authM.hasAttribute('hidden'))) return true;
    if (document.querySelector('#sb-date-overlay[aria-hidden="false"]')) return true;
    if (document.querySelector('#sb-time-overlay.open')) return true;
    return false;
  }

  /* ── Scroll hedefi sayfa mı, yoksa modal içi mi? ── */
  function isPageScroll(target) {
    if (!target || target === document || target === window ||
        target === document.documentElement || target === document.body) {
      return true;
    }
    var node = target;
    while (node && node !== document.body) {
      var cls = (node.className || '').toString();
      var id  = node.id || '';
      if (
        cls.indexOf('modal-ov')      !== -1 ||
        cls.indexOf('modal-overlay') !== -1 ||
        cls.indexOf('modal-box')     !== -1 ||
        cls.indexOf('modal')         !== -1 ||
        id === 'authModal'           ||
        id === 'sb-date-overlay'     ||
        id === 'sb-time-overlay'     ||
        id === 'svcOv'  || id === 'timeOv'   ||
        id === 'staffOv'|| id === 'reviewOv' ||
        id === 'confirmOv' || id === 'imgOv'
      ) {
        return false;
      }
      node = node.parentElement;
    }
    return true;
  }

  function initNavScroll() {
    if (window.innerWidth > 767) return;

    var navbar      = document.getElementById('mobileNavbar');
    var expanded    = document.getElementById('mobExpanded');
    var compactRow  = document.querySelector('.mob-compact-row');
    var compactLogo = document.querySelector('.mob-compact-logo');
    var collapsed   = false;

    function pxVar(name, fallback) {
      var raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
      var n = parseFloat(raw);
      return Number.isFinite(n) ? n : fallback;
    }

    function publishHeight() {
      if (!navbar) return;
      var root = document.documentElement;
      var compactH = pxVar('--mob-navbar-compact-h', 62);
      var navStyles = getComputedStyle(navbar);
      var padTop = parseFloat(navStyles.paddingTop || '0') || 0;
      var padBottom = parseFloat(navStyles.paddingBottom || '0') || 0;
      var rectH = navbar.getBoundingClientRect().height || 0;
      var expandedH = expanded ? expanded.scrollHeight : 0;
      var compactRowH = compactRow ? compactRow.getBoundingClientRect().height : compactH;

      var target = collapsed
        ? Math.max(compactH, compactRowH + padTop + padBottom)
        : Math.max(compactH + 48, expandedH + compactRowH + padTop + padBottom);

      if (rectH > compactH - 4) {
        target = Math.max(target, rectH);
      }

      root.style.setProperty('--mob-navbar-h', Math.round(target) + 'px');
    }

    /* İlk ölçüm: gerçek yüksekliği al, sonra transition'ı aktif et */
    function initHeight() {
      publishHeight();
      /* Kısa gecikme: CSS uygulandıktan sonra transition class'ı ekle */
      setTimeout(function () {
        document.documentElement.classList.add('nav-ready');
        document.body.classList.add('nav-ready');
        document.querySelector('.detail-wrap') &&
          document.querySelector('.detail-wrap').classList.add('nav-ready');
      }, 100);
    }

    function setCollapsed(yes) {
      if (yes === collapsed) return;
      collapsed = yes;

      // body class ile CSS'e bildir
      document.body.classList.toggle('navbar-collapsed', yes);

      if (expanded) {
        expanded.style.transition = 'max-height .42s cubic-bezier(.4,0,.2,1), opacity .35s cubic-bezier(.4,0,.2,1)';
        expanded.style.overflow   = 'hidden';
        expanded.style.maxHeight  = yes ? '0'     : '220px';
        expanded.style.opacity    = yes ? '0'     : '1';
      }
      if (compactLogo) {
        compactLogo.style.transition = 'max-width .38s cubic-bezier(.4,0,.2,1), opacity .3s cubic-bezier(.4,0,.2,1)';
        compactLogo.style.maxWidth   = yes ? '80px' : '0';
        compactLogo.style.opacity    = yes ? '1'    : '0';
      }

      /*
       * --mob-navbar-h'yi gerçek yüksekliğe göre güncelle.
       * requestAnimationFrame: expanded'ın yeni max-height CSS'i uygulandıktan
       * sonraki ilk render frame'inde yüksekliği ölç — hem collapse hem expand'da doğru.
       */
      requestAnimationFrame(function() {
        // Animasyon hedef yüksekliğini CSS'den oku (--mob-navbar-compact-h)
        // Yoksa gerçek navbar yüksekliğini ölç
        var root = document.documentElement;
        if (yes) {
          var compactH = pxVar('--mob-navbar-compact-h', 62);
          if (compactH) {
            root.style.setProperty('--mob-navbar-h', Math.round(compactH) + 'px');
          } else {
            // expanded gizlenince 2 rAF sonra ölç
            requestAnimationFrame(publishHeight);
          }
        } else {
          requestAnimationFrame(publishHeight);
        }
      });

      try {
        document.dispatchEvent(new CustomEvent('wb:navbarCollapse', {
          detail: { collapsed: yes }
        }));
      } catch (_) {}
    }

    initHeight();
    setCollapsed(false);
    setTimeout(publishHeight, 420); /* Fontlar/ikonlar yüklenince tekrar ölç */

    function onScroll(e) {
      if (anyModalOpen()) return;
      if (!isPageScroll(e && e.target)) return;

      var sy = Math.max(
        window.scrollY || 0,
        window.pageYOffset || 0,
        document.documentElement.scrollTop || 0,
        document.body.scrollTop || 0
      );
      setCollapsed(sy > 60);
    }

    window.addEventListener('scroll', onScroll, { passive: true });
    document.addEventListener('scroll', onScroll, { passive: true, capture: false });

    var sentinel = document.getElementById('scrollSentinel');
    if (sentinel && 'IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        if (anyModalOpen()) return;
        setCollapsed(!entries[0].isIntersecting);
      }, { threshold: 0 });
      io.observe(sentinel);
    }

    window.addEventListener('resize', function () {
      if (window.innerWidth > 767) {
        if (expanded)    { expanded.style.maxHeight = ''; expanded.style.opacity = ''; }
        if (compactLogo) { compactLogo.style.maxWidth = ''; compactLogo.style.opacity = ''; }
        collapsed = false;
        document.documentElement.style.removeProperty('--mob-navbar-h');
      } else {
        publishHeight();
      }
    }, { passive: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initNavScroll);
  } else {
    initNavScroll();
  }

  window.wbNavbarMobile = { init: initNavScroll };

})();
