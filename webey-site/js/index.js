import { loadDirectoryBusinesses, loadListingBusinesses } from "./public-businesses-store.js";

// index.js — Firebase YOK, session tabanlı PHP backend
/* ====== Session auth yardımcısı ====== */
let _sessionUser = null; // { userId, phone, firstName, lastName } | null

async function checkSession() {
  try {
    const res = await fetch('/api/session/me.php', { credentials: 'same-origin' });
    if (!res.ok) { _sessionUser = null; return null; }
    const json = await res.json();
    if (json.ok && json.data?.role === 'user') {
      _sessionUser = json.data;
      if (json.data.csrf_token) {
        _idxCsrfToken = json.data.csrf_token;
        window.__csrfToken = json.data.csrf_token;
      }
      return json.data;
    }
    _sessionUser = null; return null;
  } catch { _sessionUser = null; return null; }
}

/* ====== CSRF Token yardımcısı ====== */
let _idxCsrfToken = null;
async function idxGetCsrf() {
  if (_idxCsrfToken) return _idxCsrfToken;
  if (window.__csrfToken) { _idxCsrfToken = window.__csrfToken; return _idxCsrfToken; }
  try {
    const r = await fetch('/api/csrf.php', { credentials: 'same-origin' });
    const j = await r.json();
    _idxCsrfToken = j?.data?.token || '';
    if (_idxCsrfToken) window.__csrfToken = _idxCsrfToken;
  } catch { _idxCsrfToken = ''; }
  return _idxCsrfToken;
}
async function idxPostJson(url, body) {
  const token = await idxGetCsrf();
  return fetch(url, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
    body: JSON.stringify(body),
  });
}

/* Sayfa-özel bayrak (kuafor.html bu değişkeni true yapar) */
window.WB_DISABLE_NAV_SUGGEST = !!window.WB_DISABLE_NAV_SUGGEST;

/* ========== KÜÇÜK YARDIMCILAR ========== */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const pad = (n) => String(n).padStart(2, "0");
const MON = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
const DOW = ["Paz", "Pts", "Sal", "Çar", "Per", "Cum", "Cts"];

/* ---- Body scroll kilidi (search öneri paneli için) ---- */
const isMobileLike = () => window.matchMedia("(max-width: 860px)").matches;
let __wbLockY = 0;
function addBodyLock() {
  if (!isMobileLike()) return;
  if (document.body.classList.contains("wb-lock")) return;
  __wbLockY = window.scrollY || 0;
  document.body.style.top = `-${__wbLockY}px`;
  document.body.classList.add("wb-lock");
}
function removeBodyLock() {
  if (!document.body.classList.contains("wb-lock")) return;
  const y = Math.abs(parseInt(document.body.style.top || "0", 10)) || 0;
  document.body.classList.remove("wb-lock");
  document.body.style.top = "";
  window.scrollTo(0, y);
}

/* ---- Splash bariyeri: auth/recommended/hero ---- */
const pendingGates = new Set(["auth", "recommended", "hero"]);
function markGateDone(name) {
  if (pendingGates.has(name)) pendingGates.delete(name);
  if (pendingGates.size === 0) closeSplash();
}
function closeSplash() {
  const ov = document.getElementById("splashOverlay");
  if (!ov) return;
  ov.setAttribute("aria-hidden", "true");
  ov.classList.add("closing");
  ov.style.transition = ov.style.transition || "opacity .25s ease, visibility .25s ease";
  ov.style.opacity = "0";
  setTimeout(() => {
    try {
      ov.remove();
    } catch {
      ov.style.display = "none";
    }
  }, 280);
}
function emitHeroReadyOnce() {
  if (emitHeroReadyOnce._done) return;
  emitHeroReadyOnce._done = true;
  try {
    document.dispatchEvent(new Event("hero:ready"));
  } catch {}
  markGateDone("hero");
}
emitHeroReadyOnce._done = false;

/* ---- dış modüllerden beklenen sinyaller ---- */
document.addEventListener("auth:ready", () => markGateDone("auth"), { once: true });
document.addEventListener("recommended:ready", () => markGateDone("recommended"), { once: true });

/* ---- failsafe ---- */
const GATE_TIMEOUT_MS = 2500;
setTimeout(() => markGateDone("auth"), GATE_TIMEOUT_MS);
setTimeout(() => markGateDone("recommended"), GATE_TIMEOUT_MS + 200);

/* ========== TARİH-SAAT FORMATLAYICI ========== */
const HERO_IMAGE_URL = "img/hero-cover.webp";

function toDateValue(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const normalized = trimmed.includes("T") ? trimmed : trimmed.replace(" ", "T");
    const parsed = new Date(normalized);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function fmtWhen(dStart, dEnd) {
  const start = toDateValue(dStart);
  const endDate = toDateValue(dEnd);
  if (!start) return "—";
  const dow = DOW[start.getDay()];
  const str = `${dow} • ${pad(start.getDate())} ${MON[start.getMonth()]} ${start.getFullYear()} — ${pad(start.getHours())}:${pad(start.getMinutes())}`;
  const end = endDate ? ` – ${pad(endDate.getHours())}:${pad(endDate.getMinutes())}` : "";
  return str + end;
}
function trStatus(raw = "scheduled") {
  const s = (raw || "").toLowerCase();
  if (s.includes("cancel")) return { txt: "İptal Edildi", color: "#ef4444" };
  if (s.includes("complete") || s === "done" || s === "finished" || s === "attended" || s === "approved")
    return { txt: "Tamamlandı", color: "#10b981" };
  return { txt: "Planlandı", color: "#16a34a" };
}
function buildMapsLinks(loc = {}, bizName = "", addrText = "", mode = "search") {
  const direct = loc.googleMapsUrl || loc.googleMapUrl || loc.mapUrl || loc.mapLink || loc.gmapsUrl;
  const hasLL = Number.isFinite(loc.lat) && Number.isFinite(loc.lng);
  const fullAddr =
    addrText ||
    [loc.street && (loc.building ? `${loc.street} ${loc.building}` : loc.street), loc.neighborhood, loc.district, loc.province]
      .filter(Boolean)
      .join(", ");
  const queryQ = hasLL ? `${loc.lat},${loc.lng}` : (bizName ? `${bizName}, ` : "") + fullAddr;
  const openHref =
    direct ||
    (mode === "directions"
      ? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(queryQ)}`
      : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(queryQ)}`);
  const embedSrc = `https://www.google.com/maps?hl=tr&q=${encodeURIComponent(queryQ)}&z=15&output=embed`;
  return { openHref, embedSrc };
}

function hasValidUpcomingAppointment(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return false;
  const businessId = String(data.businessId || data.business_id || "").trim();
  const startValue = String(data.start || data.startISO || data.start_at || "").trim();
  return businessId !== "" && startValue !== "";
}

/* ========== GENEL MODAL YÖNETİMİ ========== */
const FOCUSABLE = [
  'a[href]',
  "area[href]",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "button:not([disabled])",
  "iframe",
  "object",
  "embed",
  '[tabindex]:not([tabindex="-1"])',
  '[contenteditable="true"]'
].join(",");

let lastTriggerEl = null;

function ensureAuthModal() {
  if (document.getElementById("authModal")) return;
  const m = document.createElement("div");
  m.id = "authModal";
  m.className = "modal-overlay";
  m.setAttribute("hidden", ""); // başlangıçta tamamen gizli
  m.innerHTML = `
    <div class="modal-box">
      <button class="modal-close" aria-label="Kapat"><i class="fas fa-times" aria-hidden="true"></i></button>
      <div class="auth-container"></div>
    </div>`;
  document.body.appendChild(m);
  // kapatma bağları
  m.addEventListener("click", (e) => {
    if (e.target === m) closeTopMostModal();
  });
  m.querySelector(".modal-close")?.addEventListener("click", () => closeTopMostModal());
}

function openModal(modalId = "authModal") {
  const m = document.getElementById(modalId);
  if (!m) return;
  // ÖNEMLİ: gizlilik bayrağını kaldır
  m.removeAttribute("hidden");
  lastTriggerEl = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  m.classList.add("active");
  m.setAttribute("aria-hidden", "false");
  document.body.classList.add("no-scroll");
  hideSuggest();
  const first = m.querySelector(FOCUSABLE);
  if (first) first.focus({ preventScroll: true });
}
function closeModal(modalId = "authModal") {
  const m = document.getElementById(modalId);
  if (!m) return;
  m.classList.remove("active");
  m.setAttribute("aria-hidden", "true");
  document.body.classList.remove("no-scroll");
  // Tekrar tamamen gizle
  m.setAttribute("hidden", "");
  if (lastTriggerEl && document.contains(lastTriggerEl)) {
    lastTriggerEl.focus({ preventScroll: true });
  }
}
function closeTopMostModal() {
  const opened = $$(".modal-overlay.active");
  if (!opened.length) return;
  const top = opened[opened.length - 1];
  top.classList.remove("active");
  top.setAttribute("aria-hidden", "true");
  // Başka açık modal kalmadıysa body scroll’u aç ve gizle
  if (!$$(".modal-overlay.active").length) {
    document.body.classList.remove("no-scroll");
  }
  // Tamamen gizle
  top.setAttribute("hidden", "");
  if (lastTriggerEl && document.contains(lastTriggerEl)) {
    lastTriggerEl.focus({ preventScroll: true });
  }
}
$$(".modal-overlay").forEach((m) => {
  m.addEventListener("click", (e) => {
    if (e.target === m) closeTopMostModal();
  });
  m.querySelector(".modal-close")?.addEventListener("click", () => closeTopMostModal());
});

/* --------- AUTH modalını açan tek noktadan fonksiyon --------- */
async function openAuthFlow(e) {
  if (e) {
    e.preventDefault();
    e.stopPropagation();
  }
  try {
    if (!window.__authLoaded) {
      window.__authLoaded = true;
      await import("./auth.js");
      document.dispatchEvent(new Event("auth:ready"));
    }
  } catch (err) {
    console.warn("auth lazy import failed:", err);
  }
  ensureAuthModal();
  openModal("authModal");
  // DOB orta çizgi + hizalama fix
  waitDobViewportAndFix();
}

