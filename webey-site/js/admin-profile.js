/*
 * admin-profile.js — v5
 * Professional billing & subscription management
 * Backend: PHP + iyzico (placeholder endpoints hazır)
 */

'use strict';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
let _me = null;
const GOOGLE_CLIENT_ID =
  document.querySelector('meta[name="google-signin-client_id"]')?.content?.trim()
  || window.GOOGLE_CLIENT_ID
  || '279602177241-o5qmpgshp4g13jlrunnkav6vdu4hiejv.apps.googleusercontent.com';
let _gsiAdminProfilePromise = null;
let _googleLinkBusy = false;

/* ─────────────────────────────────────────────
   PLAN TANIMI
───────────────────────────────────────────── */
let PLANS = {};
let PLAN_ORDER = [];

const fmtPrice = n => '₺' + Number(n).toLocaleString('tr-TR');

function normalizePlanCatalog(rawPlans = {}, order = []) {
  const keys = Array.isArray(order) && order.length ? order : Object.keys(rawPlans);
  const nextPlans = {};

  keys.forEach(key => {
    const plan = rawPlans[key];
    if (!plan) return;
    nextPlans[key] = {
      label: String(plan.display_label || plan.label || key).replace(/\s+Plan$/u, ''),
      months: Number(plan.months) || 0,
      monthlyPrice: Number(plan.monthly_price) || 0,
      total: Number(plan.price) || 0,
      discount: Number(plan.discount_percent) || 0,
    };
  });

  PLANS = nextPlans;
  PLAN_ORDER = keys.filter(key => !!PLANS[key]);
}

function syncPlanCards() {
  $$('[data-plan]').forEach(card => {
    const planId = card.dataset.plan;
    const plan = PLANS[planId];
    if (!plan) return;

    card.dataset.price = String(plan.total);
    card.dataset.months = String(plan.months);

    const periodEl = card.querySelector('.plan-card__period');
    const discountEl = card.querySelector('.plan-card__discount');
    const priceEl = card.querySelector('.plan-card__price');
    const totalEl = card.querySelector('.plan-card__total');

    if (periodEl) periodEl.textContent = plan.label;
    if (discountEl) {
      if (plan.discount > 0) {
        discountEl.style.display = '';
        discountEl.textContent = `%${plan.discount} indirim`;
      } else {
        discountEl.style.display = 'none';
        discountEl.textContent = '';
      }
    }
    if (priceEl) priceEl.textContent = fmtPrice(plan.monthlyPrice);
    if (totalEl) totalEl.textContent = `${fmtPrice(plan.total)} toplam · KDV dahil`;
  });
}

async function loadPlanCatalog() {
  const res = await apiGet('/api/billing/plans.php');
  if (!res?.ok) {
    showToast('Plan bilgileri yüklenemedi', 'error');
    return false;
  }

  normalizePlanCatalog(res.data?.plans || {}, res.data?.order || []);
  syncPlanCards();
  return true;
}

/* ─────────────────────────────────────────────
   TOAST
───────────────────────────────────────────── */
const toastEl = $('#toast');
function showToast(msg = '', type = 'default', duration = 2800) {
  if (!toastEl) return console.log('[toast]', msg);
  toastEl.textContent = msg;
  toastEl.className = 'toast';
  if (type !== 'default') toastEl.classList.add(type);
  toastEl.classList.add('show');
  clearTimeout(toastEl._t);
  toastEl._t = setTimeout(() => (toastEl.className = 'toast'), duration);
}

/* ─────────────────────────────────────────────
   API
───────────────────────────────────────────── */

// ── CSRF Token (api-client.js ile paylaşılan cache) ──────────────────
// ── API Wrapper — window.WbApi (wb-api-shim.js) üzerinden ──────────
async function apiGet(path, params)  { return window.WbApi.get(path, params); }
async function apiPost(path, body)   { return window.WbApi.post(path, body); }
// ─────────────────────────────────────────────────────────────────────

/* ─────────────────────────────────────────────
   YARDIMCILAR
───────────────────────────────────────────── */
function fmtDate(raw) {
  if (!raw) return '—';
  const d = new Date(raw);
  if (isNaN(d)) return '—';
  return d.toLocaleDateString('tr-TR', { day: '2-digit', month: 'short', year: 'numeric' });
}

function setLoading(btn, on, label) {
  if (!btn) return;
  if (on)  { btn._orig = btn.innerHTML; btn.disabled = true; if (label) btn.textContent = label; }
  else     { btn.disabled = false; if (btn._orig !== undefined) btn.innerHTML = btn._orig; }
}

function setGoogleUiState() {
  const badge = $('#googleConnectBadge');
  const text = $('#googleConnectText');
  const btn = $('#googleConnectBtn');
  if (!badge || !text || !btn) return;

  if (_me?.googleConnected) {
    badge.className = 'badge badge--success';
    badge.textContent = 'Google bağlı';
    text.textContent = 'Bu hesap Google ile girişe bağlı. İstersen doğrudan Google ile oturum açabilirsin.';
    btn.disabled = true;
    btn.textContent = 'Google hesabı bağlı';
    return;
  }

  badge.className = 'badge badge--warning';
  badge.textContent = 'Google bağlı değil';
  text.textContent = 'Normal e-posta ile kayıt oldun. Tek tıkla Google hesabını bağlayabilirsin.';
  btn.disabled = _googleLinkBusy;
  btn.textContent = _googleLinkBusy ? 'Bağlanıyor…' : 'Google hesabını bağla';
}

