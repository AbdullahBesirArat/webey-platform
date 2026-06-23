/* =========================================================
  kuafor.js — Kuaför listesi
  (v4.1.3 — Gün modali eklendi: “Ne zaman?” tıkla ⇒ tarih yoksa GÜN, varsa SAAT.
            Saat modalinde “Tarihi Değiştir” + başlıkta seçili tarih.)
  (v4.1.2 — “Ne zaman?” butonu direkt saat modali açar + Filtre ZAMAN tek buton)
  (v4.1.1 — Zaman modali üstte, Hizmet arama + “Seç/Seçildi” butonları)
========================================================= */

import { api, getSession, onAuthChange } from "./api-client.js";
import { loadListingBusinesses } from "./public-businesses-store.js";


/* ---------- Z-INDEX SABİTLERİ ---------- */
const Z = { modal: 10030, date: 10040, time: 2147483000, dob: 2147483625 };

/* ---------- Helpers ---------- */
const $ = (s, r = document) => r.querySelector(s);
const TL = v => "₺" + Number(v || 0).toLocaleString("tr-TR");
const escapeHTML = (s = "") =>
  String(s).replace(/[&<>"']/g, m => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[m]));
const TR_DAYS = ["Pazar","Pazartesi","Salı","Çarşamba","Perşembe","Cuma","Cumartesi"];
const TR_DAY_IDX = { "pazar":0,"pazartesi":1,"salı":2,"çarşamba":3,"perşembe":4,"cuma":5,"cumartesi":6 };
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t=setTimeout(()=>fn(...a), ms); }; };

/* Güvenli URL */
function safeURL(src, fallback = "img/hero-cover.webp") {
  const s = String(src || "").trim();
  if (!s) return fallback;
  try {
    const u = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(s)
      ? new URL(s, location.origin)
      : new URL(s.replace(/^\/+/, ""), `${location.origin}/`);
    if (u.protocol === "http:" || u.protocol === "https:") return u.href;
  } catch {}
  return fallback;
}

function toUrlList(input) {
  if (Array.isArray(input)) {
    return input.flatMap(item => toUrlList(item)).filter(Boolean);
  }
  if (input && typeof input === "object") {
    const raw = input.url || input.src || input.path || "";
    return raw ? [String(raw).trim()] : [];
  }
  const raw = String(input || "").trim();
  return raw ? [raw] : [];
}

function buildGalleryEntries(row) {
  const originals = [
    ...toUrlList(row.images?.cover).slice(0, 1),
    ...toUrlList(row.images?.salon).slice(0, 1),
    ...toUrlList(row.images?.model).slice(0, 1),
  ];
  const preferred = [
    ...toUrlList(row.images?.cover_opt).slice(0, 1),
    ...toUrlList(row.images?.salon_opt).slice(0, 1),
    ...toUrlList(row.images?.model_opt).slice(0, 1),
  ];
  const galleryList = Array.isArray(row.gallery) ? row.gallery.slice(0, 3) : [];
  const primary = galleryList.length ? galleryList : preferred;
  const entries = primary.map((src, i) => ({
    src: safeURL(src),
    fallback: safeURL(originals[i] || src),
  }));

  if (!entries.length) {
    const cover = safeURL(toUrlList(row.coverUrl)[0] || toUrlList(row.logoUrl)[0] || "img/hero-cover.webp");
    entries.push({ src: cover, fallback: cover });
  }
  return entries;
}

/* Body scroll kilidi senkronizasyonu */
function syncBodyScrollLock() {
  const anyOpen = document.querySelector(
    ".modal-overlay.active, .filter-overlay.active, #timeOverlay.active, #sb-date-overlay.open"
  );
  document.body.classList.toggle("no-scroll", !!anyOpen);
}

/* =========================================================
  AUTH BOOTSTRAP
========================================================= */

function openModal(id="authModal"){
  const m = document.getElementById(id); if (!m) return;
  m.removeAttribute("hidden");
  m.classList.add("active");
  m.style.zIndex = Z.modal;
  m.setAttribute("aria-hidden","false");
  syncBodyScrollLock();
}
function closeTopMostModal(){
  const opened = Array.from(document.querySelectorAll(".modal-overlay.active"));
  if (!opened.length) return;
  const top = opened[opened.length - 1];
  top.classList.remove("active");
  top.setAttribute("aria-hidden","true");
  top.setAttribute("hidden","");
  syncBodyScrollLock();
}
window.AppModals = { openModal };

function injectAuthModalsIfMissing(){
  if (!document.getElementById("authModal")) {
    const host = document.createElement("div");
    host.innerHTML = `
      <!-- AUTH -->
      <div id="authModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="loginRegisterTitle" hidden>
        <div class="modal-box" role="document">
          <button class="modal-close" type="button" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <div class="auth-container">
            <h2 id="loginRegisterTitle" class="sr-only">Giriş / Kayıt</h2>
            <div class="auth-tabs" aria-controls="loginForm signupForm" role="tablist">
              <button class="auth-tab active" data-tab="login" type="button" role="tab" aria-selected="true" aria-controls="loginForm">Giriş Yap</button>
              <button class="auth-tab" data-tab="signup" type="button" role="tab" aria-selected="false" aria-controls="signupForm">Kayıt Ol</button>
            </div>
            <form id="loginForm" class="auth-form active" data-form="login" autocomplete="off" role="tabpanel" aria-labelledby="loginRegisterTitle">
              <h2>Giriş Yap</h2>
              <input class="auth-input" type="email" name="email" placeholder="E-posta" inputmode="email" autocomplete="email" required aria-label="E-posta" />
              <div class="password-wrap">
                <input class="auth-input" type="password" name="password" placeholder="Şifre" autocomplete="current-password" aria-label="Şifre" required minlength="8" />
                <button type="button" class="toggle-eye" aria-label="Şifreyi göster"><i class="fa-regular fa-eye"></i></button>
              </div>
              <div class="form-row" style="margin:6px 0 0; display:flex; justify-content:flex-end;">
                <a id="forgotLink" href="sifremi-unuttum.html" class="link">Şifremi Unuttum</a>
              </div>
              <div id="loginError" class="error" aria-live="assertive"></div>
              <button type="submit" class="auth-btn" id="btnLogin">Giriş Yap</button>
            </form>
            <form id="signupForm" class="auth-form" data-form="signup" autocomplete="one-time-code" role="tabpanel" aria-labelledby="loginRegisterTitle">
              <input class="auth-input" type="email" name="email" placeholder="E-posta" inputmode="email" autocomplete="email" required aria-label="E-posta" />
              <div class="phone-hint">Doğrulama kodu bu e-posta adresine gönderilecek</div>
              <div id="signupError" class="error" aria-live="assertive"></div>
              <label class="terms-check" style="display:flex;align-items:flex-start;gap:10px;margin-bottom:14px;cursor:pointer">
                <input type="checkbox" id="termsAgree" required style="margin-top:3px;width:16px;height:16px;accent-color:#0ea5b3;flex-shrink:0"/>
                <span style="font-size:12.5px;color:#6b6b6b;line-height:1.55">
                  <a href="kullanim-kosullari.html" target="_blank" style="color:#0ea5b3;font-weight:600">Kullanım Koşulları</a>'nı,
                  <a href="gizlilik-politikasi.html" target="_blank" style="color:#0ea5b3;font-weight:600">Gizlilik Politikası</a>'nı ve
                  <a href="cerez-politikasi.html" target="_blank" style="color:#0ea5b3;font-weight:600">Çerez Politikası</a>'nı okudum, kabul ediyorum.
                </span>
              </label>
              <button type="submit" class="auth-btn" id="btnSendOtp">Devam Et →</button>
              <div class="auth-divider"><span>veya</span></div>
              <button type="button" class="auth-google-btn" id="btnGoogleSignup">
                <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true">
                  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
                  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
                  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
                  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
                </svg>
                Google ile Devam Et
              </button>
            </form>
          </div>
        </div>
      </div>

      <!-- OTP -->
      <div id="otpModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="otpTitle" hidden>
        <div class="modal-box" role="document">
          <button class="modal-close" type="button" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <div class="auth-container">
            <h2 id="otpTitle" class="modal-title-center">Doğrulama Kodu</h2>
            <p class="modal-subtitle">Gönderilen 6 haneli kodu gir.</p>
            <form id="otpForm" class="auth-form active" data-form="otp" autocomplete="one-time-code">
              <input class="auth-input otp-input" type="text" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" name="code" placeholder="- - - - - -" required aria-label="Doğrulama kodu" />
              <div id="otpError" class="error" aria-live="assertive"></div>
              <button type="submit" class="auth-btn" id="btnVerifyOtp">Doğrula</button>
              <button type="button" class="resend-otp" id="btnResendOtp">Kodu Tekrar Gönder</button>
            </form>
          </div>
        </div>
      </div>

      <!-- ŞİFRE -->
      <div id="passModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="passTitle" hidden>
        <div class="modal-box" role="document">
          <button class="modal-close" type="button" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <div class="auth-container">
            <h2 id="passTitle" class="modal-title-center">Güvenli Şifre Oluştur</h2>
            <p class="modal-subtitle">En az 8 karakter olmalı.</p>
            <form id="passForm" class="auth-form active" data-form="pass" autocomplete="new-password">
              <div class="password-wrap">
                <input class="auth-input" type="password" name="password" placeholder="Şifre" aria-label="Şifre" required minlength="8" />
                <button type="button" class="toggle-eye" aria-label="Şifreyi göster"><i class="fa-regular fa-eye"></i></button>
              </div>
              <div class="password-wrap">
                <input class="auth-input" type="password" name="confirm"  placeholder="Şifre (tekrar)" aria-label="Şifre (tekrar)" required minlength="8" />
                <button type="button" class="toggle-eye" aria-label="Şifreyi göster"><i class="fa-regular fa-eye"></i></button>
              </div>
              <div id="passError" class="error" aria-live="assertive"></div>
              <button type="submit" class="auth-btn" id="btnPassNext" disabled>Devam Et</button>
            </form>
          </div>
        </div>
      </div>

      <!-- KİMLİK -->
      <div id="nameModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="nameTitle" hidden>
        <div class="modal-box" role="document">
          <button class="modal-close" type="button" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <div class="auth-container">
            <h2 id="nameTitle" class="modal-title-center">Kimlik Bilgileri</h2>
            <p class="modal-subtitle">Ad ve soyadınız randevu alacağınız salon tarafından görülebilir. <strong>Doğru bilgi</strong> önemlidir.</p>
            <form id="nameForm" class="auth-form active" data-form="name">
              <div class="field-row-2">
                <input class="auth-input" type="text" name="firstName" placeholder="Ad" autocomplete="given-name" required />
                <input class="auth-input" type="text" name="lastName"  placeholder="Soyad" autocomplete="family-name" required />
              </div>
              <div class="phone-row" style="margin-top:10px;">
                <div class="cc-box" aria-hidden="true"><span class="flag" role="img" aria-label="Türkiye">🇹🇷</span><span class="cc">+90</span></div>
                <input class="auth-input phone-input" type="tel" name="phone" placeholder="5xx xxx xx xx" inputmode="numeric" maxlength="13" autocomplete="tel-national" data-phone required aria-label="Telefon numarası" />
              </div>
              <div class="phone-hint">Türkiye numarası · 10 hane · 5xx ile başlamalı</div>
              <div class="field"><input class="auth-input" type="date" name="birthday" required /></div>
              <div id="nameError" class="error" aria-live="assertive"></div>
              <button type="submit" class="auth-btn" id="btnNameNext" disabled>Devam Et</button>
            </form>
          </div>
        </div>
      </div>

      <!-- ADRES -->
      <div id="addressModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="addrTitle" hidden>
        <div class="modal-box" role="document">
          <button class="modal-close" type="button" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <div class="auth-container">
            <h2 id="addrTitle" class="modal-title-center">Adres Bilgileri</h2>
            <p class="modal-subtitle">Yakınındaki berberleri önermek için kullanacağız.</p>
            <form id="addressForm" class="auth-form active" data-form="address" autocomplete="address-level1 address-level2 address-level3">
              <div class="field-row-2">
                <select id="citySelect" name="city" class="auth-input" required disabled autocomplete="address-level1">
                  <option value="" selected disabled>Şehir seçin</option>
                </select>
                <select id="districtSelect" name="district" class="auth-input" required disabled autocomplete="address-level2">
                  <option value="" selected disabled>İlçe seçin</option>
                </select>
              </div>
              <select id="neighborhoodSelect" name="neighborhood" class="auth-input" required disabled autocomplete="address-level3">
                <option value="" selected disabled>Önce ilçe seçin</option>
              </select>
              <div id="addressError" class="error" aria-live="assertive"></div>
              <button type="submit" class="auth-btn" id="btnFinish" disabled>Kaydı Tamamla</button>
            </form>
          </div>
        </div>
      </div>
    `;
    document.body.appendChild(host);

    document.querySelectorAll(".modal-overlay").forEach(m => {
      if (m._wbBound) return;
      m._wbBound = true;
      m.style.zIndex = Z.modal;
      m.addEventListener("click", (e) => { if (e.target === m) closeTopMostModal(); });
      m.querySelector(".modal-close")?.addEventListener("click", () => closeTopMostModal());
    });
  }
  if (!document.getElementById("recaptcha-container")){
    const rc = document.createElement("div");
    rc.id = "recaptcha-container"; rc.className = "sr-only";
    document.body.appendChild(rc);
  }
  if (!document.getElementById("toast")){
    const t = document.createElement("div");
    t.id = "toast"; t.className = "toast"; t.setAttribute("role","status");
    t.setAttribute("aria-live","polite"); t.setAttribute("aria-atomic","true");
    document.body.appendChild(t);
  }
}