/* --- Delegation ile yakala (ikon/label tıklamaları dahil) --- */
document.addEventListener("click", (e) => {
  const btn = e.target.closest(".open-auth");
  if (!btn) return;
  openAuthFlow(e);
});

document.addEventListener("keydown", (e) => {
  const btn = e.target.closest?.(".open-auth");
  if (!btn) return;
  if (e.key === "Enter" || e.key === " ") {
    openAuthFlow(e);
  }
});

/* Profil butonu → kullanıcı girişliyse user-profile.html’e git
   CAPTURE fazında, alttaki open-auth listenerlarını iptal ederek. */
document.addEventListener(
  "click",
  (e) => {
    const btn = e.target.closest("[data-goto-profile]");
    if (!btn) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    window.location.href = "user-profile.html";
  },
  { capture: true }
);

/* Klavye ile (Enter/Space) profil açma – yine capture */
document.addEventListener(
  "keydown",
  (e) => {
    const btn = e.target.closest?.("[data-goto-profile]");
    if (!btn) return;
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      e.stopImmediatePropagation();
      window.location.href = "user-profile.html";
    }
  },
  { capture: true }
);

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && $$(".modal-overlay.active").length) {
    e.preventDefault();
    closeTopMostModal();
  }
});
document.addEventListener("keydown", (e) => {
  if (e.key !== "Tab") return;
  const opened = $$(".modal-overlay.active");
  if (!opened.length) return;
  const top = opened[opened.length - 1];
  const focusables = Array.from(top.querySelectorAll(FOCUSABLE)).filter(
    (el) => el.offsetParent !== null || el === document.activeElement
  );
  if (!focusables.length) return;
  const first = focusables[0];
  const last = focusables[focusables.length - 1];
  if (e.shiftKey) {
    if (document.activeElement === first || !top.contains(document.activeElement)) {
      e.preventDefault();
      last.focus({ preventScroll: true });
    }
  } else {
    if (document.activeElement === last) {
      e.preventDefault();
      first.focus({ preventScroll: true });
    }
  }
});
window.AppModals = { openModal, closeModal };

/* ========== NAVBAR görünüm ========== */
const navbar = document.getElementById("mainNavbar");
const hero = document.getElementById("heroSec");
const heroVideo = document.getElementById("heroVideo");
const NAV_THRESHOLD_RATIO = 0.6;

function applyNavVisual(show) {
  document.body.classList.toggle("scrolled", show);
  navbar?.classList.toggle("visible", show);
  if (navbar) {
    navbar.classList.toggle("solid", show);
    navbar.classList.toggle("transparent", !show);
  }
}
if (navbar && !hero) {
  applyNavVisual(true);
} else {
  function fallbackByScroll() {
    const h = hero?.offsetHeight || window.innerHeight;
    const threshold = h * NAV_THRESHOLD_RATIO;
    const show = window.scrollY > threshold;
    applyNavVisual(show);
  }
  function setupNavObserver() {
    if (!navbar || !hero || !("IntersectionObserver" in window)) {
      ["load", "scroll", "resize", "orientationchange"].forEach((evt) =>
        window.addEventListener(evt, fallbackByScroll, { passive: true })
      );
      heroVideo?.addEventListener("loadedmetadata", fallbackByScroll);
      fallbackByScroll();
      return;
    }
    const sentinel = document.createElement("div");
    sentinel.setAttribute("aria-hidden", "true");
    Object.assign(sentinel.style, {
      position: "absolute",
      left: "0",
      right: "0",
      height: "1px",
      pointerEvents: "none"
    });
    hero.appendChild(sentinel);
    const positionSentinel = () => {
      const h = hero?.offsetHeight || window.innerHeight;
      sentinel.style.top = `${Math.max(1, Math.round(h * NAV_THRESHOLD_RATIO))}px`;
    };
    positionSentinel();
    window.addEventListener("resize", positionSentinel);
    window.addEventListener("orientationchange", positionSentinel);
    heroVideo?.addEventListener("loadedmetadata", positionSentinel);
    const io = new IntersectionObserver(
      ([entry]) => applyNavVisual(!entry.isIntersecting),
      { root: null, threshold: 0 }
    );
    io.observe(sentinel);
  }
  setupNavObserver();
}

/* Navbar profil butonu renk + tıklanabilirlik fix’i */
(function ensureNavBtnStyle() {
  if (document.getElementById("wb-nav-btn-style")) return;
  const st = document.createElement("style");
  st.id = "wb-nav-btn-style";
  st.textContent = `
    /* Bazı temalarda pointer-events kapatılmışsa bile buton çalışsın */
    .navbar, .hero-navbar-right { pointer-events:auto!important }
    .navbar .profile, .hero-navbar-right .profile{
      background:#0ea5b3!important;color:#fff!important;border:0!important;border-radius:999px;
      padding:8px 14px;font-weight:800;pointer-events:auto!important;cursor:pointer
    }
    .navbar .profile:hover{filter:brightness(1.05)}
  `;
  document.head.appendChild(st);
})();

/* ========== HERO başlığı animasyonu ========== */
const heroTitle = document.getElementById("changingText");
const phrases = ["Webey", "Webey", "Webey", "Webey", "Webey", "Webey"];
let phraseIndex = 1;
function buildSpans(text) {
  if (!heroTitle) return;
  heroTitle.innerHTML = "";
  [...text].forEach((ch, i) => {
    const span = document.createElement("span");
    span.textContent = ch === " " ? "\u00A0" : ch;
    span.style.animationDelay = `${i * 0.05}s`;
    heroTitle.appendChild(span);
  });
}
function cycleText() {
  if (!heroTitle) return;
  heroTitle.classList.add("fade-out");
  setTimeout(() => {
    heroTitle.classList.remove("fade-out");
    buildSpans(phrases[phraseIndex]);
    phraseIndex = (phraseIndex + 1) % phrases.length;
  }, 300);
}
if (heroTitle) {
  buildSpans(phrases[0]);
  let cycleTimer = setInterval(cycleText, 2500);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      clearInterval(cycleTimer);
      cycleTimer = null;
    } else if (!cycleTimer) {
      cycleTimer = setInterval(cycleText, 2500);
    }
  });
}

/* ========== Logo → en üste kaydır ========== */
document.getElementById("logoBtn")?.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: "smooth" });
});

/* ========== İstanbul ilçeleri listesi (grid) ========== */
const districts = [
  "Adalar",
  "Arnavutköy",
  "Ataşehir",
  "Avcılar",
  "Bağcılar",
  "Bahçelievler",
  "Bakırköy",
  "Başakşehir",
  "Bayrampaşa",
  "Beşiktaş",
  "Beykoz",
  "Beylikdüzü",
  "Beyoğlu",
  "Büyükçekmece",
  "Çatalca",
  "Çekmeköy",
  "Esenler",
  "Esenyurt",
  "Eyüpsultan",
  "Fatih",
  "Gaziosmanpaşa",
  "Güngören",
  "Kadıköy",
  "Kağıthane",
  "Kartal",
  "Küçükçekmece",
  "Maltepe",
  "Pendik",
  "Sancaktepe",
  "Sarıyer",
  "Silivri",
  "Şile",
  "Şişli",
  "Sultanbeyli",
  "Sultangazi",
  "Tuzla",
  "Ümraniye",
  "Üsküdar",
  "Zeytinburnu"
];

const grid = document.getElementById("districtGrid");
if (grid) {
  const COLS = 4,
    perCol = Math.ceil(districts.length / COLS);
  for (let c = 0; c < COLS; c++) {
    const ul = document.createElement("ul");
    ul.className = "district-col";
    districts.slice(c * perCol, (c + 1) * perCol).forEach((name) => {
      const li = document.createElement("li");
      li.className = "district-item";
      li.innerHTML = `
        <button class="district-toggle" type="button" data-ilce="${name}">
          <i class="fas fa-chevron-right" aria-hidden="true"></i>
          <span>${name}</span>
        </button>`;
      ul.appendChild(li);
    });
    grid.appendChild(ul);
  }
  grid.addEventListener("click", (e) => {
    const btn = e.target.closest(".district-toggle");
    if (!btn) return;
    const name = btn.dataset.ilce || btn.querySelector("span")?.textContent?.trim() || "";
    const params = new URLSearchParams({ il: "İstanbul", ilce: name });
    window.location.href = `kuafor.html?${params}`;
  });
}

/* =========================================================
   YAKLAŞAN RANDEVU WIDGET'I (hero bölgesi)
========================================================= */
const apptHero = $("#apptHero");
const heroSec = $("#heroSec");
const elStatus = $("#homeApptStatus");
const elTitle = $("#homeApptTitle");
const elBiz = $("#homeApptBiz");
const elAddr = $("#homeApptAddr");
const elWhen = $("#homeApptWhen");
const elLogo = $("#homeApptLogo");
const elMap = $("#homeApptGm");
const btnOpen = $("#homeApptOpen");
const btnMap = $("#homeApptMap");
const btnBook = $("#homeApptBook");

function pauseHeroVideo() {
  try {
    heroVideo?.pause();
    document.body.classList.add("hero-paused");
  } catch {}
}
function resumeHeroVideo() {
  try {
    if (heroVideo && heroVideo.paused) heroVideo.play().catch(() => {});
    document.body.classList.remove("hero-paused");
  } catch {}
}

function ensureMobileHeroImage() {
  if (!isMobileLike()) return;
  const host = document.getElementById("heroSec");
  if (!host) return;

  if (!host.style.backgroundImage) {
    host.style.background = `url('${HERO_IMAGE_URL}') center top / cover no-repeat #000`;
  }

  // Artık video kullanmıyoruz, sadece olası kalıntıları temizleyelim
  if (heroVideo) {
    heroVideo.removeAttribute("src");
    heroVideo.removeAttribute("poster");
    heroVideo.load();
  }
}