function ensureGoogleScript() {
  if (window.google?.accounts?.id) return Promise.resolve(window.google);
  if (_gsiAdminProfilePromise) return _gsiAdminProfilePromise;

  _gsiAdminProfilePromise = new Promise((resolve, reject) => {
    const existing = document.querySelector('script[data-google-gsi="1"]');
    if (existing) {
      existing.addEventListener('load', () => resolve(window.google), { once: true });
      existing.addEventListener('error', () => reject(new Error('gsi_load_failed')), { once: true });
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.async = true;
    script.defer = true;
    script.dataset.googleGsi = '1';
    script.onload = () => resolve(window.google);
    script.onerror = () => reject(new Error('gsi_load_failed'));
    document.head.appendChild(script);
  }).catch(err => {
    _gsiAdminProfilePromise = null;
    throw err;
  });

  return _gsiAdminProfilePromise;
}

async function requestGoogleCredential() {
  const googleApi = await ensureGoogleScript();
  if (!googleApi?.accounts?.id) throw new Error('gsi_unavailable');

  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new Error('gsi_timeout'));
    }, 30000);

    googleApi.accounts.id.initialize({
      client_id: GOOGLE_CLIENT_ID,
      callback: (response) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        const credential = String(response?.credential || '').trim();
        if (!credential) {
          reject(new Error('missing_google_credential'));
          return;
        }
        resolve(credential);
      },
      auto_select: false,
      cancel_on_tap_outside: true,
    });

    try {
      googleApi.accounts.id.prompt();
    } catch (err) {
      clearTimeout(timeout);
      if (!settled) {
        settled = true;
        reject(err instanceof Error ? err : new Error('gsi_prompt_failed'));
      }
    }
  });
}

async function handleGoogleConnect() {
  if (_googleLinkBusy || _me?.googleConnected) return;
  if (!String(_me?.email || '').trim()) {
    showToast('Önce hesabına e-posta eklemelisin.', 'error');
    return;
  }

  _googleLinkBusy = true;
  setGoogleUiState();

  try {
    const credential = await requestGoogleCredential();
    const res = await apiPost('/api/admin/google-link.php', { credential });
    if (!res?.ok) throw new Error(res?.error || 'Google hesabı bağlanamadı');
    _me = { ...(_me || {}), googleConnected: true, emailVerified: true };
    showToast('Google hesabın bağlandı. Artık Google ile giriş yapabilirsin.', 'success');
  } catch (e) {
    const msg = e?.message === 'gsi_timeout'
      ? 'Google penceresi zaman aşımına uğradı. Tekrar deneyin.'
      : (e?.message || 'Google hesabı bağlanamadı');
    showToast(msg, 'error');
  } finally {
    _googleLinkBusy = false;
    setGoogleUiState();
  }
}

function daysBetween(from, to) {
  return Math.max(0, Math.ceil((to - from) / 86400000));
}

function renderPlanProgress({ start, end, startLabel, daysLabel, percent, mode = 'trial' }) {
  const progressWrap = $('#trialProgressWrap');
  const startLabelEl = $('#trialProgressStartLabel');
  const daysLeftEl = $('#trialDaysLeft');
  const fill = $('#trialProgressFill');

  if (!progressWrap || !startLabelEl || !daysLeftEl || !fill) return;

  progressWrap.hidden = false;
  progressWrap.classList.toggle('is-active', mode === 'active');
  startLabelEl.textContent = startLabel;
  daysLeftEl.textContent = daysLabel;
  fill.style.width = `${Math.max(0, Math.min(100, percent))}%`;
  fill.title = `${Math.round(percent)}%`;
}

/* ─────────────────────────────────────────────
   APP BAR AKTİF
───────────────────────────────────────────── */
(function initAppBar() {
  document.body.classList.add('has-app-bar');
  const cur = document.body.dataset.page || location.pathname.split('/').pop().replace('.html','');
  $$('.app-bar__item').forEach(a => {
    if (a.getAttribute('data-page') === cur) a.classList.add('app-bar__item--active');
  });
})();

/* ─────────────────────────────────────────────
   SEKMELER
───────────────────────────────────────────── */
$$('.tab').forEach(btn => {
  btn.addEventListener('click', () => {
    $$('.tab').forEach(b => { b.classList.remove('is-active'); b.setAttribute('aria-selected','false'); });
    $$('.tab-panel').forEach(p => p.classList.remove('is-active'));
    btn.classList.add('is-active');
    btn.setAttribute('aria-selected','true');
    $('#tab-' + btn.dataset.tab)?.classList.add('is-active');
  });
});

/* ─────────────────────────────────────────────
   MODAL YÖNETİCİSİ
───────────────────────────────────────────── */
const openModal  = el => { el?.classList.add('is-open'); el?.setAttribute('aria-hidden','false'); document.body.style.overflow = 'hidden'; };
const closeModal = el => { el?.classList.remove('is-open'); el?.setAttribute('aria-hidden','true'); document.body.style.overflow = ''; };

document.querySelectorAll('[data-close-modal]').forEach(el => {
  el.addEventListener('click', () => {
    const modal = el.closest('.modal');
    if (modal) closeModal(modal);
  });
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    document.querySelectorAll('.modal.is-open').forEach(m => closeModal(m));
  }
});