async function openAuthFlow(e){
  if (e){ e.preventDefault(); e.stopPropagation(); }
  try{
    if (!window.__authLoaded){
      window.__authLoaded = true;
      await import("./auth.js");
      document.dispatchEvent(new Event("auth:ready"));
    }
  }catch(err){ console.warn("auth lazy import failed:", err); }
  injectAuthModalsIfMissing();
  openModal("authModal");
  bumpDobZ();
}

document.addEventListener("click", (e) => {
  const el = e.target.closest(".open-auth, [data-profile-btn]");
  if (!el) return;
  if (el.hasAttribute("data-goto-profile")) return;
  e.preventDefault();
  e.stopPropagation();
  injectAuthModalsIfMissing();
  openAuthFlow(e);
}, { capture: true });

document.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-goto-profile]");
  if (!btn) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  window.location.href = "user-profile.html";
}, { capture: true });

document.addEventListener("keydown", (e) => {
  const btn = e.target.closest?.("[data-goto-profile]");
  if (!btn) return;
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    e.stopImmediatePropagation();
    window.location.href = "user-profile.html";
  }
}, { capture: true });

function updateAuthButtons(session){
  document.querySelectorAll(".profile").forEach(el=>{
    const textEl = el.querySelector(".auth-text") || el.querySelector("span");
    if (session){
      if (textEl) textEl.textContent = "Profilim";
      el.classList.remove("open-auth");
      el.setAttribute("data-goto-profile","1");
      el.setAttribute("aria-label","Profilim");
    }else{
      if (textEl) textEl.textContent = "Giriş Yap / Kayıt Ol";
      el.classList.add("open-auth");
      el.removeAttribute("data-goto-profile");
      el.setAttribute("aria-label","Giriş Yap / Kayıt Ol");
    }
  });
}
onAuthChange((session)=>{ updateAuthButtons(session); });

if (!window.WB_openAuth) {
  window.WB_openAuth = () => { injectAuthModalsIfMissing(); openAuthFlow(); };
}

/* =========================================================
  Navbar accent + global auth button style force
========================================================= */
(function syncAccentFromProfileBtn(){
  const prof = document.querySelector(".right-section .profile");
  if (!prof) return;
  const bg = getComputedStyle(prof).backgroundColor || "";
  if (bg) {
    document.documentElement.style.setProperty("--accent", bg);
    document.documentElement.style.setProperty("--accent-dyn", bg);
  }
  // Auth butonlarını accent'e zorlayalım (CSS ile de var, bu garanti)
  if (!document.getElementById("authAccentCSS")){
    const st = document.createElement("style");
    st.id = "authAccentCSS";
    st.textContent = `
      .auth-btn{
        background: var(--accent) !important;
        color: var(--accent-ink) !important;
        box-shadow: 0 6px 18px color-mix(in oklab, var(--accent) 35%, transparent) !important;
        border: none !important;
      }
    `;
    document.head.appendChild(st);
  }
})();

function bumpDobZ(tries = 8) {
  const el = document.querySelector(".dobp-overlay");
  if (el) {
    el.style.zIndex = String(Z.dob);
    return;
  }
  if (tries > 0) {
    setTimeout(() => bumpDobZ(tries - 1), 120);
  }
}

/* Istanbul now */
function nowInIstanbul() {
  const parts = new Intl.DateTimeFormat("tr-TR", {
    timeZone: "Europe/Istanbul", hour: "2-digit", minute: "2-digit", weekday: "long", hour12: false
  }).formatToParts(new Date());
  const get = t => parts.find(p => p.type === t)?.value;
  const hh = Number(get("hour") || 0), mm = Number(get("minute") || 0);
  const wname = (get("weekday") || "").toLowerCase();
  const dayIdx = TR_DAY_IDX[wname];
  return { minutes: hh * 60 + mm, dayIdx: Number.isInteger(dayIdx) ? dayIdx : (new Date()).getDay() };
}

function normalizeWorkingHours(src) {
  if (!src || typeof src !== "object") return null;
  const out = {};
  TR_DAYS.forEach((_, idx) => {
    const raw = src[idx] ?? src[TR_DAYS[idx]] ?? null;
    if (!raw) { out[idx] = { open:false, slots:[] }; return; }
    if (Array.isArray(raw)) {
      const slots = raw.map(r => ({from:r?.from, to:r?.to})).filter(r => r.from && r.to);
      out[idx] = { open: slots.length>0, slots }; return;
    }
    if (raw.open === false) { out[idx] = { open:false, slots:[] }; return; }
    if (Array.isArray(raw.slots)) {
      const slots = raw.slots.map(r => ({from:r?.from, to:r?.to})).filter(r => r.from && r.to);
      out[idx] = { open: slots.length>0, slots }; return;
    }
    if (raw.from && raw.to) { out[idx] = { open:true, slots:[{from:raw.from, to:raw.to}] }; return; }
    out[idx] = { open:false, slots:[] };
  });
  return out;
}
const hhmmToMin = (s="00:00") => { const [h,m]=String(s).split(":").map(n=>Number(n)||0); return h*60+m; };

function isOpenAt(hours, dateISO, timeHHMM){
  const norm = normalizeWorkingHours(hours);
  if (!norm) return false;
  if (!dateISO || !timeHHMM) return true;
  const d = new Date(dateISO); if (isNaN(d)) return true;
  const day = norm[d.getDay()];
  if (!day?.open || !day.slots?.length) return false;
  const q = hhmmToMin(timeHHMM);
  return day.slots.some(s => q >= hhmmToMin(s.from) && q < hhmmToMin(s.to));
}
function isOpenNow(hours) {
  const norm = normalizeWorkingHours(hours);
  if (!norm) return { open:false, today:"" };
  const { minutes:cur, dayIdx } = nowInIstanbul();
  const day = norm[dayIdx];
  if (!day?.open || !day.slots?.length) return { open:false, today:"Kapalı" };
  const open = day.slots.some(s => cur >= hhmmToMin(s.from) && cur < hhmmToMin(s.to));
  return { open, today: day.slots.map(s=>`${s.from} - ${s.to}`).join(", ") || "—" };
}

function minPrice(services = []) {
  if (!Array.isArray(services) || services.length === 0) return null;
  let m = Infinity;
  for (const s of services) {
    const p = Number(s?.price ?? s?.minPrice);
    if (!Number.isNaN(p)) m = Math.min(m, p);
  }
  return Number.isFinite(m) ? m : null;
}
function addressLine(loc = {}) {
  const a = [];
  if (loc.neighborhood) a.push(loc.neighborhood);
  if (loc.district) a.push(loc.district);
  if (loc.province || loc.city) a.push(loc.province || loc.city);
  return a.join(" • ");
}

/* ---------- Müsaitlik badge ---------- */
function todayIstanbul() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(new Date());
}

function computeAvailStatus(bookedMap, workingHours) {
  const norm = normalizeWorkingHours(workingHours);
  if (!norm) return null;
  const { minutes: nowMin, dayIdx } = nowInIstanbul();
  const day = norm[dayIdx];
  if (!day?.open || !day.slots?.length) return null;
  let total = 0, booked = 0, freeIn2h = false;
  for (const slot of day.slots) {
    const from = hhmmToMin(slot.from);
    const to   = hhmmToMin(slot.to);
    for (let cur = from; cur + 15 <= to; cur += 15) {
      total++;
      const h = Math.floor(cur / 60), m = cur % 60;
      if (bookedMap[h]?.includes(m)) { booked++; }
      else if (cur >= nowMin && cur < nowMin + 120) { freeIn2h = true; }
    }
  }
  if (total === 0) return null;
  if (booked >= total) return "dolu";
  if (freeIn2h)        return "hemen";
  return "musait";
}