/* --- HERO VİDEOYU GÖRÜNÜR OLUNCA YÜKLE --- */
function lazyLoadHeroVideo() {
  const v = document.getElementById("heroVideo");
  if (!v) {
    emitHeroReadyOnce();
    return;
  }

  // **GÜNCELLEME**: Mobilde videoyu hiç yükleme (performans için)
  if (isMobileLike()) {
    ensureMobileHeroImage();
    document.body.classList.add("hero-paused");
    emitHeroReadyOnce();
    return;
  }

  const saveData = navigator.connection && navigator.connection.saveData;
  if (saveData) {
    document.body.classList.add("hero-paused");
    emitHeroReadyOnce();
    return;
  }

  const setSrc = () => {
    if (v.dataset.src && !v.src) {
      v.src = v.dataset.src;
      v.load();
      v.play().catch(() => {});
    }
  };

  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      ([ent]) => {
        if (ent.isIntersecting) {
          setSrc();
          io.disconnect();
        }
      },
      { threshold: 0.2 }
    );
    io.observe(v);
  } else {
    ["scroll", "mousemove", "touchstart"].forEach((ev) =>
      window.addEventListener(ev, setSrc, { once: true, passive: true })
    );
    setTimeout(setSrc, 1500);
  }
}
if (document.readyState !== "loading") {
  ensureMobileHeroImage();
  lazyLoadHeroVideo();
} else
  document.addEventListener("DOMContentLoaded", () => {
    ensureMobileHeroImage();
    lazyLoadHeroVideo();
  });

/* ========= YENİ Firestore ŞEMASINA GÖRE RANDEVU OKUMA ========= */
/**
 * Kullanıcının tüm salonlardaki en yakın gelecekteki randevusunu bulur.
 * Kaynak: businesses/{businessId}/appointments (collectionGroup)
 */
/* fetchNextAppointment → initSessionAuth içinde PHP API ile değiştirildi */

async function getBusinessLoc(bizId) {
  if (!bizId) return {};
  try {
    const res = await fetch('/api/public/business.php?id=' + encodeURIComponent(bizId));
    if (!res.ok) return {};
    const json = await res.json();
    return json.ok ? (json.data || {}) : {};
  } catch { return {}; }
}

function pickHeroBusinessImage(biz = {}) {
  return (
    biz.coverUrl ||
    biz.logoUrl ||
    (Array.isArray(biz.images?.cover_opt) ? biz.images.cover_opt[0] : null) ||
    (Array.isArray(biz.images?.cover) ? biz.images.cover[0] : null) ||
    (Array.isArray(biz.images?.salon_opt) ? biz.images.salon_opt[0] : null) ||
    (Array.isArray(biz.images?.salon) ? biz.images.salon[0] : null) ||
    "img/berber1.jpeg"
  );
}

/* --- Harita lazy load --- */
function ensureMapLoaded(url) {
  if (!url || !elMap) return;
  if (!elMap.src) elMap.src = url;
}
function showApptHero(rec, bizLoc) {
  if (!apptHero || !heroSec) return; // profile.html gibi sayfalarda element olmayabilir
  const st = trStatus(rec.status);
  elStatus.textContent = st.txt;
  elStatus.style.background = st.color;
  elTitle.textContent = rec.serviceTitle || "Hizmet";

  const bizName = bizLoc.name || rec.businessName || "İşletme";
  elBiz.textContent = bizName;

  const addr = (bizLoc && typeof bizLoc === "object")
    ? (bizLoc.loc || bizLoc.location || bizLoc)
    : {};
  const primaryAddr = [addr.neighborhood, addr.district].filter(Boolean).join(", ");
  const line1 = [
    addr.street && (addr.building ? `${addr.street} ${addr.building}` : addr.street),
    addr.neighborhood
  ]
    .filter(Boolean)
    .join(", ");
  const line2 = [addr.district, addr.province || addr.city].filter(Boolean).join(", ");
  const full = primaryAddr || [line1, line2].filter(Boolean).join(" • ") || "—";
  elAddr.textContent = full;

  elWhen.textContent = fmtWhen(rec.start, rec.end);
  elLogo.src = pickHeroBusinessImage(bizLoc);
  elLogo.onerror = () => {
    elLogo.onerror = null;
    elLogo.src = "img/berber1.jpeg";
  };

  const { openHref, embedSrc } = buildMapsLinks(
    addr,
    bizName,
    full.replace(" • ", ", ")
  );
  elMap.removeAttribute("src");
  elMap.dataset.src = embedSrc;
  btnMap.href = openHref;

  if ("IntersectionObserver" in window) {
    const mapWrap = document.querySelector(".ah-map");
    const ioMap = new IntersectionObserver(
      ([ent]) => {
        if (ent.isIntersecting) {
          ensureMapLoaded(elMap.dataset.src);
          ioMap.disconnect();
        }
      },
      { threshold: 0.1 }
    );
    if (mapWrap) ioMap.observe(mapWrap);
  }
  btnMap.addEventListener(
    "click",
    () => ensureMapLoaded(elMap.dataset.src),
    { once: true }
  );

  apptHero.hidden = false;
  apptHero.removeAttribute('aria-hidden');
  heroSec.classList.add("has-appt");
  pauseHeroVideo();
}
function hideApptHero() {
  if (!apptHero) return; // profile.html gibi sayfalarda #apptHero olmayabilir
  apptHero.hidden = true;
  heroSec.classList.remove("has-appt");
  resumeHeroVideo();
}

/* ====== KAYIT TASLAĞI KONTROLÜ + HERO CTA ====== */
function hasSignupDraft() {
  try {
    const s = JSON.parse(localStorage.getItem("wb_signup_store") || "{}");
    return !!s.step;
  } catch {
    return false;
  }
}
function ensureResumeCTA(user) {
  const heroOv = document.getElementById("heroOverlay");
  if (!heroOv) return;
  // auth.js zaten CTA koyduysa (resumeSignupBtn) tekrar koymayalım
  if (document.getElementById("resumeSignupBtn")) {
    // Bizim eski CTA varsa temizle
    const old = document.getElementById("resumeSignupCTA");
    if (old) old.remove();
    return;
  }

  let cta = document.getElementById("resumeSignupCTA");
  const shouldShow = !user && hasSignupDraft();

  if (shouldShow) {
    if (!cta) {
      cta = document.createElement("button");
      cta.id = "resumeSignupCTA";
      cta.type = "button";
      cta.className = "resume-cta";
      cta.innerHTML =
        '<i class="fas fa-play-circle" aria-hidden="true"></i><span>Kayda devam et</span>';
      const anchor = heroOv.querySelector(".search-box");
      if (anchor) heroOv.insertBefore(cta, anchor);
      else heroOv.appendChild(cta);

      cta.addEventListener("click", async () => {
        try {
          if (!window.__authLoaded) {
            window.__authLoaded = true;
            await import("./auth.js");
            document.dispatchEvent(new Event("auth:ready"));
          }
        } catch {}
        if (window.AuthFlow?.resumeSignup) {
          window.AuthFlow.resumeSignup();
        } else {
          ensureAuthModal();
          openModal("authModal");
        }
      });
    }
  } else if (cta) {
    cta.remove();
  }

  if (!document.getElementById("wb-resume-cta-style")) {
    const st = document.createElement("style");
    st.id = "wb-resume-cta-style";
    st.textContent = `
      .resume-cta{display:inline-flex;align-items:center;gap:8px;padding:10px 16px;border:0;border-radius:999px;background:#0ea5b3;color:#fff;font-weight:800;box-shadow:0 4px 14px rgba(0,0,0,.2);margin:0 0 12px 0;cursor:pointer}
      .resume-cta i{font-size:16px}
      .resume-cta:hover{filter:brightness(1.05)}
      #heroOverlay .search-box{margin-top:6px}
    `;
    document.head.appendChild(st);
  }
}
document.addEventListener("signup:completed", () =>
  ensureResumeCTA(_sessionUser)
);

/* ===== auth durumuna göre üstteki butonları güncelle ===== */
function bindAuthButtons() {
  $$(".profile.open-auth").forEach((el) => {
    el._wbBoundAuth = true;
  });
}

function unbindAuthButton(el) {
  if (!el) return;
  delete el._wbBoundAuth;
}

function updateAuthButtons(user) {
  const els = $$(".profile");
  const isMobile = window.innerWidth <= 767;

  els.forEach((el) => {
    const textEl = el.querySelector(".auth-text") || el.querySelector("span");
    const isHeroBtn = !!el.closest(".hero-navbar-right");

    if (user) {
      // PROFIL MODU
      if (isHeroBtn && isMobile) {
        // Mobil: hero butonunu gizle
        el.hidden = true;
        el.setAttribute("aria-hidden", "true");
        return;
      }
      // Desktop hero veya navbar: "Profilim" olarak göster, profile'a git
      if (isHeroBtn) {
        el.hidden = false;
        el.removeAttribute("aria-hidden");
      }
      textEl && (textEl.textContent = "Profilim");
      if (el._wbBoundAuth) unbindAuthButton(el);
      el.classList.remove("open-auth");
      el.setAttribute("data-goto-profile", "1");
      el.setAttribute("aria-label", "Profilim");
    } else {
      // AUTH MODU
      if (isHeroBtn) {
        el.hidden = false;
        el.removeAttribute("aria-hidden");
      }
      textEl && (textEl.textContent = "Giriş Yap / Kayıt Ol");
      el.classList.add("open-auth");
      el.removeAttribute("data-goto-profile");
      el.setAttribute("aria-label", "Giriş Yap / Kayıt Ol");
    }
  });
  ensureResumeCTA(user);

  // Sadece girişli DEĞİLKEN open-auth butonlarını bağla
  if (!user) bindAuthButtons();
}

/* Session kontrolü ile auth init */
async function initSessionAuth() {
  try {
    const user = await checkSession();
    updateAuthButtons(user);

    // Sadece 'user' rolündeki müşterilerin randevusu gösterilir
    if (!user || user.role !== 'user') {
      hideApptHero();
      emitHeroReadyOnce();
      return;
    }

    try {
      const res  = await fetch('/api/user/appointments/next.php', { credentials: 'same-origin' });
      const json = res.ok ? await res.json() : { ok: false };


      if (json.ok && hasValidUpcomingAppointment(json.data)) {
        const d = json.data;
        if (!d.start && d.startISO) d.start = d.startISO;
        if (!d.end   && d.endISO)   d.end   = d.endISO;
        if (!d.serviceTitle) d.serviceTitle = d.serviceName || d.service_title || 'Randevu';

        const loc = await getBusinessLoc(d.businessId);
        showApptHero(d, loc);
      } else {
        hideApptHero();
      }
    } catch (e) {
      console.warn('[Webey] appointments/next error:', e);
      hideApptHero();
    }

    emitHeroReadyOnce();
  } catch (e) {
    console.warn('[Webey] initSessionAuth error:', e);
    emitHeroReadyOnce();
  } finally {
    markGateDone("auth");
  }
}
initSessionAuth();