/* ─────────────────────────────────────────────
   PROFİL YÜKLE
───────────────────────────────────────────── */
async function loadProfile() {
  const res = await apiGet('/api/profile/me.php');
  if (!res.ok) { showToast('Profil bilgileri alınamadı', 'error'); return; }

  const d = res.data;
  _me = d;
  const brand = d.ownerName || d.businessName || d.email || 'Profil';
  const brandEl = $('#brandName');
  if (brandEl) { brandEl.textContent = brand; document.title = `${brand} · Profil`; }

  /* Hesap */
  if ($('#uid')) $('#uid').textContent = d.uid;
  if ($('#createdAt')) $('#createdAt').textContent = fmtDate(d.createdAt);
  if ($('#lastLogin')) $('#lastLogin').textContent = fmtDate(d.lastLoginAt);
  if ($('#currentEmail')) $('#currentEmail').value = d.email || '';
  if ($('#currentPhone')) $('#currentPhone').value = d.phone ? `0${d.phone}` : '—';
  if ($('#emailVerifyBadge')) {
    const ok = !!d.emailVerified;
    $('#emailVerifyBadge').className = `badge ${ok ? 'badge--success' : 'badge--warning'}`;
    $('#emailVerifyBadge').textContent = ok ? 'E-posta doğrulandı' : 'E-posta doğrulanmadı';
  }
  setGoogleUiState();

  /* Profil linki */
  const viewBtn = $('#viewProfileBtn');
  if (viewBtn && d.businessId) viewBtn.href = `profile.html?id=${encodeURIComponent(d.businessId)}`;

  /* Fatura bilgileri için email pre-fill */
  const billEmail = $('#billEmail');
  if (billEmail) billEmail.value = d.email || '';
  if (d.ownerName) {
    const parts = (d.ownerName || '').trim().split(' ');
    if ($('#billFirstName')) $('#billFirstName').value = parts[0] || '';
    if ($('#billLastName'))  $('#billLastName').value  = parts.slice(1).join(' ') || '';
  }
  if (d.phone && $('#billPhone')) $('#billPhone').value = `+90${d.phone}`;

  /* Billing */
  await renderBilling(d);
}

/* ─────────────────────────────────────────────
   BİLLİNG RENDER
───────────────────────────────────────────── */
async function renderBilling(profileData) {
  const setText = (id, val) => { if ($(id)) $(id).textContent = val; };

  /* Abonelik durumunu API'den al */
  let activeSub = null;
  let trialExpired = false;
  try {
    const subRes = await apiGet('/api/billing/subscriptions.php');
    if (subRes?.ok) {
      const subData = subRes.data || {};
      activeSub = subData.activeSub;
      // Deneme bitti mi?
      const trialRow = subData.subscriptions?.find(s => s.isTrial);
      trialExpired = trialRow && trialRow.status === 'expired';
    }
  } catch (_) {}

  /* Trial hesapla (fallback) */
  const trialEnd   = profileData.createdAt
      ? new Date(new Date(profileData.createdAt).getTime() + 30 * 24 * 3600 * 1000)
      : null;
  const now        = new Date();
  const isTrialing = !activeSub && trialEnd && trialEnd > now;
  const daysLeft   = trialEnd ? Math.max(0, Math.ceil((trialEnd - now) / 86400000)) : 0;
  const trialPct   = trialEnd ? Math.min(100, Math.round((1 - daysLeft/30) * 100)) : 100;

  const badgeEl    = $('#statusBadge');
  const planNameEl = $('#planName');
  const descEl     = $('#subStatusText');

  if (activeSub) {
    /* Aktif ücretli plan var */
    const endDate = activeSub.endDate ? fmtDate(activeSub.endDate) : '—';
    const progressWrap = $('#trialProgressWrap');
    if (activeSub.startDate && activeSub.endDate) {
      const start = new Date(activeSub.startDate);
      const end = new Date(activeSub.endDate);
      const totalDays = Math.max(1, daysBetween(start, end));
      const daysLeft = daysBetween(now, end);
      const elapsedPct = Math.min(100, Math.max(0, ((totalDays - daysLeft) / totalDays) * 100));
      renderPlanProgress({
        start,
        end,
        startLabel: `Dönem başladı · ${fmtDate(activeSub.startDate)}`,
        daysLabel: `${daysLeft} gün kaldı`,
        percent: elapsedPct,
        mode: 'active',
      });
    } else if (progressWrap) {
      progressWrap.hidden = true;
      progressWrap.classList.remove('is-active');
    }

    if (badgeEl)    { badgeEl.textContent = 'Aktif'; badgeEl.className = 'badge badge--success'; }
    if (planNameEl) planNameEl.textContent = activeSub.planLabel;
    if (descEl)     descEl.textContent = `Planınız ${endDate} tarihine kadar geçerli. İstediğiniz zaman plan değiştirebilirsiniz.`;

    setText('#smPlan',        activeSub.planLabel);
    setText('#smStatus',      'Aktif');
    setText('#smPeriodEnd',   endDate);
    // Ödeme yöntemi: promo kodu mu, kart mı?
    {
      const promoEl = $('#smPayMethod');
      if (promoEl) {
        if (activeSub.promoCode) {
          promoEl.innerHTML = `<span style="font-family:var(--font-mono,monospace);color:var(--primary)">${activeSub.promoCode}</span> promosyon kodu`;
        } else if (activeSub.price === 0 || activeSub.price === '0') {
          promoEl.textContent = 'Ücretsiz';
        } else {
          promoEl.textContent = 'Kredi / Banka Kartı';
        }
      }
    }

  } else if (isTrialing) {
    if (badgeEl)    { badgeEl.textContent = 'Deneme Süresi'; badgeEl.className = 'badge badge--warning'; }
    if (planNameEl) planNameEl.textContent = 'Ücretsiz Deneme';
    if (descEl)     descEl.textContent = `${daysLeft} günlük ücretsiz deneme süreniz devam ediyor. Kesintisiz kullanım için bir plan seçin.`;

    setText('#smPlan',        'Ücretsiz Deneme');
    setText('#smStatus',      'Deneme Süresi');
    setText('#smPeriodEnd',   trialEnd ? fmtDate(trialEnd) : '—');
    setText('#smPayMethod',   'Ücretsiz Deneme');

    renderPlanProgress({
      start: profileData.createdAt ? new Date(profileData.createdAt) : null,
      end: trialEnd,
      startLabel: 'Deneme başladı',
      daysLabel: `${daysLeft} gün kaldı`,
      percent: trialPct,
      mode: 'trial',
    });
  } else {
    if (badgeEl)    { badgeEl.textContent = 'Pasif'; badgeEl.className = 'badge badge--danger'; }
    if (planNameEl) planNameEl.textContent = 'Aktif Plan Yok';
    if (descEl)     descEl.textContent = 'Deneme süreniz sona erdi. Dükkanınızı aktif tutmak için bir plan seçin.';

    setText('#smPlan',        '—');
    setText('#smStatus',      'Pasif');
    setText('#smPeriodEnd',   '—');
    setText('#smPayMethod',   '—');

    const progressWrap = $('#trialProgressWrap');
    if (progressWrap) {
      progressWrap.hidden = true;
      progressWrap.classList.remove('is-active');
    }
  }

  /* Manage sub button */
  $('#manageSubBtn')?.addEventListener('click', () => {
    document.querySelector('[data-tab="plans"]')?.click();
    setTimeout(() => $('#plansSection')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 100);
  });

  // Plan tab status bar güncelle
  {
    const tabBadge = $('#planTabBadge');
    const tabName  = $('#planTabName');
    const tabEnd   = $('#planTabEnd');
    if (activeSub) {
      const endDate = activeSub.endDate ? fmtDate(activeSub.endDate) : '—';
      if (tabBadge) { tabBadge.textContent = 'Aktif'; tabBadge.className = 'badge badge--success'; }
      if (tabName)  tabName.textContent = activeSub.planLabel;
      if (tabEnd)   tabEnd.textContent  = `Bitiş: ${endDate}`;
    } else if (isTrialing) {
      if (tabBadge) { tabBadge.textContent = 'Deneme'; tabBadge.className = 'badge badge--warning'; }
      if (tabName)  tabName.textContent = 'Ücretsiz Deneme';
      if (tabEnd)   tabEnd.textContent  = `${daysLeft} gün kaldı`;
    } else {
      if (tabBadge) { tabBadge.textContent = 'Pasif'; tabBadge.className = 'badge badge--danger'; }
      if (tabName)  tabName.textContent = 'Aktif plan yok';
      if (tabEnd)   tabEnd.textContent  = '';
    }
  }

  /* Empty states */
  renderCardsEmpty();
  renderInvoicesEmpty();
}

