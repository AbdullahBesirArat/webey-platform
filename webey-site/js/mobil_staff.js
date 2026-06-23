(function initMobileStaff() {
  const mq = window.matchMedia('(max-width: 1024px)');
  const staffBody = document.getElementById('staffCardBody');
  const staffTrack = document.getElementById('staffCardTrack');
  const staffRange = document.getElementById('staffCardRange');

  function isMobile() {
    return mq.matches;
  }

  function applyMobileClass() {
    document.documentElement.classList.toggle('is-mobile', isMobile());
  }

  function getStripMaxScroll() {
    if (!staffBody) return 0;
    return Math.max(0, Math.ceil(staffBody.scrollWidth - staffBody.clientWidth));
  }

  function syncRangeFromBody() {
    if (!isMobile() || !staffBody || !staffRange) return;
    staffRange.value = String(Math.round(staffBody.scrollLeft));
  }

  function refreshStaffStrip(options = {}) {
    if (!staffBody || !staffRange) return;

    requestAnimationFrame(() => {
      const maxScroll = getStripMaxScroll();
      const shouldReset = Boolean(options.reset);
      const nextValue = shouldReset ? 0 : Math.min(maxScroll, Math.round(staffBody.scrollLeft));

      staffRange.max = String(maxScroll);
      staffRange.disabled = maxScroll <= 0;

      staffBody.scrollLeft = nextValue;
      staffRange.value = String(nextValue);
    });
  }

  function scrollPanelIntoView() {
    if (!isMobile()) return;
    const panel = document.querySelector('.panel');
    if (!panel) return;
    requestAnimationFrame(() => {
      panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }

  function smoothScrollTop() {
    if (!isMobile()) return;
    const scroller = document.scrollingElement || document.documentElement;
    scroller.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function markRailActive(root) {
    if (!root) return;
    const btns = root.querySelectorAll('.rail__btn, nav.rail a, .rail a');
    if (!btns.length) return;

    let found = false;
    btns.forEach((a) => {
      const href = (a.getAttribute('href') || '').split(/[?#]/)[0];
      const pageAttr = a.dataset ? a.dataset.page : null;
      const isMe = /(^|\/)staff\.html$/i.test(href) || pageAttr === 'staff';

      a.removeAttribute('aria-current');
      if (isMe) {
        a.setAttribute('aria-current', 'page');
        found = true;
      }
    });

    if (!found) {
      const alt = root.querySelector('[data-page="staff"]');
      if (alt) alt.setAttribute('aria-current', 'page');
    }
  }

  applyMobileClass();

  const onMediaChange = () => {
    applyMobileClass();
    refreshStaffStrip({ reset: true });
  };

  if (mq.addEventListener) {
    mq.addEventListener('change', onMediaChange);
  } else if (mq.addListener) {
    mq.addListener(onMediaChange);
  }

  document.querySelectorAll('.tabs .tab[role="tab"]').forEach((tab) => {
    tab.addEventListener('click', () => {
      setTimeout(scrollPanelIntoView, 40);
    });
  });

  staffBody?.addEventListener(
    'scroll',
    () => {
      syncRangeFromBody();
    },
    { passive: true }
  );

  staffBody?.addEventListener('click', (event) => {
    const item = event.target.closest('.staff-item');
    if (!item) return;
    setTimeout(scrollPanelIntoView, 60);
  });

  staffRange?.addEventListener('input', () => {
    if (!staffBody) return;
    staffBody.scrollLeft = Number(staffRange.value || 0);
  });

  ['btnAddSmall', 'btnRemoveSmall'].forEach((id) => {
    const btn = document.getElementById(id);
    btn?.addEventListener('click', () => {
      setTimeout(smoothScrollTop, 80);
    });
  });

  const skip = document.querySelector('.skip-link');
  if (skip) {
    skip.addEventListener('click', () => {
      const main = document.getElementById('main');
      if (!main) return;
      setTimeout(() => {
        main.setAttribute('tabindex', '-1');
        main.focus({ preventScroll: true });
        smoothScrollTop();
      }, 0);
    });
  }

  if (staffTrack) {
    const observer = new MutationObserver(() => {
      refreshStaffStrip({ reset: true });
    });
    observer.observe(staffTrack, { childList: true, subtree: true });
  }

  if (window.ResizeObserver && staffBody) {
    const resizeObserver = new ResizeObserver(() => {
      refreshStaffStrip();
    });
    resizeObserver.observe(staffBody);
    if (staffTrack) resizeObserver.observe(staffTrack);
  } else {
    window.addEventListener('resize', () => {
      refreshStaffStrip();
    });
  }

  window.addEventListener('pageshow', () => {
    refreshStaffStrip({ reset: true });
  });

  window.addEventListener('load', () => {
    refreshStaffStrip({ reset: true });
  });

  markRailActive(document);

  const railMount = document.getElementById('rail-mount');
  if (railMount) {
    const railObserver = new MutationObserver(() => {
      markRailActive(railMount);
    });
    railObserver.observe(railMount, { childList: true, subtree: true });

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        markRailActive(railMount);
      }
    });
  }

  document.addEventListener(
    'keydown',
    (event) => {
      if (event.key === 'Tab') {
        document.documentElement.classList.add('show-focus');
      }
    },
    { once: true }
  );

  refreshStaffStrip({ reset: true });
})();