/* Kayıt/giriş sonrası güncelle */
document.addEventListener("user:loggedin", () => initSessionAuth());
document.addEventListener("user:loggedout", () => { _sessionUser = null; _idxCsrfToken = null; window.__csrfToken = null; updateAuthButtons(null); hideApptHero(); });
document.addEventListener("auth:userChanged", () => initSessionAuth());

/* =========================================================
   AUTH küçük UI yardımcıları
========================================================= */
function maskTRPhone(v) {
  const d = v.replace(/\D/g, "").slice(0, 10);
  const p1 = d.slice(0, 3),
    p2 = d.slice(3, 6),
    p3 = d.slice(6, 8),
    p4 = d.slice(8, 10);
  let out = "";
  if (p1) out += p1;
  if (p2) out += " " + p2;
  if (p3) out += " " + p3;
  if (p4) out += " " + p4;
  return { masked: out, raw: d };
}
$$('input[data-phone]').forEach((inp) => {
  const enforce = () => {
    inp.value = maskTRPhone(inp.value).masked;
  };
  inp.addEventListener("input", enforce);
  inp.addEventListener("blur", enforce);
});

/* Şifre göz butonu — auth.js initEyes() doğrudan bağlıyor, buradan kaldırıldı.
   İki handler çakışırsa birisi password→text, diğeri text→password yapıyor; net sıfırlanıyor.
   auth.js lazy-import SONRA yükleniyor ve initEyes her .toggle-eye butonunu kapsamakta. */

/* ---- Hero video fallback ---- */
heroVideo?.addEventListener("loadedmetadata", () => {
  emitHeroReadyOnce();
});
setTimeout(() => emitHeroReadyOnce(), 1500);

/* =========================================================
   ARAMA ALANLARI + SB ZAMAN MODALI (parametreli yönlendirme)
========================================================= */

/* ---- Yardımcılar ---- */
const navQ = document.querySelector(
  '.search-section input[aria-label="Hizmet veya işletme ara"]'
);
const navPlace = document.querySelector(
  '.search-section input[aria-label="Konum"]'
);
const navWhen = document.querySelector(
  '.search-section input[aria-label="Zaman"]'
);

const heroQ = document.querySelector("#heroOverlay .search-box input");

let currentWhen = null; // { start: ISO, end: ISO }

/* Kullanıcıya okunabilir etiket */
function labelForWhen({ start, end }) {
  try {
    const s = new Date(start),
      e = end ? new Date(end) : null;
    const sameDay = e && s.toDateString() === e.toDateString();
    const day = `${pad(s.getDate())} ${MON[s.getMonth()]}`;
    const sHM = `${pad(s.getHours())}:${pad(s.getMinutes())}`;
    const eHM = e ? `${pad(e.getHours())}:${pad(e.getMinutes())}` : "";
    return e
      ? sameDay
        ? `${day} • ${sHM}–${eHM}`
        : `${day} ${sHM} → ${pad(e.getDate())} ${MON[e.getMonth()]} ${eHM}`
      : `${day} • ${sHM}`;
  } catch {
    return "Seçildi";
  }
}

/* Basit yer ayrıştırma (fallback) */
function parsePlaceInput(raw = "") {
  const txt = (raw || "").trim();
  if (!txt) return {};
  const hitIlce = districts.find((d) =>
    new RegExp(`\\b${d}\\b`, "i").test(txt)
  );
  if (/istanbul|i̇stanbul/i.test(txt) && hitIlce) {
    return { il: "İstanbul", ilce: hitIlce };
  }
  if (/istanbul|i̇stanbul/i.test(txt)) return { il: "İstanbul" };
  return { il: txt };
}

/* Parametreli yönlendirme */
function goList(params) {
  const url = "kuafor.html?" + new URLSearchParams(params).toString();
  window.location.href = url;
}
function submitSearch({ q, place, when }) {
  const p = {};
  if (q) p.q = q.trim();
  const sel = __chosenPlace || place || parsePlaceInput(navPlace?.value || "");
  if (sel?.il) p.il = sel.il;
  if (sel?.ilce) p.ilce = sel.ilce;
  if (sel?.mahalle) p.mahalle = sel.mahalle;
  if (when?.start) p.start = when.start;
  if (when?.end) p.end = when.end;
  goList(p);
}

/* ---- URL'den zaman parametresi okuyup navbara yaz (kuafor.html için de çalışır) ---- */
function syncListAllLink() {
  const a = document.getElementById("listAllBtn");
  if (!a) return;
  const p = new URLSearchParams();
  if (currentWhen?.start) {
    p.set("start", currentWhen.start);
    if (currentWhen.end) p.set("end", currentWhen.end);
  }
  a.href = "kuafor.html" + (p.toString() ? "?" + p.toString() : "");
}
(function applyWhenFromUrlIfAny() {
  try {
    const sp = new URLSearchParams(location.search);
    const s = sp.get("start");
    const e = sp.get("end");
    if (s) {
      currentWhen = { start: s, end: e || null };
      if (navWhen) navWhen.value = labelForWhen(currentWhen);
      syncListAllLink();
    }
  } catch {}
})();

/* =========================================================
   SB TARİH/SAAT MODALİ (a11y + odak tuzaklama ile)
========================================================= */
let sbDateState = {
  monthAnchor: new Date(), // gösterilen ay (1.gün)
  selectedDate: null, // YYYY-MM-DD
  selectedTime: null // "HH:MM"
};
let __sbOverlayFocusBack = null;

function startOfMonth(d) {
  const x = new Date(d);
  x.setDate(1);
  x.setHours(0, 0, 0, 0);
  return x;
}
function ymd(d) {
  return d.toISOString().slice(0, 10);
}
function toISO(ds, ts) {
  // local → ISO
  const [hh, mm] = ts.split(":").map((n) => parseInt(n, 10));
  const d = new Date(`${ds}T00:00:00`);
  d.setHours(hh || 0, mm || 0, 0, 0);
  return d.toISOString();
}
function ensureSBDateModal() {
  if (document.getElementById("sb-date-overlay")) return;

  const wrap = document.createElement("div");
  wrap.id = "sb-date-overlay";
  wrap.setAttribute("role", "dialog");
  wrap.setAttribute("aria-modal", "true");
  wrap.setAttribute("aria-labelledby", "sb-date-title");
  wrap.setAttribute("aria-hidden", "true"); // kapalıyken erişilemez
  wrap.innerHTML = `
    <div class="sb-date-box">
      <button id="sb-date-close" aria-label="Kapat"><i class="fas fa-times"></i></button>
      <div class="sb-date-head">
        <button class="nav" data-nav="-1" aria-label="Önceki Ay"><i class="fas fa-chevron-left"></i></button>
        <div class="month" id="sb-date-title"></div>
        <button class="nav" data-nav="1" aria-label="Sonraki Ay"><i class="fas fa-chevron-right"></i></button>
      </div>
      <div class="days-head" aria-hidden="true">${DOW.map(
        (x) => `<span>${x}</span>`
      ).join("")}</div>
      <div class="grid" id="sb-days"></div>
      <div class="chips" id="sb-times"></div>
      <div class="actions">
        <button class="clear">Temizle</button>
        <button class="ok">Tamam</button>
      </div>
    </div>
  `;
  document.body.appendChild(wrap);

  // Delegated events
  wrap.addEventListener(
    "click",
    (e) => {
      const t = e.target;
      // dışa tıklama
      if (t === wrap) {
        closeSBDateOverlay();
        return;
      }
      // kapat
      if (t.id === "sb-date-close") {
        closeSBDateOverlay();
        return;
      }
      // ay navigasyonu
      const navBtn = t.closest?.(".nav");
      if (navBtn) {
        shiftMonth(parseInt(navBtn.dataset.nav, 10) || 0);
      }
      // gün seçimi
      const dayBtn = t.closest?.("button[data-date]");
      if (dayBtn) {
        sbDateState.selectedDate = dayBtn.dataset.date;
        renderDays();
        renderTimes();
      }
      // saat seçimi
      const chipsBtn = t.closest?.(".chips button");
      if (chipsBtn) {
        sbDateState.selectedTime = chipsBtn.dataset.time;
        $$("#sb-times .chips-btn").forEach((b) =>
          b.classList.toggle("active", b.dataset.time === sbDateState.selectedTime)
        );
      }
      // temizle
      if (t.closest?.(".actions .clear")) {
        sbDateState.selectedDate = null;
        sbDateState.selectedTime = null;
        renderDays();
        renderTimes();
      }
      // onay
      if (t.closest?.(".actions .ok")) {
        if (!sbDateState.selectedDate || !sbDateState.selectedTime) return;
        const startISO = toISO(
          sbDateState.selectedDate,
          sbDateState.selectedTime
        );
        const endISO = new Date(
          new Date(startISO).getTime() + 60 * 60 * 1000
        ).toISOString();
        currentWhen = { start: startISO, end: endISO };
        if (navWhen) navWhen.value = labelForWhen(currentWhen);
        syncListAllLink();

        // Parametreleri derle → kuafor.html
        const p = {};
        const sel =
          __chosenPlace || parsePlaceInput(navPlace?.value || "");
        if (sel?.il) p.il = sel.il;
        if (sel?.ilce) p.ilce = sel.ilce;
        if (sel?.mahalle) p.mahalle = sel.mahalle;
        p.start = startISO;
        p.end = endISO;

        closeSBDateOverlay();
        window.location.href =
          "kuafor.html?" + new URLSearchParams(p).toString();
      }
    },
    { passive: false }
  );

  // Odak tuzağı
  wrap.addEventListener(
    "keydown",
    (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        closeSBDateOverlay();
        return;
      }
      if (e.key !== "Tab") return;
      const focusables = Array.from(wrap.querySelectorAll(FOCUSABLE)).filter(
        (el) => el.offsetParent !== null
      );
      if (!focusables.length) return;
      const first = focusables[0],
        last = focusables[focusables.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    },
    { passive: false }
  );
}
function openSBDateOverlay() {
  ensureSBDateModal();
  const ov = document.getElementById("sb-date-overlay");
  // Anchor ay/ seçim reset
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  sbDateState.monthAnchor = startOfMonth(today);
  if (!sbDateState.selectedDate) {
    sbDateState.selectedTime = null;
  }
  renderMonthTitle();
  renderDays();
  renderTimes();

  __sbOverlayFocusBack =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  ov.classList.add("open");
  ov.setAttribute("aria-hidden", "false"); // görünür
  addBodyLock();

  // İlk odak: kapat butonu
  setTimeout(() => {
    $("#sb-date-close")?.focus({ preventScroll: true });
  }, 0);
}
function closeSBDateOverlay() {
  const ov = document.getElementById("sb-date-overlay");
  if (!ov) return;
  // önce odakı dışarı taşı
  document.body.focus?.();
  ov.classList.remove("open");
  ov.setAttribute("aria-hidden", "true");
  removeBodyLock();
  // geri odak
  if (__sbOverlayFocusBack && document.contains(__sbOverlayFocusBack)) {
    __sbOverlayFocusBack.focus({ preventScroll: true });
  }
}
function shiftMonth(delta) {
  const d = startOfMonth(sbDateState.monthAnchor);
  d.setMonth(d.getMonth() + delta);
  // geçmişe gitme engeli (bugünden önceki ayları kapat)
  const today = startOfMonth(new Date());
  if (d < today) {
    sbDateState.monthAnchor = today;
  } else {
    sbDateState.monthAnchor = d;
  }
  renderMonthTitle();
  renderDays();
  renderTimes();
}
function renderMonthTitle() {
  const title = $("#sb-date-title");
  const d = sbDateState.monthAnchor;
  title.textContent = `${MON[d.getMonth()]} ${d.getFullYear()}`;
}
function renderDays() {
  const grid = $("#sb-days");
  if (!grid) return;
  const d0 = startOfMonth(sbDateState.monthAnchor);
  const firstDow = (d0.getDay() + 7) % 7; // 0=Paz
  const daysInMonth = new Date(
    d0.getFullYear(),
    d0.getMonth() + 1,
    0
  ).getDate();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const minDate = today; // bugün ve sonrası

  const cells = [];
  for (let i = 0; i < firstDow; i++) cells.push(`<span></span>`);
  for (let day = 1; day <= daysInMonth; day++) {
    const d = new Date(d0);
    d.setDate(day);
    const disabled = d < minDate;
    const ds = ymd(d);
    const active = sbDateState.selectedDate === ds;
    cells.push(
      disabled
        ? `<span aria-disabled="true"></span>`
        : `<button type="button" data-date="${ds}" class="${
            active ? "active" : ""
          }" aria-pressed="${active ? "true" : "false"}">${pad(
            day
          )}</button>`
    );
  }
  grid.innerHTML = cells.join("");
}
function renderTimes() {
  const box = $("#sb-times");
  if (!box) return;
  const selDate = sbDateState.selectedDate;
  if (!selDate) {
    box.innerHTML =
      '<div class="info-card" style="width:100%">Lütfen önce gün seçin.</div>';
    return;
  }
  // Slotlar: 09-15 ve 16-21 (1 saatlik)
  const hours = [9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20];
  const chips = hours
    .map((h) => {
      const t = `${pad(h)}:00`;
      const active = sbDateState.selectedTime === t;
      return `<button type="button" class="chips-btn ${
        active ? "active" : ""
      }" data-time="${t}">${t}</button>`;
    })
    .join("");
  box.innerHTML = chips;
}