function renderAvailChip(badge, status) {
  const cfg = { musait: "Bugün müsait", dolu: "Bugün dolu", hemen: "⚡ Hemen randevu" };
  const label = cfg[status];
  badge.innerHTML = label
    ? `<span class="avail-chip ${status}" aria-label="${label}">${label}</span>`
    : "";
}

const AVAIL_TTL = 5 * 60 * 1000;

async function loadAvailBadge(bizId, wrap) {
  const badge = wrap.querySelector(".wb-avail-badge");
  if (!badge) return;
  const today = todayIstanbul();
  const key   = `wb_av_${bizId}_${today}`;
  try {
    const raw = localStorage.getItem(key);
    if (raw) {
      const { ts, status } = JSON.parse(raw);
      if (Date.now() - ts < AVAIL_TTL) { renderAvailChip(badge, status); return; }
    }
  } catch {}
  try {
    const data = await api.get(`/api/appointments/booked-map.php?businessId=${encodeURIComponent(bizId)}&date=${today}`);
    if (!data?.ok) return;
    const salon  = ALL_SALONS.find(s => String(s.businessId ?? s.bid ?? s.uid ?? s.id) === String(bizId));
    const status = computeAvailStatus(data.data?.map ?? {}, salon?.workingHours);
    try { localStorage.setItem(key, JSON.stringify({ ts: Date.now(), status })); } catch {}
    renderAvailChip(badge, status);
  } catch {}
}

let _availObs   = null;
let _availCount = 0;

function initAvailObserver() {
  if (_availObs) _availObs.disconnect();
  _availCount = 0;
  _availObs = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting || _availCount >= 10) continue;
      const wrap  = entry.target;
      const bizId = wrap.dataset.bizId;
      if (!bizId) continue;
      _availObs.unobserve(wrap);
      _availCount++;
      loadAvailBadge(bizId, wrap);
    }
  }, { rootMargin: "300px 0px" });
  grid?.querySelectorAll(".card-wrap[data-biz-id]").forEach(w => _availObs.observe(w));
}

/* ---------- Konum bazlı arama ---------- */
let _geoCache = null; // session cache

function showToast(msg, type = "", duration = 3200) {
  let t = document.getElementById("toast");
  if (!t) {
    t = document.createElement("div");
    t.id = "toast"; t.className = "toast";
    t.setAttribute("role", "status"); t.setAttribute("aria-live", "polite");
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.className = `toast${type ? " " + type : ""}`;
  t.classList.add("show");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => t.classList.remove("show"), duration);
}

function setGeoLoading(loading) {
  const btns = [document.getElementById("btnGeoLoc"), document.getElementById("btnGeoLocMob")];
  const qLocMob = document.getElementById("qLocMobile");
  for (const b of btns) if (b) { b.disabled = loading; b.classList.toggle("loading", loading); }
  if (qLoc)    { qLoc.disabled    = loading; if (loading) qLoc.value    = "Konum alınıyor…"; }
  if (qLocMob) { qLocMob.disabled = loading; if (loading) qLocMob.value = "Konum alınıyor…"; }
}

function resetGeoInputs() {
  if (qLoc)    { qLoc.value = ""; qLoc.disabled = false; }
  const qLocMob = document.getElementById("qLocMobile");
  if (qLocMob) { qLocMob.value = ""; qLocMob.disabled = false; }
  setGeoLoading(false);
}

/* select-combo aria-busy kalkana kadar bekle */
function waitForSelectLoad(select, timeout = 6000) {
  return new Promise((resolve) => {
    if (!select?.hasAttribute("aria-busy")) { resolve(); return; }
    const obs = new MutationObserver(() => {
      if (!select.hasAttribute("aria-busy")) { obs.disconnect(); resolve(); }
    });
    obs.observe(select, { attributes: true, attributeFilter: ["aria-busy"] });
    setTimeout(() => { obs.disconnect(); resolve(); }, timeout);
  });
}

/* Option'larda "Mahallesi" normalize eşleşme — Nominatim farkını kapatar */
function bestSelectMatch(select, value) {
  if (!value || !select) return "";
  const trM  = {"Ç":"c","ç":"c","Ğ":"g","ğ":"g","İ":"i","I":"i","ı":"i","Ö":"o","ö":"o","Ş":"s","ş":"s","Ü":"u","ü":"u"};
  const norm = (s) => String(s||"").replace(/[ÇçĞİIıÖöŞşÜü]/g, m=>trM[m]||m).toLowerCase().trim();
  const strip = (s) => norm(s).replace(/\b(mahallesi|mah\.?|mh\.?)\b/g,"").replace(/\s+/g," ").trim();
  const A = strip(value), nA = norm(value);
  const opts = Array.from(select.options).map(o => o.value).filter(Boolean);
  return opts.find(o => strip(o) === A)
    || opts.find(o => strip(o).includes(A) || A.includes(strip(o)))
    || opts.find(o => norm(o).includes(nA) || nA.includes(norm(o)))
    || "";
}

async function applyGeoResult({ il, ilce, mahalle = "" }) {
  resetGeoInputs();
  if (!fProvince) return;
  IS_FUZZY_LOC = false;
  if (qLoc) qLoc.value = "";

  // 1) İl — async listener ilçe listesini API'den çeker
  fProvince.value = il;
  fProvince.dispatchEvent(new Event("change"));
  await new Promise(r => setTimeout(r, 0)); // listener'ın aria-busy set etmesine izin ver
  await waitForSelectLoad(fDistrict);

  // 2) İlçe — normalize eşleşme, async listener mahalleleri çeker
  if (fDistrict && ilce) {
    fDistrict.value = bestSelectMatch(fDistrict, ilce) || ilce;
    fDistrict.dispatchEvent(new Event("change"));
    await new Promise(r => setTimeout(r, 0));
    await waitForSelectLoad(fNeighborhood);
  }

  // 3) Mahalle — "Bulgurlu Mahallesi" → "Bulgurlu" normalize eşleşme
  if (fNeighborhood && mahalle) {
    const m = bestSelectMatch(fNeighborhood, mahalle);
    if (m) { fNeighborhood.value = m; fNeighborhood.dispatchEvent(new Event("change")); }
  }

  updateURLFromUI();
  updateFiltersButtonLabel();
  fetchSalons();
}

async function useMyLocation() {
  if (location.protocol !== "https:" && location.hostname !== "localhost") return;
  if (_geoCache) { applyGeoResult(_geoCache); return; }
  if (!navigator.geolocation) { showToast("Tarayıcınız konum desteklemiyor", "error"); return; }
  setGeoLoading(true);
  navigator.geolocation.getCurrentPosition(
    async (pos) => {
      try {
        const { latitude: lat, longitude: lon } = pos.coords;
        const res = await fetch(
          `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&accept-language=tr`,
          { headers: { "User-Agent": "Webey/1.0 (webey.com.tr)", "Accept": "application/json" } }
        );
        const data = await res.json();
        const addr = data.address || {};
        const il      = addr.province    || addr.city         || addr.state        || "";
        const ilce    = addr.district    || addr.county       || addr.town         || addr.municipality || "";
        const mahalle = addr.suburb      || addr.neighbourhood|| addr.quarter      || addr.village      || "";
        _geoCache = { il, ilce, mahalle };
        applyGeoResult(_geoCache);
      } catch {
        resetGeoInputs();
        showToast("Konum çözümlenemedi, şehir seçin", "error");
      }
    },
    (err) => {
      resetGeoInputs();
      if (err.code === 1) showToast("Konum izni verilmedi, şehir seçin", "error");
    },
    { timeout: 10000, maximumAge: 60000 }
  );
}

function initGeoButtons() {
  const isSecure = location.protocol === "https:" || location.hostname === "localhost";
  const btnGeoLoc    = document.getElementById("btnGeoLoc");
  const btnGeoLocMob = document.getElementById("btnGeoLocMob");
  if (!isSecure) {
    if (btnGeoLoc)    btnGeoLoc.style.display    = "none";
    if (btnGeoLocMob) btnGeoLocMob.style.display = "none";
    return;
  }
  btnGeoLoc?.addEventListener("click", useMyLocation);
  btnGeoLocMob?.addEventListener("click", useMyLocation);
}

const toMs = (u) => {
  if (!u) return 0;
  if (typeof u.toMillis === "function") return u.toMillis();
  if (u.seconds != null) return u.seconds * 1000 + (u.nanoseconds || 0) / 1e6;
  const t = new Date(u).getTime();
  return Number.isFinite(t) ? t : 0;
};

/* --- TR normalize --- */
const trMap = { "Ç":"c","ç":"c","Ğ":"g","ğ":"g","İ":"i","I":"i","ı":"i","Ö":"o","ö":"o","Ş":"s","ş":"s","Ü":"u","ü":"u" };
const trNorm = (s="") => s.replace(/[ÇçĞİIıÖöŞşÜü]/g, m=>trMap[m]||m).toLowerCase().trim();
const stripMah = (s="") => trNorm(s).replace(/\b(mahallesi|mah\.?|mh\.?)\b/g, "").replace(/\s+/g," ").trim();
const eq = (a,b) => trNorm(a) === trNorm(b);
const eqMah = (a,b) => { const A = stripMah(a), B = stripMah(b); return A === B || A.includes(B) || B.includes(A); };

/* ---------- UI refs ---------- */
const grid = $("#salonGrid");
const meta = $("#resultMeta");
const empty = $("#emptyState");

const fProvince = $("#fProvince");
const fDistrict = $("#fDistrict");
const fNeighborhood = $("#fNeighborhood");
let btnMyAddress = $("#btnMyAddress");

const qSvc = $("#qSvc");
const qLoc = $("#qLoc");
/* “Ne zaman?” artık buton olabilir; #qWhen id'si korunuyor */
const qWhen = $("#qWhen");

const dateOverlay = $("#sb-date-overlay");

/* ---- When görünüm yardımcıları ---- */
function setWhenDisplay(text) {
  if (!qWhen) return;
  const span = qWhen.querySelector?.(".when-text");
  if (span) {
    span.textContent = text || "Ne zaman?";
  } else if ("value" in qWhen) {
    qWhen.value = text || "";
  } else {
    qWhen.textContent = text || "Ne zaman?";
  }
  qWhen.classList.toggle("filled", !!text);
}
function getWhenDisplay() {
  if (!qWhen) return "";
  if (qWhen.querySelector?.(".when-text")) return qWhen.querySelector(".when-text").textContent || "";
  if ("value" in qWhen) return qWhen.value || "";
  return qWhen.textContent || "";
}