function renderCardsEmpty() {
  const el = $('#cards');
  if (!el) return;
  el.innerHTML = `
    <div class="empty-state">
      <span class="material-symbols-rounded empty-state__icon">credit_card_off</span>
      <p class="empty-state__text">Kayıtlı kart bulunmuyor.<br>Ödeme yaparken kartınızı kaydedebilirsiniz.</p>
    </div>`;
}

function renderInvoicesEmpty() {
  const el = $('#invoices');
  if (!el) return;
  el.innerHTML = `
    <div class="empty-state">
      <span class="material-symbols-rounded empty-state__icon">receipt_long</span>
      <p class="empty-state__text">Henüz fatura bulunmuyor.<br>Abonelik başlattıktan sonra faturalarınız burada görünecek.</p>
    </div>`;
}

/* ─────────────────────────────────────────────
   PLAN SEÇİMİ
───────────────────────────────────────────── */
let selectedPlanId = null;

$$('[data-select-plan]').forEach(btn => {
  btn.addEventListener('click', e => {
    e.stopPropagation();
    const planId = btn.dataset.selectPlan;
    selectPlan(planId);
  });
});

$$('.plan-card').forEach(card => {
  card.addEventListener('click', () => {
    const planId = card.dataset.plan;
    if (planId) selectPlan(planId);
  });
});

function selectPlan(planId) {
  const plan = PLANS[planId];
  if (!plan) {
    showToast('Plan bilgileri henüz yüklenmedi', 'error');
    return;
  }

  selectedPlanId = planId;

  /* Kartı vurgula */
  $$('.plan-card').forEach(c => c.classList.toggle('is-selected', c.dataset.plan === planId));

  /* Checkout modal doldur */
  fillCheckoutModal(planId, plan);
  openModal($('#checkoutModal'));
}

/* ─────────────────────────────────────────────
   CHECKOUT MODAL DOLDUR
───────────────────────────────────────────── */
function fillCheckoutModal(planId, plan) {
  /* Header summary */
  const setText = (id, val) => { if ($(id)) $(id).textContent = val; };
  setText('#checkoutPlanName',   `${plan.label} Plan`);
  setText('#checkoutPlanPeriod', `${plan.months} aylık erişim · ${fmtPrice(plan.monthlyPrice)}/ay`);
  setText('#checkoutPlanPrice',  fmtPrice(plan.total));
  setText('#checkoutPlanTotal',  plan.discount > 0 ? `%${plan.discount} indirimli` : '');
  setText('#csSummaryPlan',     `Webey ${plan.label} Plan`);

  /* Promo sıfırla — yeni plan seçilince önceki kodu temizle */
  resetPromo();
  const inp = $('#promoCodeInput');
  if (inp) inp.value = '';
}

/* ─────────────────────────────────────────────
   PAY METHOD TABS (Checkout modal içinde)
───────────────────────────────────────────── */
$$('.pay-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const target = tab.dataset.payTab;
    $$('.pay-tab').forEach(t => t.classList.remove('is-active'));
    $$('.pay-tab-panel').forEach(p => p.classList.remove('is-active'));
    tab.classList.add('is-active');
    $(`#payTab-${target}`)?.classList.add('is-active');
  });
});

/* ─────────────────────────────────────────────
   KART NUMARASI FORMAT
───────────────────────────────────────────── */
function formatCardNumber(input) {
  input.addEventListener('input', () => {
    let v = input.value.replace(/\D/g,'').slice(0,16);
    input.value = v.replace(/(.{4})/g,'$1 ').trim();
    detectCardBrand(v);
  });
}