/* =========================================================
   ANLIK ARAMA ÖNERİLERİ — SABİT PANEL + KONUM ÖNERİLERİ
========================================================= */
const trMap = {
  Ç: "c",
  ç: "c",
  Ğ: "g",
  ğ: "g",
  İ: "i",
  I: "i",
  ı: "i",
  Ö: "o",
  ö: "o",
  Ş: "s",
  ş: "s",
  Ü: "u",
  ü: "u"
};
const trNorm = (s = "") =>
  s.replace(/[ÇçĞİIıÖöŞşÜü]/g, (m) => trMap[m] || m).toLowerCase();
const slugify = (s = "") =>
  trNorm(s).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");

let salonIndexLoaded = false;
let salonIndex = []; // [{id,name,loc:{...}}]
let serviceIndex = []; // unique array of service names
async function ensureSalonIndex() {
  if (salonIndexLoaded) return;
  try {
    const items = await loadDirectoryBusinesses();

    const svcSet = new Set();
    salonIndex = items.map(r => {
      const name = String(r.name || '').trim();
      // Hizmetleri topla
      if (Array.isArray(r.services)) {
        r.services.forEach(s => {
          const n = String(s?.name || s || '').trim();
          if (n) svcSet.add(n);
        });
      }
      return name ? {
        id: r.id || r.businessId || r.uid,
        name,
        loc: {
          province: r.businessLocation?.province || r.businessLocation?.city || r.city || r.province || '',
          district: r.businessLocation?.district || r.district || '',
          neighborhood: r.businessLocation?.neighborhood || r.neighborhood || '',
        }
      } : null;
    }).filter(Boolean);

    serviceIndex = Array.from(svcSet).sort((a, b) => trNorm(a).localeCompare(trNorm(b)));
  } catch (err) {
    console.warn("[suggest] index alınamadı:", err);
    salonIndex = []; serviceIndex = [];
  } finally {
    salonIndexLoaded = true;
  }
}

/* ---------- KONUM İNDEKSİ (İl / İlçe / Mahalle) ---------- */
let placeIndexLoaded = false;
let placeCombos = []; // {il, ilce?, mahalle?, label, tier}
let __chosenPlace = null;

async function ensurePlaceIndex() {
  if (placeIndexLoaded) return;
  try {
    if (!salonIndexLoaded) await ensureSalonIndex();
    const seen = new Set();

    for (const s of salonIndex) {
      const il = s.loc?.province || s.loc?.city || "";
      if (!il) continue;
      const key1 = `${il}|`;
      if (!seen.has(key1)) {
        seen.add(key1);
        placeCombos.push({ il, label: il, tier: 1 });
      }
      const ilce = s.loc?.district || "";
      if (ilce) {
        const key2 = `${il}|${ilce}|`;
        if (!seen.has(key2)) {
          seen.add(key2);
          placeCombos.push({
            il,
            ilce,
            label: `${il} • ${ilce}`,
            tier: 2
          });
        }
        const mah = s.loc?.neighborhood || "";
        if (mah) {
          const key3 = `${il}|${ilce}|${mah}`;
          if (!seen.has(key3)) {
            seen.add(key3);
            placeCombos.push({
              il,
              ilce,
              mahalle: mah,
              label: `${il} • ${ilce} • ${mah}`,
              tier: 3
            });
          }
        }
      }
    }

    placeCombos.sort((a, b) => {
      if (b.tier !== a.tier) return b.tier - a.tier;
      return trNorm(a.label).localeCompare(trNorm(b.label));
    });
  } catch (e) {
    console.warn("[place] index error:", e);
  } finally {
    placeIndexLoaded = true;
  }
}

/* --- Tether helper: paneli input’un altına sabitle --- */
let activeAnchor = null;
let tetherHandlers = null;
function placeBoxToAnchor(box, anchor) {
  if (!box || !anchor) return;
  const r = (
    anchor.getBoundingClientRect ? anchor : anchor.querySelector("input")
  ).getBoundingClientRect();
  // box.style.position = 'fixed' → viewport koordinatları kullan (scrollY YOK)
  const top = Math.round(r.bottom + 6);
  const left = Math.round(r.left);
  const w = Math.max(r.width, 280);
  const maxH = Math.max(
    160,
    window.innerHeight - top - 24
  );
  box.style.top = top + "px";
  box.style.left = left + "px";
  box.style.width = w + "px";
  box.style.maxHeight = maxH + "px";
}
function attachTether(box, anchor) {
  detachTether();
  activeAnchor = anchor;
  const place = () => placeBoxToAnchor(box, anchor);
  place();
  const ro = new ResizeObserver(place);
  ro.observe(document.documentElement);
  ro.observe(anchor);
  const onScroll = () => place();
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);
  tetherHandlers = { ro, onScroll };
}
function detachTether() {
  if (!tetherHandlers) return;
  try {
    tetherHandlers.ro.disconnect();
  } catch {}
  window.removeEventListener("scroll", tetherHandlers.onScroll);
  window.removeEventListener("resize", tetherHandlers.onScroll);
  tetherHandlers = null;
  activeAnchor = null;
}

/* --- Öneri UI --- */
function makeSuggestUI() {
  let box = document.getElementById("suggestBox");
  if (box) return box;
  box = document.createElement("div");
  box.id = "suggestBox";
  box.className = "search-pop";
  box.setAttribute("role", "listbox");
  box.style.display = "none";
  box.style.position = "fixed";
  box.style.zIndex = "999999";
  box.innerHTML = `
    <div class="sg-head group-title">Sonuçlar</div>
    <div class="sg-wrap"></div>
  `;
  document.body.appendChild(box);
  return box;
}
function renderSuggest(items, anchorInput) {
  const box = makeSuggestUI();
  const wrap = box.querySelector(".sg-wrap");
  wrap.innerHTML = "";

  const mkSection = (title, arr) => {
    if (!arr.length) return;
    const sec = document.createElement("div");
    sec.innerHTML = `<div class="group-title" style="padding:8px 12px;">${title}</div>`;
    arr.forEach((it) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "item sg-row";
      row.setAttribute("role", "option");
      row.setAttribute("data-type", it.type);
      row.setAttribute("data-name", it.label);
      if (it.id) row.setAttribute("data-id", it.id);
      if (it.il) row.setAttribute("data-il", it.il);
      if (it.ilce) row.setAttribute("data-ilce", it.ilce);
      if (it.mahalle) row.setAttribute("data-mahalle", it.mahalle);
      row.innerHTML = `<i class="${it.icon}" aria-hidden="true"></i><span>${it.label}</span>`;
      sec.appendChild(row);
    });
    wrap.appendChild(sec);
  };

  const by = { service: [], business: [], place: [] };
  items.forEach((x) => (by[x.type] ?? (by[x.type] = [])).push(x));
  mkSection("KONUM", by.place);
  mkSection("HİZMETLER", by.service);
  mkSection("İŞLETMELER", by.business);

  if (items.length) {
    box.style.display = "block";
    attachTether(box, anchorInput.closest(".search-box") || anchorInput);
    addBodyLock();
  } else {
    box.style.display = "none";
    detachTether();
    removeBodyLock();
  }
}