/* ---------- URL/konum/saat/hizmet ---------- */
let params = new URLSearchParams(location.search);
function readPlaceParams(p = params) {
  let il = p.get("il") || "";
  let ilce = p.get("ilce") || "";
  let mahalle = p.get("mahalle") || "";
  if (!ilce && !mahalle && /•/.test(il)) {
    const parts = il.split("•").map(t => t.trim()).filter(Boolean);
    il = parts[0] || il; ilce = parts[1] || ""; mahalle = parts[2] || "";
  }
  return { il, ilce, mahalle };
}
const PLACE0 = readPlaceParams();

// Sadece label amaçlı, filtreyi zorlamıyor
const DEFAULT_PROVINCE = "İstanbul";

let IS_FUZZY_LOC = !!(params.get("loc") || "").trim();
let DATE_STATE = params.get("date") || "";
let TIME_STATE = (params.get("time") || "").split(",").filter(Boolean);
let SVC_STATE  = (params.get("svc")  || "").split(",").filter(Boolean); // seçili hizmetler

const initState = {
  q: params.get("q") || "",
  date: DATE_STATE,
  time: TIME_STATE,
  svc:  SVC_STATE,
  place: PLACE0,
  locFree: params.get("loc") || ""
};
if (qSvc) qSvc.value = initState.q;
// Konum text'i sadece URL'den gelen il/ilçe/mahalle ile doldurulur (varsayılan il yok)
if (qLoc) qLoc.value = initState.locFree || [PLACE0.il, PLACE0.ilce, PLACE0.mahalle].filter(Boolean).join(" • ");
if (qWhen && (initState.date || initState.time.length)) {
  try{
    const d = initState.date ? new Date(initState.date) : null;
    const dd = d ? d.toLocaleDateString("tr-TR", { day:"2-digit", month:"long", year:"numeric" }) : "";
    setWhenDisplay([dd, initState.time.join(", ")].filter(Boolean).join(" • "));
  }catch{}
}

/* =========================================================
  TÜM TÜRKİYE İL / İLÇE / MAHALLE (select-combo.js)
========================================================= */

async function prepareFilters() {
  if (!fProvince || !fDistrict || !fNeighborhood) return;

  try {
    const { attachTRLocationCombo } = await import("./components/select-combo.js");
    await attachTRLocationCombo({
      citySelect:       fProvince,
      districtSelect:   fDistrict,
      neighborhoodSelect: fNeighborhood
    });
  } catch (e) {
    console.warn("[kuafor] select-combo yüklenemedi, mevcut seçeneklerle devam:", e);
  }

  // URL'den gelen başlangıç konumu UI'ya yansıt
  const il  = PLACE0.il   || "";
  const ilce= PLACE0.ilce || "";
  const mah = PLACE0.mahalle || "";

  if (il) {
    fProvince.value = il;
    fProvince.dispatchEvent(new Event("change"));
  }
  if (ilce) {
    setTimeout(() => {
      fDistrict.value = ilce;
      fDistrict.dispatchEvent(new Event("change"));
      if (mah) {
        setTimeout(() => {
          fNeighborhood.value = mah;
        }, 60);
      }
    }, 60);
  }
}

/* ---------- Kullanıcının kayıtlı adresi ---------- */
let USER_ADDRESS = null;
async function resolveUserAddress() {
  try {
    const session = getSession();
    if (!session) return null;
    const res = await api.get("/api/user/me.php");
    if (!res.ok || !res.data) return null;
    const il = res.data.city || "";
    const ilce = res.data.district || "";
    const mahalle = res.data.neighborhood || "";
    if (!il && !ilce && !mahalle) return null;
    return { il, ilce, mahalle };
  } catch (e) {
    console.warn("[kuafor] kullanıcı adresi okunamadı:", e);
    return null;
  }
}

function injectMyAddressQuickAction(){
  const wrap = $(".filters");
  if (!wrap) return;
  btnMyAddress = $("#btnMyAddress") || null;
  if (!btnMyAddress) {
    const btn = document.createElement("button");
    btn.id = "btnMyAddress";
    btn.type = "button";
    btn.className = "btn-outline";
    btn.textContent = "Kayıtlı adresim";
    btn.setAttribute("aria-label","Kayıtlı adresimi uygula");
    wrap.insertBefore(btn, wrap.firstChild);
    btnMyAddress = btn;
  }
  wireMyAddressButton(btnMyAddress);
}

function wireMyAddressButton(btn){
  if (!btn || btn.dataset.bound === "1") return;
  btn.dataset.bound = "1";

  btn.addEventListener("click", async () => {
    USER_ADDRESS = USER_ADDRESS || await resolveUserAddress();
    if (!USER_ADDRESS) {
      window.WB_openAuth?.();
      return;
    }

    if (fProvince) {
      fProvince.value = USER_ADDRESS.il || "";
      fProvince.dispatchEvent(new Event("change"));
    }
    setTimeout(() => {
      if (fDistrict) {
        fDistrict.value = USER_ADDRESS.ilce || "";
        fDistrict.dispatchEvent(new Event("change"));
      }
      setTimeout(() => {
        if (fNeighborhood) fNeighborhood.value = USER_ADDRESS.mahalle || "";
      }, 40);
    }, 40);

    if (qLoc) qLoc.value = "";
    IS_FUZZY_LOC = false;

    updateURLFromUI();
    updateFiltersButtonLabel();
    fetchSalons();
  });
}

/* ---------- URL güncelle ---------- */
function updateURLFromUI() {
  const p = new URLSearchParams(location.search);

  const qVal   = (qSvc?.value || "").trim();
  const locTxt = (qLoc?.value || "").trim();

  const il   = (fProvince?.value || "").trim();
  const ilce = (fDistrict?.value || "").trim();
  const mah  = (fNeighborhood?.value || "").trim();

  if (qVal) p.set("q", qVal); else p.delete("q");

  if (il) p.set("il", il); else p.delete("il");
  if (ilce) p.set("ilce", ilce); else p.delete("ilce");
  if (mah) p.set("mahalle", mah); else p.delete("mahalle");

  const structuredLabel = [il, ilce, mah].filter(Boolean).join(" • ");
  if (locTxt && trNorm(locTxt) !== trNorm(structuredLabel)) { p.set("loc", locTxt); IS_FUZZY_LOC = true; }
  else { p.delete("loc"); IS_FUZZY_LOC = false; }

  if (DATE_STATE) p.set("date", DATE_STATE); else p.delete("date");
  if (TIME_STATE.length) p.set("time", TIME_STATE.join(",")); else p.delete("time");
  if (SVC_STATE.length)  p.set("svc",  SVC_STATE.join(","));  else p.delete("svc");

  const qs = p.toString();
  history.replaceState({}, "", qs ? `${location.pathname}?${qs}` : location.pathname);
  params = new URLSearchParams(location.search);
}

/* ---------- Kart şablonu ---------- */
function cardTemplate(row) {
  const uid = row.uid || row.id || "";
  const slug = row.slug || "";
  const name = row.name || row.business?.name || slug || "İşletme";

  const galleryEntries = buildGalleryEntries(row);
  const gallery = galleryEntries.map(entry => entry.src);

  const price = minPrice(row.services);
  // API'den gelen min_price varsa onu kullan
  const displayPrice = price ?? row.min_price ?? row.minPrice ?? null;

  const loc = addressLine(row.businessLocation || {});
  const openInfo = isOpenNow(row.workingHours);
  const openBadge = openInfo.open ? `<span class="badge ok" aria-label="Şu an açık">Açık</span>` : `<span class="badge off" aria-label="Şu an kapalı">Kapalı</span>`;
  const todayText = openInfo.today || "—";
  const bizId = row.businessId || row.bid || uid || row.id || "";
  const href = `profile.html?id=${encodeURIComponent(bizId)}${slug ? `&n=${encodeURIComponent(slug)}` : ""}`;

  // Puan satırı

  // Carousel slide'ları
  const slidesHtml = galleryEntries.map((entry, i) =>
    `<img class="wb-slide" src="${i === 0 ? entry.src : ''}" data-src="${entry.src}" data-fallback="${entry.fallback}" alt="${escapeHTML(name)} ${i+1}" loading="${i === 0 ? 'eager' : 'lazy'}" decoding="async" style="${i === 0 ? 'opacity:1' : 'opacity:0;position:absolute;inset:0'}" onerror="if(this.dataset.fallback&&this.src!==this.dataset.fallback){this.src=this.dataset.fallback;return;}this.onerror=null;this.src='img/hero-cover.webp';">`
  ).join('');

  // Carousel dots (sadece 2+ resim varsa)
  const dotsHtml = gallery.length > 1
    ? `<div class="wb-dots" aria-hidden="true">${gallery.map((_,i) => `<span class="wb-dot${i===0?' wb-dot--active':''}"></span>`).join('')}</div>`
    : '';

  // Fiyat metni
  const priceHtml = displayPrice != null
    ? `<div class="price"><span class="price-amount">${TL(displayPrice)}</span><span class="price-label">'dan başlayan fiyatlar</span></div>`
    : `<div class="price price--ask">Fiyat sorunuz</div>`;

  return `
    <div class="card-wrap" data-biz-id="${bizId}" data-gallery='${JSON.stringify(gallery)}'>
      <a class="card" href="${href}" aria-label="${escapeHTML(name)} profiline git">
        <div class="cover wb-carousel" aria-hidden="true">
          <div class="wb-slides-track" style="position:relative;width:100%;height:100%;">
            ${slidesHtml}
          </div>
          ${dotsHtml}
          <div class="wb-avail-badge" aria-hidden="true"></div>
        </div>
        <div class="body">
          <div class="row1">
            <h3 class="ttl">${escapeHTML(name)}</h3>
            ${openBadge}
          </div>
          <div class="muted small">${escapeHTML(loc || "—")}</div>
          <div class="muted tiny">Bugün: ${escapeHTML(todayText)}</div>
          <div class="row2">
            ${priceHtml}
            <div class="cta" style="background:var(--accent);color:var(--accent-ink)" aria-hidden="true">Randevu al</div>
          </div>
        </div>
      </a>
    </div>
  `;
}

/* ---------- Data ---------- */
let ALL_SALONS = [];
let FETCH_SEQ = 0;