function detectCardBrand(num) {
  const el = $('#cardBrandIcon');
  if (!el) return;
  if (num.startsWith('4'))                       el.textContent = 'VISA';
  else if (/^5[1-5]/.test(num) || /^2[2-7]/.test(num)) el.textContent = 'MC';
  else if (/^3[47]/.test(num))                   el.textContent = 'AMEX';
  else if (/^9792/.test(num))                    el.textContent = 'Troy';
  else                                            el.textContent = '';
}

function formatExpiry(input) {
  input.addEventListener('input', () => {
    let v = input.value.replace(/\D/g,'').slice(0,4);
    if (v.length >= 3) v = v.slice(0,2) + ' / ' + v.slice(2);
    input.value = v;
  });
}

/* ─────────────────────────────────────────────
   PROMO KODU
───────────────────────────────────────────── */
let _appliedPromo = null; // { promo_id, code, discount_label, original_price, final_price, is_free }

function resetPromo() {
  _appliedPromo = null;
  const inp = $('#promoCodeInput');
  const res = $('#promoResult');
  const clearBtn = $('#clearPromoBtn');
  if (inp) inp.disabled = false;
  if (res) { res.style.display = 'none'; res.className = 'promo-result'; res.innerHTML = ''; }
  if (clearBtn) clearBtn.style.display = 'none';
  updateCheckoutSummary();
}

function updateCheckoutSummary() {
  if (!selectedPlanId) return;
  const plan = PLANS[selectedPlanId];
  const discRow = $('#csSummaryDiscountRow');
  const discEl  = $('#csSummaryDiscount');
  const totalEl = $('#csSummaryTotal');
  const btnLbl  = $('#confirmPayBtnLabel');
  const btn     = $('#confirmPayBtn');
  const payMethodSection = document.querySelector('.checkout-section:has(.pay-method-tabs)');
  const billSection = document.querySelectorAll('.checkout-section')[1]; // Fatura Bilgileri
  const legalEl = $('.checkout-legal');

  if (_appliedPromo) {
    if (discRow) discRow.style.display = '';
    if (discEl)  discEl.textContent = `-${_appliedPromo.discount_label}`;
    const final = _appliedPromo.final_price;
    if (totalEl) totalEl.textContent = final === 0 ? '₺0 — Ücretsiz!' : `₺${final.toLocaleString('tr-TR')}`;
    if (btnLbl)  btnLbl.textContent  = final === 0 ? '🎉 Ücretsiz Aktifleştir' : 'Güvenli Ödeme Yap';
    if (btn)     btn.style.background = final === 0 ? 'linear-gradient(135deg,#0ea5b3,#0891b2)' : '';

    // Ücretsizse kart ve fatura alanlarını gizle
    const isFree = final === 0;
    if (payMethodSection) payMethodSection.style.display = isFree ? 'none' : '';
    if (billSection)      billSection.style.display      = isFree ? 'none' : '';
    if (legalEl)          legalEl.style.display          = isFree ? 'none' : '';
    if ($('#checkoutModalTitle')) $('#checkoutModalTitle').textContent = isFree ? 'Ücretsiz Aktifleştir' : 'Planı Satın Al';
  } else {
    if (discRow) discRow.style.display = 'none';
    if (totalEl) totalEl.textContent = `₺${plan.total.toLocaleString('tr-TR')}`;
    if (btnLbl)  btnLbl.textContent  = 'Güvenli Ödeme Yap';
    if (btn)     btn.style.background = '';
    // Kart ve fatura alanlarını göster
    if (payMethodSection) payMethodSection.style.display = '';
    if (billSection)      billSection.style.display      = '';
    if (legalEl)          legalEl.style.display          = '';
    if ($('#checkoutModalTitle')) $('#checkoutModalTitle').textContent = 'Planı Satın Al';
  }
}

$('#applyPromoBtn')?.addEventListener('click', async () => {
  const code = ($('#promoCodeInput')?.value || '').trim().toUpperCase();
  if (!code) { showToast('Lütfen bir promosyon kodu girin', 'error'); return; }
  if (!selectedPlanId) { showToast('Önce bir plan seçin', 'error'); return; }

  const btn = $('#applyPromoBtn');
  const res = $('#promoResult');
  setLoading(btn, true, 'Kontrol...');

  try {
    const data = await apiPost('/api/billing/apply-promo.php', { code, plan: selectedPlanId });
    if (data?.ok) {
      _appliedPromo = data.data;
      if (res) {
        res.style.display = '';
        res.className = 'promo-result success';
        res.innerHTML = `<span class="promo-badge">${data.data.code}</span>${data.data.discount_label} uygulandı!`;
      }
      const inp = $('#promoCodeInput');
      const clearBtn = $('#clearPromoBtn');
      if (inp) inp.disabled = true;
      if (clearBtn) clearBtn.style.display = '';
      updateCheckoutSummary();
      showToast(`✅ ${data.data.discount_label} kazandınız!`, 'success');
    } else {
      if (res) {
        res.style.display = '';
        res.className = 'promo-result error';
        res.innerHTML = data?.error || 'Geçersiz kod';
      }
    }
  } catch {
    showToast('Kod doğrulanamadı', 'error');
  } finally {
    setLoading(btn, false);
  }
});

$('#clearPromoBtn')?.addEventListener('click', resetPromo);

$('#promoCodeInput')?.addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); $('#applyPromoBtn')?.click(); }
});