/* dışarıdan kapatma */
function hideSuggest() {
  const b = document.getElementById("suggestBox");
  if (b) {
    b.style.display = "none";
  }
  detachTether();
  removeBodyLock();
}

/* ---------- Hizmet/İşletme typeahead (opsiyonlu: konum göster/gizle) ---------- */
function attachSuggest(input, opts = { allowPlaces: true }) {
  if (!input) return;
  let lastVal = "";
  const DEBOUNCE = 80;
  let t;
  const run = async () => {
    const v = (input.value || "").trim();
    if (v === lastVal) {
      placeBoxToAnchor(
        document.getElementById("suggestBox"),
        input.closest(".search-box") || input
      );
      return;
    }
    lastVal = v;
    if (!v) {
      hideSuggest();
      return;
    }
    await ensureSalonIndex();
    await ensurePlaceIndex();

    const tokens = trNorm(v).split(/\s+/).filter(Boolean);
    if (!tokens.length) {
      hideSuggest();
      return;
    }

    const svc = [];
    for (const s of serviceIndex) {
      const ns = trNorm(s);
      const ok = tokens.every((tk) => ns.includes(tk));
      if (ok) svc.push({ type: "service", label: s, icon: "fas fa-scissors" });
      if (svc.length >= 8) break;
    }

    const biz = [];
    for (const b of salonIndex) {
      const nb = trNorm(b.name);
      const ok = tokens.every((tk) => nb.includes(tk));
      if (ok) biz.push({ type: "business", label: b.name, id: b.id, icon: "fas fa-store" });
      if (biz.length >= 8) break;
    }

    const plc = [];
    if (opts.allowPlaces) {
      for (const p of placeCombos) {
        const hay = trNorm(
          [p.il, p.ilce, p.mahalle].filter(Boolean).join(" ")
        );
        const ok = tokens.every((tk) => hay.includes(tk));
        if (ok)
          plc.push({
            type: "place",
            label: p.label,
            il: p.il,
            ilce: p.ilce,
            mahalle: p.mahalle,
            icon: "fas fa-location-dot",
            tier: p.tier
          });
        if (plc.length >= 10) break;
      }
      plc.sort(
        (a, b) =>
          b.tier - a.tier ||
          trNorm(a.label).localeCompare(trNorm(b.label))
      );
    }

    renderSuggest([...plc, ...svc, ...biz], input);
  };

  input.addEventListener("input", () => {
    clearTimeout(t);
    t = setTimeout(run, DEBOUNCE);
  });
  input.addEventListener("focus", () => {
    lastVal = "";
    run();
  });
  input.addEventListener("blur", () => setTimeout(hideSuggest, 250));

  const box = makeSuggestUI();
  if (!box._boundClick) {
    box._boundClick = true;
    box.addEventListener(
      "pointerdown",
      (e) => {
        const row = e.target.closest(".sg-row");
        if (!row) return;
        e.preventDefault();
        e.stopPropagation();
        const type = row.dataset.type;
        const name = row.dataset.name;

        if (type === "service") {
          const params = new URLSearchParams({
            service: name,
            serviceSlug: slugify(name),
            q: name
          });
          if (currentWhen?.start) {
            params.set("start", currentWhen.start);
            params.set("end", currentWhen.end);
          }
          window.location.assign(`kuafor.html?${params.toString()}`);
        } else if (type === "business") {
          const id = row.dataset.id;
          if (id) window.location.assign(`profile.html?id=${encodeURIComponent(id)}`);
        } else if (type === "place") {
          const il = row.dataset.il || "";
          const ilce = row.dataset.ilce || "";
          const mahalle = row.dataset.mahalle || "";

          // Konum önerisine tıklayınca HER ZAMAN listeye git
          const params = new URLSearchParams();
          if (il) params.set("il", il);
          if (ilce) params.set("ilce", ilce);
          if (mahalle) params.set("mahalle", mahalle);
          if (currentWhen?.start) {
            params.set("start", currentWhen.start);
            params.set("end", currentWhen.end);
          }
          const qVal = (navQ?.value || heroQ?.value || "").trim();
          if (qVal) params.set("q", qVal);

          window.location.assign(
            `kuafor.html?${params.toString()}`
          );
        }
        hideSuggest();
      },
      { passive: false }
    );
  }

  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") hideSuggest();
  });
}

/* ---------- SADECE KONUM alani için hafif typeahead ---------- */
function attachPlaceSuggest(input) {
  if (!input) return;
  let last = "";
  let t;
  const DEBOUNCE = 80;

  const run = async () => {
    const q = (input.value || "").trim();
    if (q === last) {
      placeBoxToAnchor(
        document.getElementById("suggestBox"),
        input.closest(".search-box") || input
      );
      return;
    }
    last = q;
    await ensurePlaceIndex();
    if (!q) {
      const top = placeCombos
        .filter((p) => p.tier === 3)
        .slice(0, 8)
        .map((p) => ({
          type: "place",
          label: p.label,
          il: p.il,
          ilce: p.ilce,
          mahalle: p.mahalle,
          icon: "fas fa-location-dot",
          tier: p.tier
        }));
      renderSuggest(top, input);
      return;
    }
    const tokens = trNorm(q).split(/\s+/).filter(Boolean);
    const plc = [];
    for (const p of placeCombos) {
      const hay = trNorm(
        [p.il, p.ilce, p.mahalle].filter(Boolean).join(" ")
      );
      const ok = tokens.every((tk) => hay.includes(tk));
      if (ok)
        plc.push({
          type: "place",
          label: p.label,
          il: p.il,
          ilce: p.ilce,
          mahalle: p.mahalle,
          icon: "fas fa-location-dot",
          tier: p.tier
        });
      if (plc.length >= 12) break;
    }
    plc.sort(
      (a, b) =>
        b.tier - a.tier ||
        trNorm(a.label).localeCompare(trNorm(b.label))
    );
    renderSuggest(plc, input);
  };

  input.addEventListener("input", () => {
    __chosenPlace = null;
    clearTimeout(t);
    t = setTimeout(run, DEBOUNCE);
  });
  input.addEventListener("focus", () => {
    last = "";
    run();
  });
  input.addEventListener("blur", () => setTimeout(hideSuggest, 250));
}

/* ---- Arama alanlarını bağla ---- */
function bindSearchBars() {
  [navQ, navPlace].forEach((inp) => {
    inp?.addEventListener(
      "keydown",
      (e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          const q = navQ?.value || "";
          submitSearch({ q, when: currentWhen });
        }
      },
      { passive: false }
    );
  });

  if (navWhen) {
    navWhen.readOnly = true;

    const openTime = (e) => {
      e.preventDefault();
      e.stopPropagation();
      openSBDateOverlay();
    };
    navWhen.addEventListener("click", openTime);
    navWhen.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        openTime(e);
      }
    });
    // Mobilde native picker tetiklenmesini engelle
    navWhen.addEventListener("mousedown", (e) => {
      e.preventDefault();
    });
  }

  heroQ?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const q = heroQ.value || "";
      submitSearch({ q, when: currentWhen });
    }
  });

  // Navbar ilk bar → konum gösterme yok
  attachSuggest(navQ, { allowPlaces: false });
  // Hero arama → konum dahil
  attachSuggest(heroQ, { allowPlaces: true });
  // Navbar “Neresi?” → konuma tıklayınca doğrudan yönlendirme
  attachPlaceSuggest(navPlace);

  const onRelayout = () => {
    const box = document.getElementById("suggestBox");
    if (box && box.style.display !== "none" && activeAnchor) {
      placeBoxToAnchor(
        box,
        activeAnchor.closest?.(".search-box") || activeAnchor
      );
    }
  };
  window.addEventListener("scroll", onRelayout, { passive: true });
  window.addEventListener("resize", onRelayout);

  // ── Hero searchbar sticky ──────────────────────────────────────────────
  // Hero section içindeki search-box, hero ekrandan çıkarken sabit kalır.
  const heroSection = document.getElementById("heroSec");
  const heroSearchBox = document.querySelector("#heroOverlay .search-box");
  if (heroSection && heroSearchBox) {
    let heroSticky = false;
    const toggleHeroSticky = () => {
      const heroBottom = heroSection.getBoundingClientRect().bottom;
      const shouldStick = heroBottom < 80; // hero neredeyse çıktıysa
      if (shouldStick !== heroSticky) {
        heroSticky = shouldStick;
        heroSearchBox.classList.toggle("hero-search-sticky", heroSticky);
        // suggest box'u yeniden konumlandır
        const sb = document.getElementById("suggestBox");
        if (sb && sb.style.display !== "none") {
          placeBoxToAnchor(sb, heroSearchBox);
        }
      }
    };
    window.addEventListener("scroll", toggleHeroSticky, { passive: true });
    toggleHeroSticky(); // sayfa yüklenmesinde kontrol et
  }
  // ──────────────────────────────────────────────────────────────────────
}

/* ---- ÖNEMLİ: Kuaför listesinde çakışmayı engelle ---- */
if (!window.WB_DISABLE_NAV_SUGGEST) {
  bindSearchBars();
} else {
  hideSuggest();
}