/* Hizmet listesi (distinct, alfabetik — TR normalize ile) */
function distinctServices(){
  const seen = new Map(); // key: trNorm(name) -> original (ilk görüleni tut)
  for (const x of ALL_SALONS){
    const arr = Array.isArray(x.services) ? x.services : [];
    for (const s of arr){
      const nm = (s?.name || s?.title || "").trim();
      if (!nm) continue;
      const k = trNorm(nm);
      if (!seen.has(k)) seen.set(k, nm);
    }
  }
  return Array.from(seen.values()).sort((a,b)=> a.localeCompare(b, "tr"));
}

function showSkeleton(n = 8) {
  if (!grid) return;
  grid.setAttribute("aria-busy","true");
  grid.innerHTML = "";
  const tpl = $("#skeletonTpl");
  if (tpl?.content) {
    for (let i=0;i<n;i++) grid.appendChild(tpl.content.cloneNode(true));
  } else {
    for (let i=0;i<n;i++) {
      const div = document.createElement("div");
      div.className = "card skel";
      div.innerHTML = `<div class="img"></div><div class="lines"><div class="l w2"></div><div class="l w1"></div><div class="l w3"></div></div>`;
      grid.appendChild(div);
    }
  }
}
function clearSkeleton() {
  if (!grid) return;
  grid.querySelectorAll(".skel").forEach(n => n.remove());
  grid.removeAttribute("aria-busy");
}

/* Parametreye göre Firestore'dan çek (race-safe) */
async function fetchSalons() {
  if (!grid) return;
  showSkeleton();
  const mySeq = ++FETCH_SEQ;
  try {
    const cur = new URLSearchParams(location.search);
    let il   = cur.get("il")   || "";
    let ilce = cur.get("ilce") || "";
    let mah  = cur.get("mahalle") || "";
    if (!ilce && !mah && /•/.test(il)) {
      const parts = il.split("•").map(t => t.trim()).filter(Boolean);
      il   = parts[0] || il; ilce = parts[1] || ""; mah  = parts[2] || "";
    }

    const serverQuery = (qSvc?.value || "").trim();
    const rows = await loadListingBusinesses({
      city: il,
      district: ilce,
      neighborhood: mah,
      q: serverQuery,
      pageSize: 60,
      maxPages: 6,
      maxItems: 300,
    });

    if (mySeq !== FETCH_SEQ) return;
    ALL_SALONS = rows;

    // Filtre modali içindeki hizmet listesi (varsa) güncellensin
    refreshOverlayServices();

    renderList();
  } catch (e) {
    console.error("[kuafor] fetch error:", e);
    if (grid) grid.innerHTML = "";
    if (empty) empty.style.display = "block";
    if (meta) meta.textContent = "Yüklenemedi";
  } finally {
    if (mySeq === FETCH_SEQ) clearSkeleton();
  }
}

/* ---------- Liste/filtreleme ---------- */
function placeScopeLabel(p){
  if (p.mahalle) return `${p.mahalle}, ${p.ilce} • ${p.il}`;
  if (p.ilce)    return `${p.ilce} • ${p.il || ""}`.trim();
  return p.il || "";
}

function renderEmptySuggestions(placeURL){
  if (!empty) return;
  const sugg = [];
  if (USER_ADDRESS) sugg.push({ key:"myaddr", label:"Kayıtlı adresim" });
  if (placeURL.mahalle && placeURL.ilce) sugg.push({ key:"district", label:`Tüm ${placeURL.ilce}` });
  if (placeURL.ilce) sugg.push({ key:"province", label:`Tüm ${placeURL.il || DEFAULT_PROVINCE}` });
  if (!sugg.length) sugg.push({ key:"clear", label:"Filtreleri temizle" });

  const btns = sugg.map(s => `<button type="button" class="sugg-btn" data-sugg="${s.key}">${escapeHTML(s.label)}</button>`).join("");

  let shareCardHTML = "";
  if (placeURL.il) {
    const bolge = placeURL.mahalle || placeURL.ilce || "";
    const il    = placeURL.il;
    const type  = bolge ? "1" : "2";
    const title = bolge
      ? `${escapeHTML(bolge)} bölgesinde henüz kuaför yok`
      : `${escapeHTML(il)} ilinde henüz kuaför yok`;
    const sub = bolge
      ? "Bu bölgede gittiğin bir kuaför var mı? Ona bu linki gönder, bölgende de Webey'i büyütelim 🙌"
      : "Gittiğin bir kuaför biliyor musun? Ona bu linki gönder, birlikte büyüyelim 🙌";
    const shareText = type === "1"
      ? `Merhaba! Webey'de ${bolge}, ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`
      : `Merhaba! Webey'de ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`;
    const waUrl = `https://wa.me/?text=${encodeURIComponent(shareText)}`;
    shareCardHTML = `
<div class="wb-share-card">
  <p class="wb-share-title">${title}</p>
  <p class="wb-share-sub">${sub}</p>
  <button type="button" class="wb-share-btn" data-action="wb-share"
    data-il="${escapeHTML(il)}" data-bolge="${escapeHTML(bolge)}" data-type="${type}">
    💌 Kuaföre Link Gönder
  </button>
  <div class="wb-share-fallback">
    <a class="wb-share-wa" href="${escapeHTML(waUrl)}" target="_blank" rel="noopener noreferrer">
      <i class="fab fa-whatsapp" aria-hidden="true"></i> WhatsApp
    </a>
    <button type="button" class="wb-copy-btn" data-action="wb-copy"
      data-il="${escapeHTML(il)}" data-bolge="${escapeHTML(bolge)}" data-type="${type}">🔗 Linki Kopyala</button>
  </div>
</div>`;
  }

  empty.innerHTML = `Hiç sonuç yok. Filtreleri değiştirmeyi deneyin.<div class="sugg-wrap">${btns}</div>${shareCardHTML}`;
  empty.style.display = "block";
}

empty?.addEventListener("click", async (e)=>{
  // Kuaför davet kartı — paylaş
  const shareBtn = e.target.closest("[data-action='wb-share']");
  if (shareBtn) {
    const il    = shareBtn.dataset.il    || "";
    const bolge = shareBtn.dataset.bolge || "";
    const type  = shareBtn.dataset.type;
    const shareText = type === "1"
      ? `Merhaba! Webey'de ${bolge}, ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`
      : `Merhaba! Webey'de ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`;
    if (navigator.share) {
      try { await navigator.share({ text: shareText }); } catch {}
    } else {
      const fallback = shareBtn.closest(".wb-share-card")?.querySelector(".wb-share-fallback");
      if (fallback) fallback.classList.toggle("open");
    }
    return;
  }

  // Kuaför davet kartı — kopyala
  const copyBtn = e.target.closest("[data-action='wb-copy']");
  if (copyBtn) {
    const il    = copyBtn.dataset.il    || "";
    const bolge = copyBtn.dataset.bolge || "";
    const type  = copyBtn.dataset.type;
    const text = type === "1"
      ? `Merhaba! Webey'de ${bolge}, ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`
      : `Merhaba! Webey'de ${il} için kuaför arıyordum ama seni bulamadım. Buradan ücretsiz kaydolabilirsin, müşteri bulmana yardımcı olur 👇\nhttps://webey.com.tr`;
    try {
      await navigator.clipboard.writeText(text);
      const orig = copyBtn.innerHTML;
      copyBtn.textContent = "Kopyalandı ✓";
      setTimeout(() => { copyBtn.innerHTML = orig; }, 2500);
    } catch {}
    return;
  }

  const btn = e.target.closest("button[data-sugg]");
  if (!btn) return;
  const key = btn.getAttribute("data-sugg");

  if (qLoc) qLoc.value = "";
  IS_FUZZY_LOC = false;

  if (key === "myaddr") {
    USER_ADDRESS = USER_ADDRESS || await resolveUserAddress();
    if (!USER_ADDRESS) { window.WB_openAuth?.(); return; }

    if (fProvince) {
      fProvince.value = USER_ADDRESS.il || "";
      fProvince.dispatchEvent(new Event("change"));
    }
    setTimeout(() => {
      if (fDistrict) {
        fDistrict.value = USER_ADDRESS.ilce || "";
        fDistrict.dispatchEvent(new Event("change"));
      }
      setTimeout(() => {
        if (fNeighborhood) fNeighborhood.value = USER_ADDRESS.mahalle || "";
      }, 40);
    }, 40);

    updateURLFromUI();
    updateFiltersButtonLabel();
    fetchSalons();
    return;
  }

  if (key === "district") {
    // İlçe bazına genişlet → mahalleyi temizle
    if (fNeighborhood) fNeighborhood.value = "";
    updateURLFromUI();
    updateFiltersButtonLabel();
    renderList();
    fetchSalons();
  } else if (key === "province") {
    // İle genişlet → ilçe + mahalleyi temizle
    if (fDistrict) fDistrict.value = "";
    if (fNeighborhood) fNeighborhood.value = "";
    updateURLFromUI();
    updateFiltersButtonLabel();
    renderList();
    fetchSalons();
  } else if (key === "clear") {
    clearFilters();
    fetchSalons();
  }
});