/* ─────────────────────────────────────────────
   ÖDEME ONAYLA
───────────────────────────────────────────── */
$('#confirmPayBtn')?.addEventListener('click', async () => {
  if (!selectedPlanId) { showToast('Plan seçilmedi', 'error'); return; }

  const plan = PLANS[selectedPlanId];
  const btn  = $('#confirmPayBtn');

  // ── Ücretsiz promo kodu varsa kart formu atla ──────────────
  if (_appliedPromo?.is_free) {
    setLoading(btn, true);
    btn.innerHTML = `<span class="material-symbols-rounded" style="font-size:17px">hourglass_top</span> Aktifleştiriliyor…`;
    try {
      const res = await apiPost('/api/billing/subscribe.php', {
        plan: selectedPlanId,
        promo_code: _appliedPromo.code,
      });
      if (res && res.ok) {
        closeModal($('#checkoutModal'));
        showToast(`🎉 ${plan.label} plan ücretsiz aktifleştirildi!`, 'success', 4000);
        setTimeout(() => location.reload(), 2000);
      } else {
        showToast(res?.error || 'Aktifleştirilemedi.', 'error');
      }
    } catch (err) {
      showToast('Hata: ' + err.message, 'error');
    } finally {
      setLoading(btn, false);
    }
    return;
  }

  /* Aktif sekme */
  const activeTab = document.querySelector('.pay-tab.is-active')?.dataset.payTab;

  if (activeTab === 'new-card') {
    /* Form doğrulama */
    const name   = ($('#ccName')?.value   || '').trim();
    const number = ($('#ccNumber')?.value || '').replace(/\s/g,'');
    const expiry = ($('#ccExpiry')?.value || '').replace(/\s/g,'');
    const cvv    = ($('#ccCvv')?.value    || '').trim();
    const fname  = ($('#billFirstName')?.value || '').trim();
    const lname  = ($('#billLastName')?.value  || '').trim();
    const email  = ($('#billEmail')?.value     || '').trim();
    const phone  = ($('#billPhone')?.value     || '').trim();

    if (!name)              { showToast('Kart üzerindeki isim gerekli', 'error'); return; }
    if (number.length < 15) { showToast('Geçerli kart numarası girin', 'error'); return; }
    if (expiry.length < 4)  { showToast('Geçerli son kullanma tarihi girin', 'error'); return; }
    if (cvv.length < 3)     { showToast('Geçerli CVV girin', 'error'); return; }
    if (!fname || !lname)   { showToast('Fatura için ad ve soyad gerekli', 'error'); return; }
    if (!email || !email.includes('@')) { showToast('Geçerli e-posta girin', 'error'); return; }

    const [expMonth, expYear] = expiry.split('/').map(s => s.trim());

    setLoading(btn, true);
    btn.innerHTML = `<span class="material-symbols-rounded" style="font-size:17px">hourglass_top</span> İşleniyor…`;

    try {
      const res = await apiPost('/api/billing/subscribe.php', {
        plan:         selectedPlanId,
        promo_code:   _appliedPromo?.code || undefined,
        cardHolderName: name,
        cardNumber:   number,
        expireMonth:  expMonth,
        expireYear:   expYear,
        cvc:          cvv,
        saveCard:     $('#saveCardCheck')?.checked || false,
        buyer: { firstName: fname, lastName: lname, email, phone },
      });

      if (res && res.ok) {
        if (res.requiresAction && res.checkoutUrl) {
          // İyzico ödeme sayfasına yönlendir
          showToast('Ödeme sayfasına yönlendiriliyorsunuz...', 'info');
          setTimeout(() => { window.location.href = res.checkoutUrl; }, 800);
          return;
        }
        closeModal($('#checkoutModal'));
        showToast(`🎉 ${plan.label} plan başarıyla aktifleştirildi!`, 'success', 4000);
        setTimeout(() => location.reload(), 2000);
      } else {
        showToast(res?.error || 'Ödeme işlemi başlatılamadı.', 'error');
      }
    } catch (err) {
      showToast('Ödeme sırasında bir hata oluştu: ' + err.message, 'error');
    } finally {
      setLoading(btn, false);
    }

  } else {
    /* Kayıtlı kart */
    const selected = document.querySelector('.saved-card-option.is-selected');
    if (!selected) { showToast('Lütfen bir kart seçin', 'error'); return; }

    setLoading(btn, true);
    btn.textContent = 'İşleniyor…';

    try {
      const res = await apiPost('/api/billing/subscribe.php', {
        plan:       selectedPlanId,
        promo_code: _appliedPromo?.code || undefined,
        cardToken:  selected.dataset.token,
      });

      if (res && res.ok) {
        if (res.requiresAction && res.checkoutUrl) {
          showToast('Ödeme sayfasına yönlendiriliyorsunuz...', 'info');
          setTimeout(() => { window.location.href = res.checkoutUrl; }, 800);
          return;
        }
        closeModal($('#checkoutModal'));
        showToast(`🎉 ${plan.label} plan başarıyla aktifleştirildi!`, 'success', 4000);
        setTimeout(() => location.reload(), 2000);
      } else {
        showToast(res?.error || 'Ödeme işlemi başlatılamadı.', 'error');
      }
    } catch (err) {
      showToast('Ödeme sırasında bir hata oluştu: ' + err.message, 'error');
    } finally {
      setLoading(btn, false);
    }
  }
});

/* ─────────────────────────────────────────────
   KART EKLE
───────────────────────────────────────────── */
$('#addCardBtn')?.addEventListener('click', () => {
  ['#acName','#acNumber','#acExpiry','#acCvv'].forEach(id => { if ($(id)) $(id).value = ''; });
  openModal($('#addCardModal'));
});