/* =========================================================
   MOBİL INTRO (bir kere en aşağıdan yukarı scroll + ipucu)
========================================================= */
function showScrollHintOnce() {
  const host = document.getElementById("heroSec");
  if (!host || document.getElementById("wbScrollHint")) return;
  const hint = document.createElement("div");
  hint.id = "wbScrollHint";
  hint.className = "scroll-hint";
  hint.setAttribute("aria-hidden", "true");
  hint.innerHTML = '<i class="fas fa-chevron-down"></i>';
  host.appendChild(hint);

  const clear = () => {
    try {
      hint.remove();
    } catch {}
  };
  const onScroll = () => {
    if (window.scrollY > 32) {
      clear();
      window.removeEventListener("scroll", onScroll);
    }
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  setTimeout(() => {
    clear();
    window.removeEventListener("scroll", onScroll);
  }, 3000);
}

/* **GÜNCELLEME**: Mobilde sayfaya ilk girişte bir kez alttan üste yavaş kaydır (reduce-motion saygılı) */
function runMobileIntro() {
  if (!isMobileLike()) return;

  // Hareket kısıtına saygı
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Bu animasyon bir kez çalışsın
  if (sessionStorage.getItem("wb_intro_done_scroll") || reduce) {
    showScrollHintOnce();
    // intro animasyonu için sınıf (poster modunda da çalışır)
    heroVideo?.classList.add("bounce-intro");
    return;
  }

  // Önce en alta git (anlık), sonra yukarı doğru smooth kaydır
  setTimeout(() => {
    try {
      window.scrollTo(0, document.body.scrollHeight);
      setTimeout(() => {
        window.scrollTo({ top: 0, behavior: "smooth" });
      }, 250);
    } catch {}
  }, 400);

  sessionStorage.setItem("wb_intro_done_scroll", "1");
  heroVideo?.classList.add("bounce-intro");
  showScrollHintOnce();
}
document.addEventListener("hero:ready", runMobileIntro, { once: true });

/* =========================================================
   ÖNERİLENLER (Recommended)
========================================================= */
const recTrack = document.getElementById("recommendedContainer");
const recBtnL = document.querySelector(".rec-viewport .scroll-btn.left");
const recBtnR = document.querySelector(".rec-viewport .scroll-btn.right");

/* ---- Yardımcılar ---- */
function shortAddr(loc = {}) {
  const bits = [loc.district, loc.province || loc.city].filter(Boolean);
  return bits.join(" • ");
}

/* ---- URL çözümleyici: uploads/ relative path destekli ---- */
function resolveImageUrl(u) {
  if (!u) return null;
  if (/^https?:\/\//i.test(u)) return u;
  // "uploads/biz/10/..." gibi relative path → sayfa base'ine ekle
  if (u.startsWith("uploads/") || u.startsWith("upload/")) {
    const base = window.location.pathname.replace(/\/[^/]*$/, "/");
    return base + u;
  }
  return null; // bilinmeyen format → fallback kullan
}

/* ---- API'dan en uygun resmi seç ---- */
function resolveMediaUrl(input) {
  const s = String(input || "").trim();
  if (!s) return null;
  try {
    const url = /^https?:\/\//i.test(s)
      ? new URL(s)
      : new URL(s.replace(/^\/+/, ""), `${window.location.origin}/`);
    if (url.protocol === "http:" || url.protocol === "https:") return url.href;
  } catch {}
  return null;
}

function mediaUrlList(input) {
  if (Array.isArray(input)) {
    return input.flatMap(item => mediaUrlList(item)).filter(Boolean);
  }
  if (input && typeof input === "object") {
    const raw = input.url || input.src || input.path || "";
    return raw ? [String(raw).trim()] : [];
  }
  const raw = String(input || "").trim();
  return raw ? [raw] : [];
}

function buildRecommendedGalleryEntries(it) {
  const originals = [
    ...mediaUrlList(it.images?.cover).slice(0, 1),
    ...mediaUrlList(it.images?.salon).slice(0, 1),
    ...mediaUrlList(it.images?.model).slice(0, 1),
  ];
  const preferred = [
    ...mediaUrlList(it.images?.cover_opt).slice(0, 1),
    ...mediaUrlList(it.images?.salon_opt).slice(0, 1),
    ...mediaUrlList(it.images?.model_opt).slice(0, 1),
  ];
  const galleryList = Array.isArray(it.gallery) ? it.gallery.slice(0, 3) : [];
  const primary = galleryList.length ? galleryList : preferred;
  const entries = primary.map((src, i) => ({
    src: resolveMediaUrl(src) || resolveImageUrl(src),
    fallback: resolveMediaUrl(originals[i] || src) || resolveImageUrl(originals[i] || src),
  })).filter(item => item.src);

  if (!entries.length) {
    const cover = resolveMediaUrl(pickCoverUrl(it)) || resolveImageUrl(pickCoverUrl(it)) || "img/hero-cover.webp";
    entries.push({ src: cover, fallback: cover });
  }
  return entries;
}

function pickCoverUrl(r) {
  // Önce coverUrl — businesses.php buraya optimize (WebP) versiyonu koyuyor
  if (r.coverUrl) return r.coverUrl;

  // Liste sayfalarında sadece optimize görselleri tercih et
  if (r.images && typeof r.images === "object" && !Array.isArray(r.images)) {
    for (const k of ["cover_opt", "salon_opt", "model_opt", "cover", "salon", "model"]) {
      const v = r.images[k];
      const url = Array.isArray(v) ? v[0] : (typeof v === "string" ? v : null);
      if (url) return url;
    }
  }
  return r.logoUrl || r.cover || r.logo || null;
}

/* ---- min fiyat çıkar ---- */
function extractMinPrice(r) {
  const nums = [r.min_price, r.minPrice, r.startingPrice, r.startPrice]
    .map(Number).filter(x => Number.isFinite(x) && x > 0);
  if (nums.length) return Math.min(...nums);
  if (Array.isArray(r.services)) {
    const ps = r.services.map(s => Number(s?.price ?? s?.minPrice)).filter(x => Number.isFinite(x) && x > 0);
    if (ps.length) return Math.min(...ps);
  }
  return null;
}

/* ---- Tek kart oluştur ---- */
function buildRecCard(it) {
  const esc = s => String(s || "").replace(/[&<>"']/g, m => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
  const loc  = shortAddr(it.loc || {});
  const mp   = extractMinPrice(it);
  const priceHtml = mp ? `<div class="rec-price">₺${Math.round(mp)}'den başlayan</div>` : "";
  const rawCover  = pickCoverUrl(it);
  const coverSrc  = resolveImageUrl(rawCover) || "img/berber1.jpeg";

  const bizId = String(it.id || "");
  

  const wrap = document.createElement("div");
  wrap.className = "rec-card-wrap";
  wrap.dataset.bizId = bizId;

  const a = document.createElement("a");
  a.className = "rec-card";
  a.href = `profile.html?id=${encodeURIComponent(it.id)}`;
  a.setAttribute("aria-label", esc(it.name));
  a.innerHTML = `
    <div class="rec-img-wrap">
      <img loading="lazy" decoding="async"
           src="${esc(coverSrc)}"
           alt="${esc(it.name)} kapak"
           onerror="this.onerror=null;this.src='img/berber1.jpeg'">
    </div>
    <div class="rec-info">
      <h3 class="rec-title">${esc(it.name)}</h3>
      <p class="rec-meta">${esc(loc || "—")}</p>
      ${priceHtml}
    </div>`;

  wrap.appendChild(a);
  return wrap;
}

function buildRecommendedCard(it) {
  const esc = s => String(s || "").replace(/[&<>"']/g, m => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
  const loc = shortAddr(it.loc || {});
  const mp = extractMinPrice(it);
  const priceHtml = mp ? `<div class="rec-price">₺${Math.round(mp)}'den başlayan fiyatlarla</div>` : "";
  const rawGallery = [
    ...mediaUrlList(it.gallery),
    ...mediaUrlList(it.images?.cover),
    ...mediaUrlList(it.images?.salon),
    ...mediaUrlList(it.images?.model),
    pickCoverUrl(it),
  ].filter(Boolean);
  const gallery = [...new Set(rawGallery.map(u => resolveImageUrl(u)).filter(Boolean))].slice(0, 3);
  if (!gallery.length) gallery.push("img/berber1.jpeg");
  const slidesHtml = gallery.map((src, i) =>
    `<img class="rec-slide" src="${i === 0 ? esc(src) : ""}" data-src="${esc(src)}" alt="${esc(it.name)} ${i + 1}" loading="${i === 0 ? "eager" : "lazy"}" decoding="async" style="${i === 0 ? "opacity:1" : "opacity:0;position:absolute;inset:0"}">`
  ).join("");
  const dotsHtml = gallery.length > 1
    ? `<div class="rec-dots" aria-hidden="true">${gallery.map((_, i) => `<span class="rec-dot${i === 0 ? " rec-dot--active" : ""}"></span>`).join("")}</div>`
    : "";

  const wrap = document.createElement("div");
  wrap.className = "rec-card-wrap";
  wrap.dataset.bizId = String(it.id || "");

  const a = document.createElement("a");
  a.className = "rec-card";
  a.href = `profile.html?id=${encodeURIComponent(it.id)}`;
  a.setAttribute("aria-label", esc(it.name));
  a.innerHTML = `
    <div class="rec-img-wrap rec-carousel">
      <div class="rec-slides">
        ${slidesHtml}
      </div>
      ${dotsHtml}
    </div>
    <div class="rec-info">
      <h3 class="rec-title">${esc(it.name)}</h3>
      <p class="rec-meta">${esc(loc || "—")}</p>
      ${priceHtml}
    </div>`;

  wrap.appendChild(a);
  return wrap;
}

function buildRecommendedCardV2(it) {
  const esc = s => String(s || "").replace(/[&<>"']/g, m => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));
  const loc = shortAddr(it.loc || {});
  const mp = extractMinPrice(it);
  const priceHtml = mp ? `<div class="rec-price">₺${Math.round(mp)}'den başlayan fiyatlarla</div>` : "";
  const galleryEntries = buildRecommendedGalleryEntries(it);
  const slidesHtml = galleryEntries.map((entry, i) =>
    `<img class="rec-slide" src="${i === 0 ? esc(entry.src) : ""}" data-src="${esc(entry.src)}" data-fallback="${esc(entry.fallback || entry.src)}" alt="${esc(it.name)} ${i + 1}" loading="${i === 0 ? "eager" : "lazy"}" decoding="async" style="${i === 0 ? "opacity:1" : "opacity:0;position:absolute;inset:0"}" onerror="if(this.dataset.fallback&&this.src!==this.dataset.fallback){this.src=this.dataset.fallback;return;}this.onerror=null;this.src='img/hero-cover.webp'">`
  ).join("");
  const dotsHtml = galleryEntries.length > 1
    ? `<div class="rec-dots" aria-hidden="true">${galleryEntries.map((_, i) => `<span class="rec-dot${i === 0 ? " rec-dot--active" : ""}"></span>`).join("")}</div>`
    : "";

  const wrap = document.createElement("div");
  wrap.className = "rec-card-wrap";
  wrap.dataset.bizId = String(it.id || "");

  const a = document.createElement("a");
  a.className = "rec-card";
  a.href = `profile.html?id=${encodeURIComponent(it.id)}`;
  a.setAttribute("aria-label", esc(it.name));
  a.innerHTML = `
    <div class="rec-img-wrap rec-carousel">
      <div class="rec-slides">
        ${slidesHtml}
      </div>
      ${dotsHtml}
    </div>
    <div class="rec-info">
      <h3 class="rec-title">${esc(it.name)}</h3>
      <p class="rec-meta">${esc(loc || "—")}</p>
      ${priceHtml}
    </div>`;

  wrap.appendChild(a);
  return wrap;
}

function initRecommendedCarousels() {
  if (!recTrack) return;
  recTrack.querySelectorAll(".rec-carousel").forEach((carousel) => {
    const slides = Array.from(carousel.querySelectorAll(".rec-slide"));
    const dots = Array.from(carousel.querySelectorAll(".rec-dot"));
    if (slides.length < 2) return;

    let current = 0;
    let touchStartX = 0;

    const preloadAll = () => {
      slides.forEach((slide) => {
        if (!slide.src && slide.dataset.src) slide.src = slide.dataset.src;
      });
    };

    const goTo = (idx) => {
      const prev = current;
      current = (idx + slides.length) % slides.length;
      if (current === prev) return;
      preloadAll();
      slides[prev].style.opacity = "0";
      slides[prev].style.position = "absolute";
      slides[current].style.opacity = "1";
      slides[current].style.position = current === 0 ? "relative" : "absolute";
      dots.forEach((dot, i) => dot.classList.toggle("rec-dot--active", i === current));
    };

    carousel.addEventListener("mouseenter", preloadAll);
    carousel.addEventListener("touchstart", (e) => {
      preloadAll();
      touchStartX = e.touches[0].clientX;
    }, { passive: true });
    carousel.addEventListener("touchend", (e) => {
      const diff = touchStartX - e.changedTouches[0].clientX;
      if (Math.abs(diff) > 40) goTo(current + (diff > 0 ? 1 : -1));
    }, { passive: true });

    dots.forEach((dot, i) => {
      dot.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        goTo(i);
      });
    });
  });
}

/* ---- Sonsuz (infinite) carousel kur ---- */
function setupInfiniteCarousel(items) {
  if (!recTrack) return;
  if (typeof recTrack.__wbRecommendedCleanup === "function") {
    try { recTrack.__wbRecommendedCleanup(); } catch {}
    recTrack.__wbRecommendedCleanup = null;
  }
  recTrack.innerHTML = "";

  if (!items.length) {
    recTrack.innerHTML = `<div class="rec-empty">Şu an öneri bulunamadı.</div>`;
    if (recBtnL) recBtnL.hidden = true;
    if (recBtnR) recBtnR.hidden = true;
    return;
  }

  const useCarouselButtons = items.length > 1;
  const all = [...items];
  const frag = document.createDocumentFragment();
  all.forEach(it => frag.appendChild(buildRecommendedCardV2(it)));
  recTrack.appendChild(frag);
  initRecommendedCarousels();

  // Butonu göster/gizle
  if (recBtnL) recBtnL.hidden = !useCarouselButtons;
  if (recBtnR) recBtnR.hidden = !useCarouselButtons;

  if (!useCarouselButtons) return;

  const cardW = () => {
    const c = recTrack.querySelector(".rec-card-wrap, .rec-card");
    if (!c) return 336;
    return c.getBoundingClientRect().width + 18; // gap
  };

  let isScrolling = false;

  function go(dir) {
    if (isScrolling) return;
    isScrolling = true;
    recTrack.scrollBy({ left: dir * cardW(), behavior: "smooth" });
    setTimeout(() => {
      isScrolling = false;
    }, 420);
  }

  const onLeftClick = () => go(-1);
  const onRightClick = () => go(1);
  recBtnL?.addEventListener("click", onLeftClick);
  recBtnR?.addEventListener("click", onRightClick);

  // Mouse wheel yatay kaydırma
  const onWheel = (e) => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
      e.preventDefault();
      go(e.deltaY > 0 ? 1 : -1);
    }
  };
  recTrack.addEventListener("wheel", onWheel, { passive: false });

  recTrack.__wbRecommendedCleanup = () => {
    recBtnL?.removeEventListener("click", onLeftClick);
    recBtnR?.removeEventListener("click", onRightClick);
    recTrack.removeEventListener("wheel", onWheel);
  };
}

/* ---- Ana yükleme ---- */
async function loadRecommended() {
  if (!recTrack) {
    try { document.dispatchEvent(new Event("recommended:ready")); } catch {}
    return;
  }

  // Skeleton göster
  recTrack.innerHTML = "";
  for (let i = 0; i < 4; i++) {
    const sk = document.createElement("div");
    sk.className = "rec-card";
    sk.style.cssText = "pointer-events:none";
    sk.innerHTML = `
      <div class="rec-img-wrap" style="background:linear-gradient(90deg,#f0f0f0 25%,#e8e8e8 50%,#f0f0f0 75%);background-size:200% 100%;animation:_recShimmer 1.4s infinite"></div>
      <div class="rec-info">
        <div style="height:14px;background:#eee;border-radius:6px;width:65%;margin-bottom:8px"></div>
        <div style="height:12px;background:#f3f3f3;border-radius:6px;width:50%"></div>
      </div>`;
    recTrack.appendChild(sk);
  }
  // Shimmer animasyonu (1 kez ekle)
  if (!document.getElementById("_recShimmerStyle")) {
    const st = document.createElement("style");
    st.id = "_recShimmerStyle";
    st.textContent = `@keyframes _recShimmer{0%{background-position:200% 0}100%{background-position:-200% 0}}`;
    document.head.appendChild(st);
  }

  try {
    const raw = await loadListingBusinesses({ pageSize: 24, maxPages: 2, maxItems: 24 });
    const items = raw
      .filter(r => r.name)
      .map(r => ({
        id:       r.id || r.businessId || r.uid,
        name:     r.name || "İşletme",
        gallery:  r.gallery,
        images:   r.images,
        coverUrl: r.coverUrl || r.cover,
        logoUrl:  r.logoUrl,
        services: r.services,
        minPrice: r.minPrice,
        min_price:r.min_price,
        loc: {
          district: r.businessLocation?.district || r.district || "",
          city:     r.businessLocation?.city     || r.city     || "",
          province: r.businessLocation?.province || r.city     || "",
        }
      }));

    setupInfiniteCarousel(items);
  } catch (err) {
    console.warn("[recommended] yüklenemedi:", err);
    recTrack.innerHTML = `<div class="rec-empty">Önerilenler yüklenemedi.</div>`;
  } finally {
    try { document.dispatchEvent(new Event("recommended:ready")); } catch {}
  }
}
loadRecommended();

/* =========================================================
   DOB modal – orta çizgi hizası (rail) + seçilene kaydırma
========================================================= */
function ensureDobRail() {
  const vp = document.querySelector(".dobp-viewport");
  if (!vp) return false;
  if (!vp.querySelector(".dobp-rail")) {
    const rail = document.createElement("div");
    rail.className = "dobp-rail";
    rail.setAttribute("aria-hidden", "true");
    vp.appendChild(rail);
  }
  // Seçili öğeyi merkeze getir
  centerDobSelected();
  // Scroll sonunda seçiliyi merkeze sabitle
  bindDobCentering();
  return true;
}
function centerInCol(col, el) {
  if (!col || !el) return;
  const target = el.offsetTop - (col.clientHeight / 2 - el.clientHeight / 2);
  col.scrollTo({ top: Math.max(0, target), behavior: "auto" });
}
function centerDobSelected() {
  $$(".dobp-col").forEach((col) => {
    const sel =
      col.querySelector('.dobp-opt[aria-selected="true"]') ||
      col.querySelector(".dobp-opt");
    if (sel) centerInCol(col, sel);
  });
}
function bindDobCentering() {
  $$(".dobp-col").forEach((col) => {
    if (col._wbBoundCenter) return;
    col._wbBoundCenter = true;
    let t;
    const onStop = () => {
      const items = Array.from(col.querySelectorAll(".dobp-opt"));
      if (!items.length) return;
      // orta çizgi koordinatı
      const mid = col.getBoundingClientRect().top + col.clientHeight / 2;
      // en yakın butonu bul
      let best = null,
        bestDist = 1e9;
      items.forEach((it) => {
        const r = it.getBoundingClientRect();
        const cy = r.top + r.height / 2;
        const d = Math.abs(cy - mid);
        if (d < bestDist) {
          best = it;
          bestDist = d;
        }
      });
      if (best) centerInCol(col, best);
    };
    col.addEventListener(
      "scroll",
      () => {
        clearTimeout(t);
        t = setTimeout(onStop, 80);
      },
      { passive: true }
    );
    col.addEventListener("click", (e) => {
      const btn = e.target.closest(".dobp-opt");
      if (!btn) return;
      setTimeout(() => centerInCol(col, btn), 10);
    });
  });
}
function waitDobViewportAndFix(tries = 30) {
  const ok = ensureDobRail();
  if (ok) return;
  if (tries <= 0) return;
  setTimeout(() => waitDobViewportAndFix(tries - 1), 100);
}

/* =========================================================
   BİNDINGS SONU
========================================================= */