function renderList() {
  meta?.setAttribute("aria-live", "polite");
  if (!grid) return;

  const cur = new URLSearchParams(location.search);
  let placeURL = (() => {
    let il = cur.get("il") || "";
    let ilce = cur.get("ilce") || "";
    let mahalle = cur.get("mahalle") || "";
    if (!ilce && !mahalle && /•/.test(il)) {
      const parts = il.split("•").map(t => t.trim()).filter(Boolean);
      il = parts[0] || il; ilce = parts[1] || ""; mahalle = parts[2] || "";
    }
    return { il, ilce, mahalle };
  })();

  const svcQuery = (qSvc?.value || "").trim().toLowerCase();
  const locQuery = (qLoc?.value || "").trim().toLowerCase();

  let list = ALL_SALONS.slice();

  // Konum filtresi
  list = list.filter(x => {
    const L = x.businessLocation || {};
    const province = L.province || L.city || "";
    const district = L.district || "";
    const neighborhood = L.neighborhood || "";

    if (placeURL.mahalle) {
      const okMah = eqMah(neighborhood, placeURL.mahalle);
      const okIlce = !placeURL.ilce || eq(district, placeURL.ilce);
      const okIl   = !placeURL.il   || eq(province, placeURL.il);
      return okMah && okIlce && okIl;
    }
    if (placeURL.ilce) {
      return eq(district, placeURL.ilce) && (!placeURL.il || eq(province, placeURL.il));
    }
    if (placeURL.il) {
      return eq(province, placeURL.il);
    }
    return true;
  });

  // Serbest hizmet/isim araması
  if (svcQuery) {
    list = list.filter(x => {
      const nm = (x.name || x.business?.name || x.slug || "").toLowerCase();
      const hasName = nm.includes(svcQuery);
      const hasSvc = Array.isArray(x.services)
        ? x.services.some(s => (s?.name || "").toLowerCase().includes(svcQuery))
        : false;
      return hasName || hasSvc;
    });
  }

  // Fuzzy konum araması
  if (IS_FUZZY_LOC && locQuery) {
    list = list.filter(x => {
      const loc = `${x.businessLocation?.neighborhood || ""} ${x.businessLocation?.district || ""} ${(x.businessLocation?.province || x.businessLocation?.city || "")}`.toLowerCase();
      return loc.includes(locQuery);
    });
  }

  // Seçili HİZMETLER (OR mantığı: seçilenlerden en az biri)
  if (SVC_STATE.length){
    const sels = SVC_STATE.map(s=>trNorm(s));
    list = list.filter(x => {
      const arr = Array.isArray(x.services) ? x.services : [];
      const names = arr.map(s => trNorm(s?.name || s?.title || ""));
      return sels.some(sel => names.includes(sel));
    });
  }

  // Tarih + saat (her seçili saat için açık olmalı)
  if (DATE_STATE && TIME_STATE.length){
    list = list.filter(x => TIME_STATE.every(t => isOpenAt(x.workingHours, DATE_STATE, t)));
  }

  if (list.length) {
    grid.innerHTML = list.map(cardTemplate).join("");
    if (empty) empty.style.display = "none";
    initCarousels(grid);
    initAvailObserver();
  } else {
    grid.innerHTML = "";
    renderEmptySuggestions(placeURL);
  }

  const chips = [];
  const scope = placeScopeLabel(placeURL);
  if (scope) chips.push(scope);
  if (svcQuery) chips.push(`“${svcQuery}”`);
  if (SVC_STATE.length) chips.push(`${SVC_STATE.length} hizmet`);
  if (DATE_STATE) {
    try{
      const d = new Date(DATE_STATE);
      const dd = d.toLocaleDateString("tr-TR",{ day:"2-digit", month:"long", year:"numeric" });
      chips.push(TIME_STATE.length ? `${dd} • ${TIME_STATE.join(", ")}` : dd);
    }catch{}
  }
  const ctx = chips.length ? chips.join(" • ") + " için " : "";
  if (meta) meta.textContent = list.length ? `${ctx}${list.length} işletme bulundu` : (ctx ? `${ctx}sonuç yok` : "Sonuç yok");

  updateFiltersButtonLabel();
}

/* ---------- Filtreler tek butonda + geniş iletişim ---------- */
let btnFilters = null;
function ensureFiltersToggle(){
  const wrap = $(".filters");
  if (!wrap || btnFilters) return;

  [fProvince, fDistrict, fNeighborhood].forEach(el => { if (el) el.style.display = "none"; });

  btnFilters = document.createElement("button");
  btnFilters.type = "button";
  btnFilters.className = "btn-outline";
  btnFilters.id = "btnFilters";
  btnFilters.style.display = "inline-flex";
  btnFilters.style.alignItems = "center";
  btnFilters.style.gap = "8px";
  btnFilters.setAttribute("aria-haspopup","dialog");
  btnFilters.innerHTML = `<i class="fas fa-sliders-h" aria-hidden="true"></i><span>Filtreler</span>`;
  wrap.insertBefore(btnFilters, wrap.firstChild);

  btnFilters.addEventListener("click", openFilterOverlay);

  ensureFilterOverlay();
  updateFiltersButtonLabel();
}

function currentFilterParts(){
  const parts = [];
  const ilce = (fDistrict?.value || "").trim();
  const mah  = (fNeighborhood?.value || "").trim();
  if (mah) parts.push(mah);
  if (ilce) parts.push(ilce);
  return parts;
}

function updateFiltersButtonLabel(){
  if (!btnFilters) return;
  const span = btnFilters.querySelector("span");
  const parts = currentFilterParts();
  let label = parts.length ? parts.join(" • ") : "Filtreler";
  const extras = [];
  if (SVC_STATE.length) extras.push(`${SVC_STATE.length} hizmet`);
  if (DATE_STATE || TIME_STATE.length) extras.push("zaman");
  if (extras.length) label += ` — ${extras.join(", ")}`;
  span.textContent = label;
  btnFilters.dataset.active = (parts.length || extras.length) ? "1" : "0";
}

/* Overlay */
let filterOverlay = null;
let FO_TEMP = null; // {svc:[], date:'', time:[]}
function ensureFilterOverlay(){
  if (filterOverlay) return;
  filterOverlay = document.createElement("div");
  filterOverlay.id = "filterOverlay";
  filterOverlay.className = "filter-overlay"; // <— ARTIK filter-overlay
  filterOverlay.setAttribute("aria-hidden","true");
  filterOverlay.style.zIndex = Z.modal; // CSS !important ile de kilitleniyor
  filterOverlay.innerHTML = `
    <div class="time-box" role="dialog" aria-modal="true" aria-label="Filtreler">
      <button class="time-close" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
      <h2 class="modal-title-center" style="margin:4px 0 12px">Filtreler</h2>

      <div class="filter-fields" style="display:grid;gap:12px;margin-bottom:8px">
        <!-- KONUM -->
        <section>
          <div style="font-weight:800;margin-bottom:6px">Konum</div>
          <div style="display:grid;gap:10px">
            <label style="display:grid;gap:6px">
              <span style="font-weight:600">İl</span>
              <select id="foProvince"></select>
            </label>
            <label style="display:grid;gap:6px">
              <span style="font-weight:600">İlçe</span>
              <select id="foDistrict"></select>
            </label>
            <label style="display:grid;gap:6px">
              <span style="font-weight:600">Mahalle</span>
              <select id="foNeighborhood" disabled></select>
            </label>
          </div>
        </section>

        <!-- ZAMAN -->
        <section>
          <div style="font-weight:800;margin:6px 0">Zaman</div>
          <button
            type="button"
            id="foWhenBtn"
            class="when-btn"
            aria-label="Zaman seç"
            aria-haspopup="dialog"
            aria-controls="timeOverlay"
            style="min-height:40px;padding:8px 12px;border:1px solid var(--border);border-radius:12px;background:#fff;text-align:left"
          >Seçilmedi</button>
          <div class="form-hint" id="foWhenHint">Saat seçtiğinizde URL’ye de yansır.</div>
        </section>

        <!-- HİZMET -->
        <section>
          <div style="font-weight:800;margin:6px 0">Hizmetler</div>

          <div class="svc-head" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:6px">
            <input id="foSvcSearch" class="auth-input" type="text" placeholder="Hizmet ara (örn. Saç kesimi)" aria-label="Hizmet ara" style="flex:1;min-width:220px;max-width:360px">
            <div class="form-hint" aria-hidden="true">Yazdıkça süzülür</div>
          </div>

          <div id="foServices" class="svc-list" role="group" aria-label="Hizmetler"
               style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px"></div>
          <div class="form-hint">Birden çok hizmet seçebilirsiniz (OR mantığı).</div>
        </section>
      </div>

      <div class="time-actions" style="display:flex;gap:10px;align-items:center;justify-content:flex-end">
        <span style="flex:1"></span>
        <button id="foCancel" class="btn btn-danger">İptal</button>
        <button id="foClear" class="btn">Temizle</button>
        <button id="foApply" class="auth-btn" style="min-width:140px;background:var(--accent);color:var(--accent-ink);border:none;border-radius:12px">Uygula</button>
      </div>
    </div>
  `;
  document.body.appendChild(filterOverlay);

  // Kapatma
  filterOverlay.querySelector(".time-close")?.addEventListener("click", closeFilterOverlay);
  filterOverlay.addEventListener("click", e => { if (e.target === filterOverlay) closeFilterOverlay(); });
  $("#foCancel")?.addEventListener("click", closeFilterOverlay);

  // Temizle
  $("#foClear")?.addEventListener("click", ()=>{
    // Konum temizle → tüm Türkiye
    $("#foProvince").value = "";
    $("#foDistrict").value = "";
    $("#foNeighborhood").value = "";

    // Zaman temizle
    setWhenDisplay("");
    FO_TEMP = FO_TEMP || { svc: [], date: "", time: [] };
    FO_TEMP.date = "";
    FO_TEMP.time = [];
    DATE_STATE = "";
    TIME_STATE = [];
    refreshOverlayWhenText();

    // Hizmet temizle (temp + UI)
    FO_TEMP.svc = [];
    const s = $("#foSvcSearch"); if (s) s.value = "";
    refreshOverlayServices();
  });

  // Uygula
  $("#foApply")?.addEventListener("click", ()=>{
    const il  = $("#foProvince").value;
    const ilc = $("#foDistrict").value;
    const mah = $("#foNeighborhood").value;

    // Ana select’lere yansıt
    if (fProvince)     fProvince.value     = il || "";
    if (fDistrict)     fDistrict.value     = ilc || "";
    if (fNeighborhood) fNeighborhood.value = mah || "";

    // Hizmetler: temp -> gerçek
    SVC_STATE = Array.isArray(FO_TEMP?.svc) ? FO_TEMP.svc.slice() : [];

    updateURLFromUI();
    updateFiltersButtonLabel();
    renderList();
    fetchSalons();
    closeFilterOverlay();
  });

  // Zaman: TEK BUTON — tarih yoksa GÜN, varsa SAAT
  $("#foWhenBtn")?.addEventListener("click", ()=>{
    if (!DATE_STATE) window.WB_openDateOverlay?.();
    else window.WB_openTimeModal?.();
  });

  // Hizmet arama
  $("#foSvcSearch")?.addEventListener("input", debounce(()=>{
    refreshOverlayServices();
  }, 80));

  populateOverlaySelects();
  refreshOverlayServices();
  refreshOverlayWhenText();
}

async function populateOverlaySelects(){
  const foProvince     = $("#foProvince");
  const foDistrict     = $("#foDistrict");
  const foNeighborhood = $("#foNeighborhood");
  if (!foProvince || !foDistrict || !foNeighborhood) return;

  try {
    const { attachTRLocationCombo } = await import("./components/select-combo.js");
    await attachTRLocationCombo({
      citySelect:       foProvince,
      districtSelect:   foDistrict,
      neighborhoodSelect: foNeighborhood
    });
  } catch (e) {
    console.warn("[kuafor] overlay select-combo yüklenemedi:", e);
  }

  // Ana filtrede seçili olan konumu modal içine yansıt
  const il  = (fProvince?.value || "").trim();
  const ilc = (fDistrict?.value || "").trim();
  const mah = (fNeighborhood?.value || "").trim();

  if (il) {
    foProvince.value = il;
    foProvince.dispatchEvent(new Event("change"));
  }
  if (ilc) {
    setTimeout(() => {
      foDistrict.value = ilc;
      foDistrict.dispatchEvent(new Event("change"));
      if (mah) {
        setTimeout(() => {
          foNeighborhood.value = mah;
        }, 40);
      }
    }, 40);
  }
}