$('#saveAddCardBtn')?.addEventListener('click', async () => {
  const name   = ($('#acName')?.value   || '').trim();
  const number = ($('#acNumber')?.value || '').replace(/\s/g,'');
  const expiry = ($('#acExpiry')?.value || '').replace(/\s/g,'');
  const cvv    = ($('#acCvv')?.value    || '').trim();

  if (!name)              { showToast('Kart üzerindeki isim gerekli', 'error'); return; }
  if (number.length < 15) { showToast('Geçerli kart numarası girin', 'error'); return; }
  if (expiry.length < 4)  { showToast('Geçerli son kullanma tarihi girin', 'error'); return; }
  if (cvv.length < 3)     { showToast('Geçerli CVV girin', 'error'); return; }

  const btn = $('#saveAddCardBtn');
  setLoading(btn, true, 'Kaydediliyor…');
  try {
    const res = await apiPost('/api/billing/add-card.php', { cardHolderName: name, cardNumber: number, expireMonth: expiry.split('/')[0]?.trim(), expireYear: expiry.split('/')[1]?.trim(), cvc: cvv });
    if (res?.ok) {
      closeModal($('#addCardModal'));
      showToast('Kart başarıyla kaydedildi', 'success');
      await loadSavedCards();
    } else {
      showToast(res?.error || 'Kart kaydedilemedi', 'error');
    }
  } catch (err) {
    showToast('Hata: ' + err.message, 'error');
  } finally {
    setLoading(btn, false);
  }
});

/* ─────────────────────────────────────────────
   KAYITLI KARTLARI YÜKLE
───────────────────────────────────────────── */
async function loadSavedCards() {
  try {
    const res = await apiGet('/api/billing/cards.php');
    if (res?.ok && Array.isArray(res.cards) && res.cards.length > 0) {
      renderCardsList(res.cards);
      renderSavedCardsForCheckout(res.cards);
    } else {
      renderCardsEmpty();
    }
  } catch (_) {
    renderCardsEmpty();
  }
}

function renderCardsList(cards) {
  const el = $('#cards');
  if (!el) return;
  el.innerHTML = cards.map(c => `
    <div class="card-row">
      <div class="card-row__left">
        <div class="card-row__icon">
          <span class="material-symbols-rounded" style="font-size:18px">credit_card</span>
        </div>
        <div class="card-row__meta">
          <strong>${c.brand || 'Kart'} •••• ${c.last4 || '****'}</strong>
          <span>Son Kullanma: ${c.expMonth}/${c.expYear}</span>
        </div>
      </div>
      <div class="card-row__actions">
        ${c.isDefault ? '<span class="card-row__default">Varsayılan</span>' : ''}
        <button class="btn btn--sm btn--soft" data-remove-card="${c.token}" type="button">
          <span class="material-symbols-rounded" style="font-size:15px">delete</span>
          Sil
        </button>
      </div>
    </div>`).join('');

  el.querySelectorAll('[data-remove-card]').forEach(btn => {
    btn.addEventListener('click', () => removeCard(btn.dataset.removeCard, btn));
  });
}

function renderSavedCardsForCheckout(cards) {
  const el = $('#savedCardsForCheckout');
  if (!el || !cards.length) return;
  el.innerHTML = cards.map((c, i) => `
    <div class="saved-card-option${i === 0 ? ' is-selected' : ''}" data-token="${c.token}">
      <input type="radio" name="savedCard" value="${c.token}" ${i===0?'checked':''} />
      <div class="saved-card-option__info">
        <strong>${c.brand || 'Kart'} •••• ${c.last4 || '****'}</strong>
        <span>Son Kullanma: ${c.expMonth}/${c.expYear}</span>
      </div>
    </div>`).join('');

  el.querySelectorAll('.saved-card-option').forEach(opt => {
    opt.addEventListener('click', () => {
      el.querySelectorAll('.saved-card-option').forEach(o => o.classList.remove('is-selected'));
      opt.classList.add('is-selected');
      opt.querySelector('input[type="radio"]').checked = true;
    });
  });
}

async function removeCard(token, btn) {
  if (!confirm('Bu kartı silmek istediğinizden emin misiniz?')) return;
  setLoading(btn, true, 'Siliniyor…');
  try {
    const res = await apiPost('/api/billing/remove-card.php', { token });
    if (res?.ok) {
      showToast('Kart silindi', 'success');
      await loadSavedCards();
    } else {
      showToast(res?.error || 'Kart silinemedi', 'error');
    }
  } catch (err) {
    showToast('Hata: ' + err.message, 'error');
  } finally {
    setLoading(btn, false);
  }
}

/* ─────────────────────────────────────────────
   FATURALARI YÜKLE
───────────────────────────────────────────── */
async function loadInvoices() {
  try {
    const res = await apiGet('/api/billing/invoices.php');
    if (res?.ok && Array.isArray(res.invoices) && res.invoices.length > 0) {
      renderInvoicesList(res.invoices);
      const exportBtn = $('#exportInvoicesBtn');
      if (exportBtn) exportBtn.hidden = false;
    } else {
      renderInvoicesEmpty();
    }
  } catch (_) {
    renderInvoicesEmpty();
  }
}

function renderInvoicesList(invoices) {
  const el = $('#invoices');
  if (!el) return;
  el.innerHTML = invoices.map(inv => `
    <div class="invoice-row">
      <div class="invoice-row__info">
        <strong>${inv.planLabel || 'Webey Plan'}</strong>
        <span>${fmtDate(inv.createdAt)} · ${inv.period || ''}</span>
      </div>
      <div class="invoice-row__right">
        <span class="badge ${inv.status === 'paid' ? 'badge--success' : 'badge--danger'}">
          ${inv.status === 'paid' ? 'Ödendi' : 'Beklemede'}
        </span>
        <span class="invoice-row__amount">${fmtPrice(inv.amount)}</span>
        ${inv.pdfUrl ? `<a href="${inv.pdfUrl}" class="btn btn--sm btn--soft" target="_blank">
          <span class="material-symbols-rounded" style="font-size:15px">download</span>PDF
        </a>` : ''}
      </div>
    </div>`).join('');
}