/* === Hizmet UI yardımcıları (Seç/Seçildi) === */
function applySvcButtonState(btn, active){
  btn.setAttribute("aria-pressed", active ? "true" : "false");
  btn.textContent = active ? "Seçildi" : "Seç";
  btn.style.fontWeight = "800";
  btn.style.borderRadius = "10px";
  btn.style.padding = "8px 10px";
  btn.style.transition = "filter .15s ease";
  btn.style.border = "1px solid " + (active ? "var(--ok)" : "var(--border)");
  btn.style.background = active ? "var(--ok)" : "#fff";
  btn.style.color = active ? "#fff" : "var(--ink)";
}

/* Overlay içi Hizmet listesi (butonlu ve aramalı) */
function refreshOverlayServices(){
  const host = $("#foServices");
  if (!host) return;

  const search = trNorm($("#foSvcSearch")?.value || "");
  const all = distinctServices();
  const list = all.filter(nm => !search || trNorm(nm).includes(search));

  host.innerHTML = "";

  if (!list.length){
    const div = document.createElement("div");
    div.className = "muted";
    div.style.gridColumn = "1 / -1";
    div.textContent = "Sonuç yok.";
    host.appendChild(div);
    return;
  }

  const selectedSet = new Set(FO_TEMP?.svc ?? SVC_STATE);

  list.forEach(nm => {
    const row = document.createElement("div");
    row.className = "svc-item";
    row.style.display = "flex";
    row.style.alignItems = "center";
    row.style.justifyContent = "space-between";
    row.style.gap = "10px";
    row.style.border = "1px solid var(--border)";
    row.style.borderRadius = "12px";
    row.style.padding = "8px 10px";
    row.style.background = "#fff";

    const name = document.createElement("span");
    name.className = "svc-name";
    name.textContent = nm;
    name.style.fontWeight = "600";
    name.style.lineHeight = "1.2";

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "svc-select";
    btn.dataset.name = nm;

    applySvcButtonState(btn, selectedSet.has(nm));

    const toggle = ()=>{
      const active = btn.getAttribute("aria-pressed") !== "true";
      applySvcButtonState(btn, active);
      const cur = new Set(FO_TEMP?.svc ?? SVC_STATE);
      if (active) cur.add(nm); else cur.delete(nm);
      FO_TEMP = FO_TEMP || { svc: [], date: DATE_STATE, time: TIME_STATE.slice() };
      FO_TEMP.svc = Array.from(cur);
    };

    btn.addEventListener("click", toggle);
    btn.addEventListener("keydown", (e)=>{ if(e.key===" "||e.key==="Enter"){ e.preventDefault(); toggle(); } });

    row.appendChild(name);
    row.appendChild(btn);
    host.appendChild(row);
  });
}

/* Overlay içi Zaman metni (buton üstüne) */
function refreshOverlayWhenText(){
  const btn = $("#foWhenBtn");
  if (!btn) return;

  let s = "";
  if (DATE_STATE){
    try{
      const dTxt = new Date(DATE_STATE).toLocaleDateString("tr-TR",{day:"2-digit",month:"long",year:"numeric"});
      s = dTxt;
    }catch{}
  }
  if (TIME_STATE.length){
    s = [s, TIME_STATE.join(", ")].filter(Boolean).join(" • ");
  }

  btn.textContent = s || "Seçilmedi";
  btn.classList.toggle("filled", !!s);
}

function openFilterOverlay(){
  ensureFilterOverlay();

  // Temp snapshot
  FO_TEMP = {
    svc: SVC_STATE.slice(),
    date: DATE_STATE,
    time: TIME_STATE.slice()
  };

  populateOverlaySelects();
  refreshOverlayServices();
  refreshOverlayWhenText();

  filterOverlay.classList.add("active");
  filterOverlay.style.display = "grid";
  filterOverlay.setAttribute("aria-hidden","false");
  syncBodyScrollLock();
  window.WB_closeFilterOverlay = closeFilterOverlay;
}
function closeFilterOverlay(){
  if (!filterOverlay) return;
  filterOverlay.classList.remove("active");
  filterOverlay.style.display = "";
  filterOverlay.setAttribute("aria-hidden","true");
  FO_TEMP = null;
  syncBodyScrollLock();
}

/* ---------- Clear helper ---------- */
function clearFilters(){
  // Tüm şehir / ilçe / mahalle temiz
  if (fProvince)     fProvince.value = "";
  if (fDistrict)     fDistrict.value = "";
  if (fNeighborhood) fNeighborhood.value = "";

  if (qSvc) qSvc.value = "";
  if (qLoc) qLoc.value = "";
  IS_FUZZY_LOC = false;

  DATE_STATE = "";
  TIME_STATE = [];
  SVC_STATE  = [];
  setWhenDisplay("");

  const p = new URLSearchParams(location.search);
  p.delete("il");
  p.delete("ilce");
  p.delete("mahalle");
  p.delete("loc");
  p.delete("q");
  p.delete("date");
  p.delete("time");
  p.delete("svc");

  const qs = p.toString();
  history.replaceState({}, "", qs ? `${location.pathname}?${qs}` : location.pathname);
  params = new URLSearchParams(location.search);
  updateFiltersButtonLabel();
  renderList();
}

/* ---------- Events ---------- */
fDistrict?.addEventListener("change", () => {
  updateURLFromUI();
  renderList();
  fetchSalons();
});
fNeighborhood?.addEventListener("change", () => {
  updateURLFromUI();
  renderList();
  fetchSalons();
});

qSvc?.addEventListener("input", debounce(() => { updateURLFromUI(); renderList(); fetchSalons(); }, 250));
qLoc?.addEventListener("input", debounce(() => { updateURLFromUI(); renderList(); }, 200));

/* ---------- Tarih & saat seçici ---------- */
(function wireDateAndTimePickers(){
  if (!qWhen || !dateOverlay) return;

  // Eski kalıntı (temizlik)
  document.getElementById("timeModal")?.remove();

  function ensureOverlayCSS(){
    if (document.getElementById("overlayCSS")) return;
    const style = document.createElement("style");
    style.id = "overlayCSS";
    style.textContent = `
      body.no-scroll{ overflow:hidden!important; }
      #sb-date-overlay{ position:fixed; inset:0; z-index:${Z.date}; }
      #timeOverlay .time-box, .filter-overlay .time-box{
        width:min(520px,92vw); max-height:min(85vh,720px); overflow:auto;
        background:#fff; border-radius:16px; padding:16px; box-shadow:0 10px 40px rgba(0,0,0,.2);
      }
      .modal-overlay{ z-index:${Z.modal}; }
    `;
    document.head.appendChild(style);
  }
  ensureOverlayCSS();

  const head  = dateOverlay.querySelector(".month");
  const dateGrid  = dateOverlay.querySelector(".grid");
  const btnPrev = dateOverlay.querySelector(".prev");
  const btnNext = dateOverlay.querySelector(".next");
  const btnClose= dateOverlay.querySelector(".sb-date-close");
  const btnOk   = dateOverlay.querySelector(".ok");
  const btnClr  = dateOverlay.querySelector(".clear");

  const chipsWrap = dateOverlay.querySelector(".chips");
  if (chipsWrap) chipsWrap.style.display = "none";

  let view = new Date(); view.setDate(1);
  let picked = DATE_STATE ? new Date(DATE_STATE) : null;

  function fmt(d){ return d.toISOString().slice(0,10); }

  function openDate(){
    dateOverlay.classList.add("open");
    dateOverlay.style.display = "grid";           // açıkken görünür
    dateOverlay.style.zIndex = Z.date;
    dateOverlay.setAttribute("aria-hidden","false");
    renderMonth();
    syncBodyScrollLock();
    window.WB_closeDateOverlay = closeDate;
  }
  function closeDate(hard=false){
    dateOverlay.classList.remove("open");
    dateOverlay.setAttribute("aria-hidden","true");
    if (hard) dateOverlay.style.display = "none"; // hard close → stacking dışı
    else dateOverlay.style.display = "";
    syncBodyScrollLock();
  }

  function renderMonth(){
    if (head) head.textContent = view.toLocaleDateString("tr-TR",{year:"numeric",month:"long"});
    if (!dateGrid) return;

    dateGrid.innerHTML = "";

    const firstDay = (view.getDay() + 6) % 7; // Pazartesi=0
    const daysInMonth = new Date(view.getFullYear(), view.getMonth()+1, 0).getDate();
    const today0 = new Date(); today0.setHours(0,0,0,0);

    for(let i=0;i<firstDay;i++) dateGrid.appendChild(document.createElement("span"));

    for(let d=1; d<=daysInMonth; d++){
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = d;
      btn.setAttribute("aria-label",`${d} seç`);
      const cur = new Date(view.getFullYear(), view.getMonth(), d);
      const cur0 = new Date(cur); cur0.setHours(0,0,0,0);

      if (cur0 < today0) { btn.disabled = true; btn.setAttribute("aria-disabled","true"); }
      if (picked && fmt(cur) === fmt(picked)) btn.classList.add("active");

      // GÜN TIKLANIR TIKLANMAZ: tarih kapat + saat aç
      btn.addEventListener("click", () => {
        if (btn.disabled) return;

        picked = cur;
        DATE_STATE = fmt(picked);

        Array.from(dateGrid.querySelectorAll("button")).forEach(b=>b.classList.remove("active"));
        btn.classList.add("active");

        if (DATE_STATE) {
          try {
            const dd = new Date(DATE_STATE).toLocaleDateString("tr-TR", { day:"2-digit", month:"long", year:"numeric" });
            setWhenDisplay([dd, TIME_STATE.join(", ")].filter(Boolean).join(" • "));
          } catch {}
        }

        closeDate(true);                  // HARD CLOSE → display:none
        setTimeout(() => openTimeModal(), 0); // bir sonraki tikte kesin üstte
      });

      dateGrid.appendChild(btn);
    }
  }

  renderMonth();

  dateOverlay.addEventListener("click", (e)=>{ if(e.target===dateOverlay) closeDate(); });
  btnClose?.addEventListener("click", () => closeDate());
  btnPrev?.addEventListener("click", () => { view.setMonth(view.getMonth()-1); renderMonth(); });
  btnNext?.addEventListener("click", () => { view.setMonth(view.getMonth()+1); renderMonth(); });

  btnOk?.addEventListener("click", () => {
    if (picked){
      DATE_STATE = fmt(picked);
      closeDate(true);
      setTimeout(()=>openTimeModal(),0);
    } else {
      closeDate();
    }
  });
  btnClr?.addEventListener("click", () => {
    picked=null; DATE_STATE=""; TIME_STATE=[]; setWhenDisplay(""); updateURLFromUI(); renderList(); closeDate();
    refreshOverlayWhenText();
  });

  /* ---- TIME MODAL (statik/dinamik ikisini de bağla) ---- */
  function bindTimeOverlayEvents(el){
    if (!el || el._wbBound) return;
    const grid = el.querySelector("#timeGrid");

    // Dışarı tıkla -> kapa
    el.addEventListener("click", (e)=>{ if (e.target===el) closeTimeModal(); });
    el.querySelector(".time-close")?.addEventListener("click", closeTimeModal);

    // === YENİ: “Tarihi Değiştir” butonunu enjekte et (yoksa)
    const actions = el.querySelector(".time-actions");
    if (actions && !actions.querySelector('[data-action="pick-date"]')){
      const pickBtn = document.createElement("button");
      pickBtn.type = "button";
      pickBtn.className = "btn";
      pickBtn.textContent = "Tarihi Değiştir";
      pickBtn.setAttribute("data-action","pick-date");
      actions.insertBefore(pickBtn, actions.firstChild);
    }
    el.querySelector('[data-action="pick-date"]')?.addEventListener("click", ()=>{
      closeTimeModal();
      setTimeout(()=>openDate(),0);
    });

    // Cancel (data-action ile destek)
    el.querySelector('[data-action="cancel"]')?.addEventListener("click", closeTimeModal);

    // Clear
    const btnClear = el.querySelector("#tClear") || el.querySelector('[data-action="clear"]');
    btnClear?.addEventListener("click", ()=>{
      TIME_STATE=[]; updateURLFromUI(); renderList(); closeTimeModal();
      if (DATE_STATE){
        const dTxt = new Date(DATE_STATE).toLocaleDateString("tr-TR",{day:"2-digit",month:"long",year:"numeric"});
        setWhenDisplay(dTxt);
      } else {
        setWhenDisplay("");
      }
      refreshOverlayWhenText();
    });

    // Apply
    const btnOk = el.querySelector("#tOk") || el.querySelector('[data-action="apply"]');
    btnOk?.addEventListener("click", ()=>{
      const selected = Array.from(grid.querySelectorAll(".time-chip.active")).map(x=>x.dataset.time);
      TIME_STATE = selected;
      const dTxt = DATE_STATE ? new Date(DATE_STATE).toLocaleDateString("tr-TR",{day:"2-digit",month:"long",year:"numeric"}) : "";
      setWhenDisplay([dTxt, TIME_STATE.join(", ")].filter(Boolean).join(" • "));
      updateURLFromUI(); renderList();
      closeTimeModal();
      refreshOverlayWhenText();
    });

    el._wbBound = true;
  }

  function ensureTimeOverlay(){
    // Statik overlay varsa onu kullan; yoksa oluştur.
    let el = document.getElementById("timeOverlay");
    if (!el){
      el = document.createElement("div");
      el.id = "timeOverlay";
      el.className = "time-overlay";
      el.setAttribute("aria-hidden","true");
      el.style.position = "fixed";
      el.style.inset = "0";
      el.style.background = "rgba(0,0,0,.45)";
      el.style.display = "none";
      el.style.placeItems = "center";
      el.style.zIndex = String(Z.time);
      el.innerHTML = `
        <div class="time-box" role="dialog" aria-modal="true" aria-labelledby="timeTitle">
          <button class="time-close" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
          <h2 id="timeTitle" class="modal-title-center" style="margin:4px 0 12px">Saat Seç</h2>
          <div id="timeGrid" class="time-grid" aria-multiselectable="true"></div>
          <div class="time-actions" style="display:flex;gap:10px;margin-top:10px;justify-content:flex-end">
            <button class="btn btn-danger" data-action="cancel">İptal</button>
            <button id="tClear" class="btn" data-action="clear">Temizle</button>
            <button id="tOk" class="auth-btn" data-action="apply" style="min-width:140px;background:var(--accent);color:var(--accent-ink);border:none;border-radius:12px">Seç</button>
          </div>
        </div>`;
      document.body.appendChild(el);
    } else {
      // statikse z-index'i garantiye al
      el.style.zIndex = String(Z.time);
    }
    bindTimeOverlayEvents(el);
    return el;
  }

  function populateTimes(el){
    const grid = el.querySelector("#timeGrid");
    grid.innerHTML = "";
    const hours = [];
    for(let h=9; h<=21; h++){ if (h!==15) hours.push(`${String(h).padStart(2,"0")}:00`); }
    hours.forEach(hh=>{
      const b = document.createElement("button");
      b.type = "button";
      b.className = "time-chip";
      b.textContent = hh;
      b.dataset.time = hh;
      b.setAttribute("role","option");
      const active = TIME_STATE.includes(hh);
      if (active) b.classList.add("active");
      b.setAttribute("aria-selected", active ? "true" : "false");
      b.addEventListener("click", ()=>{
        b.classList.toggle("active");
        b.setAttribute("aria-selected", b.classList.contains("active") ? "true" : "false");
      });
      grid.appendChild(b);
    });
  }

  function openTimeModal(){
    const el = ensureTimeOverlay();
    populateTimes(el);

    // Tarih overlay’i kesin kapalı
    closeDate(true);

    // Başlıkta seçili tarihi göster
    const title = el.querySelector("#timeTitle");
    if (title){
      const dTxt = DATE_STATE
        ? new Date(DATE_STATE).toLocaleDateString("tr-TR",{day:"2-digit",month:"long",year:"numeric"})
        : "";
      title.innerHTML = dTxt ? `Saat Seç<br><small class="muted" style="font-weight:600">${dTxt}</small>` : "Saat Seç";
    }

    el.classList.add("active");
    el.style.display="grid";
    el.setAttribute("aria-hidden","false");
    syncBodyScrollLock();
    (el.querySelector(".time-chip.active") || el.querySelector(".time-chip"))?.focus();
    window.WB_openTimeModal = openTimeModal;
  }

  function closeTimeModal(){
    const el=document.getElementById("timeOverlay"); if(!el) return;
    el.classList.remove("active");
    el.style.display="";
    el.setAttribute("aria-hidden","true");
    syncBodyScrollLock();
  }

  // === “Ne zaman?” butonu: akış karar verici
  function openWhenFlow(e){
    if (e){ e.preventDefault(); e.stopImmediatePropagation(); }
    if (!DATE_STATE) openDate(); else openTimeModal();
  }

  // qWhen: input ya da button olabilir
  qWhen.addEventListener("click", openWhenFlow, { capture:true });
  qWhen.addEventListener("keydown", (e)=>{ if(e.key==="Enter" || e.key===" "){ openWhenFlow(e); } }, { capture:true });

  // Dışa aç (filtre modali ve navbar için)
  window.WB_openDateOverlay = openDate;
  window.WB_openTimeModal   = openTimeModal;

  // global ESC: saat > tarih > modal > filtre
  window.addEventListener("keydown", (e)=>{
    if (e.key !== "Escape") return;
    const timeOpen = document.getElementById("timeOverlay")?.classList.contains("active");
    const dateOpen = dateOverlay.classList.contains("open");
    const modalOpen = document.querySelector(".modal-overlay.active");
    const filterOpen = document.getElementById("filterOverlay")?.classList.contains("active");

    if (timeOpen) { closeTimeModal(); return; }
    if (dateOpen) { closeDate(); return; }
    if (modalOpen) { closeTopMostModal(); return; }
    if (filterOpen) { closeFilterOverlay(); return; }
  });
})();

/* ---------- Init ---------- */
await prepareFilters();
injectMyAddressQuickAction();
USER_ADDRESS = await resolveUserAddress();
ensureFiltersToggle();
wireMyAddressButton(btnMyAddress);
initGeoButtons();

// Başlangıçta seçili konumu URL ile senkronla (tüm Türkiye destekli)
updateURLFromUI();

renderList();
fetchSalons();
/* ═══════════════════════════════════════════════════════
   CAROUSEL — Kart resim kaydırıcı
   • Fare üzerindeyse her 2s'de bir resim değişir
   • Dokunmatik: swipe
   • Resimler lazy load (hover'da yükle)
   ═══════════════════════════════════════════════════════ */
function initCarousels(container) {
  container.querySelectorAll('.wb-carousel').forEach(carousel => {
    const slides = Array.from(carousel.querySelectorAll('.wb-slide'));
    const dots   = Array.from(carousel.querySelectorAll('.wb-dot'));
    if (slides.length < 2) return; // Tek resimse carousel gerekmez

    let current   = 0;
    let timer     = null;
    let touchStartX = 0;

    function goTo(idx) {
      const prev = current;
      current = (idx + slides.length) % slides.length;
      if (prev === current) return;

      // Lazy load
      const nextSlide = slides[current];
      if (!nextSlide.src && nextSlide.dataset.src) {
        nextSlide.src = nextSlide.dataset.src;
      }

      slides[prev].style.opacity  = '0';
      slides[prev].style.position = 'absolute';
      slides[current].style.opacity  = '1';
      slides[current].style.position = current === 0 ? 'relative' : 'absolute';

      dots.forEach((d, i) => d.classList.toggle('wb-dot--active', i === current));
    }

    function startAuto() {
      stopAuto();
      timer = setInterval(() => goTo(current + 1), 2000);
    }

    function stopAuto() {
      if (timer) { clearInterval(timer); timer = null; }
    }

    // Preload resimler hover'a girmeden önce
    carousel.addEventListener('mouseenter', () => {
      slides.forEach(s => { if (!s.src && s.dataset.src) s.src = s.dataset.src; });
      startAuto();
    });
    carousel.addEventListener('mouseleave', () => {
      stopAuto();
      goTo(0); // İlk resme dön
    });

    // Mobil dokunmatik swipe
    carousel.addEventListener('touchstart', e => {
      slides.forEach(s => { if (!s.src && s.dataset.src) s.src = s.dataset.src; });
      touchStartX = e.touches[0].clientX;
    }, { passive: true });
    carousel.addEventListener('touchend', e => {
      const diff = touchStartX - e.changedTouches[0].clientX;
      if (Math.abs(diff) > 40) goTo(current + (diff > 0 ? 1 : -1));
    }, { passive: true });

    // Dot'lara tıklama (a.card href'i tetiklememesi için)
    dots.forEach((dot, i) => {
      dot.addEventListener('click', e => {
        e.preventDefault();
        e.stopPropagation();
        stopAuto();
        goTo(i);
      });
    });
  });
}