/* ─────────────────────────────────────────────
   ABONELİĞİ İPTAL
───────────────────────────────────────────── */
$('#cancelAtPeriodEnd')?.addEventListener('click', async () => {
  const confirmed = confirm('Aboneliğinizi dönem sonunda iptal etmek istediğinizden emin misiniz?\n\nKalan süre boyunca erişiminiz devam eder.');
  if (!confirmed) return;

  const btn = $('#cancelAtPeriodEnd');
  setLoading(btn, true, 'İptal ediliyor…');
  try {
    const res = await apiPost('/api/billing/cancel.php', { at_period_end: true });
    if (res?.ok) {
      showToast('Aboneliğiniz dönem sonunda iptal edilecek', 'info', 4000);
      setTimeout(() => location.reload(), 2000);
    } else {
      showToast(res?.error || 'İptal işlemi başarısız', 'error');
    }
  } catch (err) {
    showToast('Hata: ' + err.message, 'error');
  } finally {
    setLoading(btn, false);
  }
});

/* ─────────────────────────────────────────────
   PROFİL AKSİYON SAYFALARI
───────────────────────────────────────────── */
function openProfileActionPage(path) {
  const win = window.open(path, '_blank', 'noopener');
  if (!win) showToast('Tarayıcı yeni sekmeyi engelledi', 'error');
}

$('#openEmailUpdatePage')?.addEventListener('click', () => openProfileActionPage('email-guncelle.html'));
$('#openPasswordPage')?.addEventListener('click', () => openProfileActionPage('sifre-degistir-profil.html'));
$('#openPhoneUpdatePage')?.addEventListener('click', () => openProfileActionPage('telefon-guncelle.html'));
$('#googleConnectBtn')?.addEventListener('click', handleGoogleConnect);

/* ─────────────────────────────────────────────
   ÇIKIŞ YAP
───────────────────────────────────────────── */
$('#logoutBtn')?.addEventListener('click', async () => {
  try { await apiPost('/api/profile/logout.php', {}); } catch (_) {}
  location.href = 'admin-register-login.html#login';
});

/* ─────────────────────────────────────────────
   KART FORMAT UYGULA
───────────────────────────────────────────── */
const ccNumberEl = $('#ccNumber');
const ccExpiryEl = $('#ccExpiry');
const acNumberEl = $('#acNumber');
const acExpiryEl = $('#acExpiry');

if (ccNumberEl) formatCardNumber(ccNumberEl);
if (ccExpiryEl) formatExpiry(ccExpiryEl);
if (acNumberEl) formatCardNumber(acNumberEl);
if (acExpiryEl) formatExpiry(acExpiryEl);

/* ─────────────────────────────────────────────
   INIT
───────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', async () => {
  try {
    await loadPlanCatalog();
    await loadProfile();
    await Promise.allSettled([loadSavedCards(), loadInvoices(), loadSubscriptionHistory()]);
  } catch (err) {
    if (err.message !== 'UNAUTHORIZED') {
      console.error('[admin-profile]', err);
      showToast('Profil yüklenemedi: ' + err.message, 'error');
    }
  }
});

window.addEventListener('focus', () => { loadProfile().catch(() => {}); });
window.addEventListener('storage', (e) => {
  if (e.key === 'wb_profile_refresh') loadProfile().catch(() => {});
});
/* ─────────────────────────────────────────────
   ÖNCEKİ PLANLARIM
───────────────────────────────────────────── */
async function loadSubscriptionHistory() {
  const el = $('#planHistoryList');
  if (!el) return;

  try {
    const res = await apiGet('/api/billing/subscriptions.php');
    const subData = res?.data || {};
    if (!res?.ok || !subData.subscriptions?.length) {
      el.innerHTML = '<p class="empty-state__text" style="padding:16px;color:var(--muted)">Henüz plan geçmişi bulunmuyor.</p>';
      return;
    }

    const STATUS_MAP = {
      trialing:  { label: 'Deneme',   cls: 'badge--warning' },
      active:    { label: 'Aktif',    cls: 'badge--success' },
      queued:    { label: 'Bekliyor', cls: 'badge--gray'    },
      cancelled: { label: 'İptal',    cls: 'badge--danger'  },
      expired:   { label: 'Sona Erdi', cls: 'badge--gray'   },
      past_due:  { label: 'Gecikmiş', cls: 'badge--danger'  },
    };

    el.innerHTML = subData.subscriptions.map(sub => {
      const s = STATUS_MAP[sub.status] || { label: sub.status, cls: 'badge--gray' };
      const start = sub.startDate ? fmtDate(sub.startDate) : '—';
      const end   = sub.endDate   ? fmtDate(sub.endDate)   : '—';
      const price = sub.price === 0 ? '₺0 · Ücretsiz' : fmtPrice(sub.price);
      const trialIcon = sub.isTrial ? '🎁 ' : '';

      return `
      <div class="invoice-row" style="padding:14px 0;border-bottom:1px solid var(--border-light, #f0efe9)">
        <div class="invoice-row__info">
          <strong>${trialIcon}${sub.planLabel}</strong>
          <span style="font-size:12px;color:var(--muted)">${start} → ${end}</span>
        </div>
        <div class="invoice-row__right">
          <span class="badge ${s.cls}">${s.label}</span>
          <span class="invoice-row__amount" style="font-size:13px">${price}</span>
        </div>
      </div>`;
    }).join('');

  } catch (_) {
    el.innerHTML = '<p class="empty-state__text" style="padding:16px;color:var(--muted)">Plan geçmişi yüklenemedi.</p>';
  }
}
