/* calendar.js — MySQL + PHP Session backend (Firebase tamamen kaldırıldı)
 *
 * Bu sürüm:
 *  - Frontend’de Firebase SDK yok.
 *  - Auth: PHP session cookie (credentials: "include")
 *  - Tüm veriler PHP endpoint’lerinden gelir:
 *
 *    GET  /api/calendar/bootstrap.php
 *      → { ok:true, data:{ user, business, owner, staff[], catalog[] } }
 *        (Bazı kurulumlarda {staff:[], services:[]} da gelebilir; JS tolerant.)
 *
 *    GET  /api/calendar/appointments.php?start=YYYY-MM-DD%20HH:MM:SS&end=YYYY-MM-DD%20HH:MM:SS
 *      → { ok:true, data:{ appointments:[...] } }  veya direkt [...]
 *
 *    POST /api/calendar/update-appointment.php
 *      body: { id|appointmentId, status?, attended? }
 *      → { ok:true, updated:true, data:{ id, status, attended } }
 *
 *    POST /api/auth/logout.php
 *      → { ok:true, data:{ success:true } }
 */

const DAY_TR       = ["Pazar","Pazartesi","Salı","Çarşamba","Perşembe","Cuma","Cumartesi"];
const DAY_TR_SHORT = ["Paz","Pzt","Sal","Çar","Per","Cum","Cmt"];
const fmtTR        = new Intl.DateTimeFormat("tr-TR",{weekday:"short", day:"2-digit", month:"short"});
const dShort       = new Intl.DateTimeFormat("tr-TR",{day:"2-digit", month:"short"});
const $  = (s,r=document)=>r.querySelector(s);
const $$ = (s,r=document)=>[...r.querySelectorAll(s)];
const pad = (n)=>String(n).padStart(2,"0");
const cssEscape = (s)=>{ try{ return CSS?.escape ? CSS.escape(String(s)) : String(s).replace(/[^a-zA-Z0-9_\-]/g,'\\$&'); }catch{ return String(s); } };
const monthTR = (d)=> d.toLocaleString("tr-TR",{month:"long", year:"numeric"});

/* =================== READY helper =================== */

function onReady(fn){
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", fn, { once:true });
  } else {
    fn();
  }
}

/* =================== LOGIN redirect helper =================== */

function redirectToLogin(){
  const loginUrl = new URL("admin-register-login.html", window.location.href);
  const here = window.location.pathname + window.location.search + window.location.hash;
  loginUrl.searchParams.set("return_to", here);
  loginUrl.hash = "login";
  location.replace(loginUrl.toString());
}

/* =================== API yardımcıları =================== */

/** json_ok() -> { ok:true, data:{...} } formatını açar (extra flag’leri de korur) */
/** wb_ok() -> { ok:true, data:{...} } zarfini acar */
function unwrapPayload(obj){
  if (!obj) return null;
  if (typeof obj === "object" && obj.ok === true && obj.data != null){
    const { ok, data, ...rest } = obj;
    if (data && typeof data === "object" && !Array.isArray(data)){
      return { ...data, ...rest };
    }
    return data;
  }
  return obj;
}


// ── API Wrapper — window.WbApi (wb-api-shim.js) üzerinden ──────────
async function apiGet(path, params)  { return window.WbApi.get(path, params); }
async function apiPost(path, body)   { return window.WbApi.post(path, body); }
// ─────────────────────────────────────────────────────────────────────



/* =================== Telefon normalizasyonu =================== */

function _digits(s){ return String(s||"").replace(/\D+/g,""); }

function phoneToTR10(any){
  let d = _digits(any);
  if (d.startsWith("00")) d = d.slice(2);
  if (d.startsWith("90") && d.length === 12) d = d.slice(2);
  if (d.startsWith("0")  && d.length === 11) d = d.slice(1);
  return (d.length===10) ? d : (d.length>10 ? d.slice(-10) : "");
}

function normalizeCustomerPhone(customer){
  const candidates = [
    customer?.phone, customer?.phoneNumber, customer?.tel,
    customer?.phoneE164, customer?.userPhoneE164, customer?.phone_e164,
    customer?.userPhone, customer?.userPhoneE164
  ];
  for(const v of candidates){
    const t = phoneToTR10(v);
    if (t) return t;
  }
  return "";
}

/* =================== Saat / tarih yardımcıları =================== */

function cellH(){
  const v = getComputedStyle(document.documentElement).getPropertyValue('--cellH') || "";
  const n = parseFloat(v);
  return Number.isFinite(n) && n > 0 ? n : 64;
}
function cssVarPx(name, scope=document.documentElement){
  const raw = getComputedStyle(scope).getPropertyValue(name) || "0";
  return parseFloat(raw);
}
function px(n){
  const dpr = window.devicePixelRatio || 1;
  return Math.round(n * dpr) / dpr;
}
function floatToHM(f){
  const h = Math.floor(f || 0);
  const m = Math.round(((f || 0) - h) * 60);
  return `${String(h).padStart(2,"0")}:${String(m).padStart(2,"0")}`;
}
function fmtHM(date){ return `${pad(date.getHours())}:${pad(date.getMinutes())}`; }

function toSqlDateTimeLocal(d){
  // YYYY-MM-DD HH:MM:SS (local time)
  const yyyy = d.getFullYear();
  const mm   = pad(d.getMonth()+1);
  const dd   = pad(d.getDate());
  const hh   = pad(d.getHours());
  const mi   = pad(d.getMinutes());
  const ss   = pad(d.getSeconds());
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}:${ss}`;
}

/**
 * Business/staff saatlerini tek formata çevir:
 * defaultWeek[0..6] = { open:boolean, ranges:[{startMin,endMin}] }
 *
 * Kabul edilen input örnekleri:
 *  - Eski: {0:{open:true,ranges:[{startMin:540,endMin:1080}]}, ...}
 *  - Key: {mon:["09:00-18:00"], tue:["09:00-18:00"], ...}
 *  - UI:  {mon:{enabled:true,start:"09:00",end:"18:00"}, ...}
 *  - JSON string
 */
function normalizeHoursToDefaultWeek(input){
  const out = {};
  for(let i=0;i<=6;i++) out[i] = { open:false, ranges:[] };

  if (!input) return out;

  let obj = input;
  try{
    if (typeof obj === "string") obj = JSON.parse(obj);
  }catch{}

  if (!obj || typeof obj !== "object") return out;

  // helper: "HH:MM" -> minutes
  const t2m = (t)=>{
    const m = String(t||"").match(/(\d{1,2}):(\d{2})/);
    if(!m) return null;
    const hh = Number(m[1]), mm = Number(m[2]);
    if(!Number.isFinite(hh)||!Number.isFinite(mm)) return null;
    return hh*60+mm;
  };

  const setRange = (idx, startMin, endMin)=>{
    if (startMin==null || endMin==null || endMin<=startMin) return;
    out[idx] = { open:true, ranges:[{ startMin, endMin }] };
  };

  const keyToIdx = {sun:0,mon:1,tue:2,wed:3,thu:4,fri:5,sat:6};

  // 1) Numeric index format
  const keys = Object.keys(obj);
  const hasNumeric = keys.some(k => /^\d$/.test(k) || /^[0-6]$/.test(k));
  if (hasNumeric){
    for (let i=0;i<=6;i++){
      const d = obj[i] ?? obj[String(i)];
      if (!d) continue;
      if (d.open && Array.isArray(d.ranges) && d.ranges.length){
        const r = d.ranges[0];
        setRange(i, r.startMin, r.endMin);
      }
    }
    return out;
  }

  // 2) sun/mon... keys
  for (const [k,v] of Object.entries(obj)){
    const kk = String(k).toLowerCase();
    if (!(kk in keyToIdx)) continue;
    const idx = keyToIdx[kk];

    // v = ["09:00-18:00"] veya "09:00-18:00"
    if (Array.isArray(v) && v.length){
      const s = String(v[0]||"");
      const parts = s.split("-");
      if (parts.length===2){
        setRange(idx, t2m(parts[0]), t2m(parts[1]));
      }
      continue;
    }
    if (typeof v === "string"){
      const parts = v.split("-");
      if (parts.length===2){
        setRange(idx, t2m(parts[0]), t2m(parts[1]));
      }
      continue;
    }
    // v = {enabled,start,end}
    if (v && typeof v === "object"){
      const enabled = (v.enabled ?? v.open) === true;
      const start = t2m(v.start ?? v.startTime);
      const end   = t2m(v.end   ?? v.endTime);
      if (enabled && start!=null && end!=null){
        setRange(idx, start, end);
      }
      continue;
    }
  }

  return out;
}

function initials(n){
  return (n||"?").split(" ").filter(Boolean).map(w=>w[0]).slice(0,2).join("").toUpperCase();
}

/* staff.js ile aynı renk paleti */
const AVATAR_COLORS_CAL = [
  '#0ea5b3','#6366f1','#8b5cf6','#ec4899','#f59e0b',
  '#0284c7','#7c3aed','#db2777','#0891b2','#4f46e5'
];

  // Yeşil tonları filtrele (DB'den gelen custom renk dahil)
  function filterGreen(color) {
    if (!color) return '#0ea5b3';
    const c = color.toLowerCase();
    // Yeşil hex tonları
    const greens = ['#16a34a','#059669','#10b981','#22c55e','#4ade80','#15803d','#166534','#14532d','#86efac','#bbf7d0','#dcfce7'];
    if (greens.includes(c)) return '#0ea5b3';
    // RGB yeşil kontrolü
    try {
      const m = c.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/);
      if (m) {
        const r=parseInt(m[1],16), g=parseInt(m[2],16), b=parseInt(m[3],16);
        if (g > r*1.3 && g > b*1.3 && g > 100) return '#0ea5b3';
      }
    } catch(e) {}
    return color;
  }

function avatarColorCal(name){
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff;
  return AVATAR_COLORS_CAL[Math.abs(h) % AVATAR_COLORS_CAL.length];
}
function uniqueNames(names){
  const seen = new Set(); const out = [];
  for(const raw of names){
    const name = (raw||"").trim(); if(!name) continue;
    const key = name.toLowerCase(); if(seen.has(key)) continue;
    seen.add(key); out.push(name);
  }
  return out;
}

/* defaultHours helpers */

const IDX_TO_KEY = {0:"sun",1:"mon",2:"tue",3:"wed",4:"thu",5:"fri",6:"sat"};
const KEY_TO_IDX = {sun:0,mon:1,tue:2,wed:3,thu:4,fri:5,sat:6};

const pad2 = (n)=>String(n).padStart(2,"0");
const m2t  = (x)=>`${pad2(Math.floor((x||0)/60))}:${pad2((x||0)%60)}`;

function defaultHoursToUI(defaultHoursObj){
  const ui = {};
  Object.keys(KEY_TO_IDX).forEach(k=> ui[k] = { enabled:false, start:"10:00", end:"19:00" });
  if (!defaultHoursObj || typeof defaultHoursObj !== "object") return ui;
  for (let i=0;i<=6;i++){
    const d = defaultHoursObj[i] || defaultHoursObj[IDX_TO_KEY[i]];
    if (!d || !d.open || !Array.isArray(d.ranges) || !d.ranges.length){
      ui[IDX_TO_KEY[i]] = { enabled:false, start:"10:00", end:"19:00" };
    } else {
      const r = d.ranges[0];
      ui[IDX_TO_KEY[i]] = { enabled:true, start:m2t(r.startMin), end:m2t(r.endMin) };
    }
  }
  return ui;
}

/* =================== Modal yöneticisi =================== */

let __lastFocusEl = null;
let __activeModalEl = null;

function _trapFocusHandler(e){
  if (e.key !== "Tab") return;
  const host = __activeModalEl ||
    document.querySelector('.center-pop.open,#notify.open,#bkPanel.open,#bmModal.show,.sb-modal:has(+ *)');
  if (!host) return;
  const focusables = host.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
  const list = Array.from(focusables).filter(el => !el.hasAttribute('disabled') && el.offsetParent !== null);
  if (!list.length) return;
  const first = list[0], last = list[list.length - 1];
  const goingBack = e.shiftKey;
  if (goingBack && document.activeElement === first){ e.preventDefault(); last.focus(); }
  else if (!goingBack && document.activeElement === last){ e.preventDefault(); first.focus(); }
}

function closeAllModals() {
  const calPop = document.getElementById('calendarPopover') || document.querySelector('.center-pop');
  calPop?.classList.remove('open');
  calPop?.setAttribute('aria-hidden','true');
  document.getElementById('dateLabelWrap')?.setAttribute('aria-expanded','false');

  document.getElementById('staffPop')?.classList.remove('open');
  document.getElementById('staffBtn')?.setAttribute('aria-expanded','false');

  document.getElementById('viewPop')?.classList.remove('open');
  document.getElementById('viewChip')?.setAttribute('aria-expanded','false');

  document.getElementById('notify')?.classList.remove('open');
  document.getElementById('bkPanel')?.classList.remove('open');

  const bm = document.getElementById('bmModal');
  bm?.classList.remove('show');
  bm?.setAttribute('aria-hidden','true');

  const sb = document.querySelector('.sb-modal')?.parentElement;
  sb?.setAttribute('aria-hidden','true');

  __activeModalEl = null;
  try{
    if (__lastFocusEl && document.contains(__lastFocusEl)) {
      __lastFocusEl.focus();
    }
  }catch{}
}

function openModal({ id, panelClassOpen='open', ariaTargetId }) {
  __lastFocusEl = document.activeElement;
  closeAllModals();
  const panel = document.getElementById(id);
  panel?.classList.add(panelClassOpen);
  (ariaTargetId ? document.getElementById(ariaTargetId) : panel)?.setAttribute('aria-hidden','false');
  __activeModalEl = panel || null;
  panel?.querySelector('button, [href], input, [tabindex]:not([tabindex="-1"])')?.focus();
}

document.addEventListener('keydown', e => { if (e.key === 'Escape') closeAllModals(); });
document.addEventListener('keydown', _trapFocusHandler);
document.addEventListener('mousedown', e => {
  const anyOpen =
    document.querySelector('.center-pop.open') ||
    document.getElementById('notify')?.classList.contains('open') ||
    document.getElementById('bmModal')?.classList.contains('show') ||
    document.getElementById('staffPop')?.classList.contains('open') ||
    document.getElementById('bkPanel')?.classList.contains('open');
  if (!anyOpen) return;

  const inside =
    e.target.closest('#calendarPopover') ||
    e.target.closest('.center-pop') ||
    e.target.closest('#notify') ||
    e.target.closest('#bmModal') ||
    e.target.closest('.sb-modal') ||
    e.target.closest('#staffPop') ||
    e.target.closest('#bkPanel') ||
    e.target.closest('#dateLabelWrap') ||
    e.target.closest('#bellBtn') ||
    e.target.closest('#topProfileBtn');
  if (!inside) closeAllModals();
});
window.openModal = openModal;
window.closeAllModals = closeAllModals;
// wb-notifications.js'in takvimi yenileyebilmesi için global hook
window.wbCalendarRefresh = function() {
  try { loadAppointmentsForCurrent(); } catch(e) { console.warn('[wbCalendarRefresh]', e); }
};

/* =================== Profil modalını doldur =================== */

function setBusinessModalData({ name="", email="", business="" }) {
  const nameEl  = document.getElementById('bmName');
  const emailEl = document.getElementById('bmMail');
  const bizEl   = document.getElementById('bmBusiness');
  const listEl  = document.getElementById('bmList');

  if (nameEl)  nameEl.textContent  = name || "—";
  if (emailEl) emailEl.textContent = email || "";
  if (bizEl)   bizEl.textContent   = business || "";

  if (listEl) {
    listEl.innerHTML = "";
    const item = document.createElement("div");
    item.className = "bm-item";
    item.innerHTML = `
      <div class="bm-dot"></div>
      <div class="bm-item-main">
        <div class="bm-biz">${business || 'İşletme'}</div>
        <div class="bm-sub">${name || '—'}</div>
      </div>`;
    listEl.appendChild(item);
  }
}
window.setBusinessModalData = setBusinessModalData;

/* =================== STATE =================== */

let current = new Date();
let view    = (localStorage.getItem("calendar_view") === "week") ? "week" : "day";

let ADMIN_UID   = "";
let BUSINESS_ID = "";
let OWNER_UID   = "";
let OWNER       = "Admin";

let defaultWeek = {};
let bizHoursUI  = {};

let STAFF_DOCS   = [];   // { id, data: {name, hoursOverride?} }
let STAFF_NAMES  = [];
let selectedStaff = [];

let BOOKINGS    = [];
let BOOKING_MAP = new Map();

/* Randevuyu localStorage’da gizlemek için key */
function bookingKey(bOrId){
  if (typeof bOrId === "string") return `appts:${bOrId}`;
  if (!bOrId || !bOrId.id) return "";
  return `appts:${bOrId.id}`;
}

/* Görünümden gizlenen randevular */
let HIDDEN_BOOKINGS = new Set();
function _hiddenStoreKey(){ return `hidden_bookings_${BUSINESS_ID||"_"}`; }
function loadHidden(){
  try{
    const raw = localStorage.getItem(_hiddenStoreKey());
    if(!raw) return;
    const arr = JSON.parse(raw);
    if(Array.isArray(arr)) HIDDEN_BOOKINGS = new Set(arr.map(String));
  }catch{}
}
function persistHidden(){
  try{ localStorage.setItem(_hiddenStoreKey(), JSON.stringify([...HIDDEN_BOOKINGS])); }catch{}
}

/* Gün görünümü: staff sütunlarına hızlı erişim için Map */
let DAY_COL_MAP = new Map();

/* Servis kataloğu cache’i (serviceId → {id, name, price...}) */
const SERVICE_MAP = new Map();

/* =================== Saat/mesai hesapları =================== */

function effectiveDayForStaff(idx, staffName){
  const base = defaultWeek?.[idx] || { open:false, ranges:[] };

  let override = null;
  const who = STAFF_DOCS.find(rec => (rec.data?.name || "").trim().toLowerCase() === String(staffName||"").trim().toLowerCase());
  if (who && who.data?.hoursOverride && who.data.hoursOverride[idx] != null){
    override = who.data.hoursOverride[idx];
  }
  const eff = override ? override : base;

  if (!eff.open || !Array.isArray(eff.ranges) || !eff.ranges.length){
    return { open:false, start:10, end:19 };
  }
  const r = eff.ranges[0];
  return { open:true, start:(r.startMin/60), end:(r.endMin/60) };
}

function hoursFor(name, d=current){
  const idx = d.getDay();
  return effectiveDayForStaff(idx, name);
}

/* Takvim dikey aralığı 08:00–24:00 */
const VSTART = 8, VEND = 24;

function addOff(container, fromH, toH){
  const CH = cellH();
  const s = Math.max(fromH, VSTART);
  const e = Math.min(toH, VEND);
  if(e<=s) return;
  const band=document.createElement("div");
  band.className="offband";
  band.style.top    = px((s - VSTART)*CH) + "px";
  band.style.height = px((e - s)*CH) + "px";
  container.appendChild(band);
}

/* === Overdue/Late & geçmiş kontrolleri === */

const nowLocal = ()=> new Date();

function isOverdue(b){
  try{
    const st = (b.status||'pending');
    if (st==='cancelled' || st==='canceled') return false;
    if (b.attended === true) return false;
    if(!b.startAt) return false;
    const s = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
    return nowLocal() >= s;
  }catch{ return false; }
}

function isLate(b){
  try{
    const st = (b.status||'pending');
    if (st==='cancelled' || st==='canceled') return false;
    if (b.attended !== true) return false;
    if(!b.startAt) return false;
    const s = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
    return nowLocal() >= s;
  }catch{ return false; }
}

function isPastBooking(b){
  try{
    const start = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt || Date.now());
    const end   = (b.endAt   instanceof Date) ? b.endAt :
                  (b.endAt ? new Date(b.endAt) :
                   new Date(start.getTime() + (b.totalMin||b.durationMin||30)*60000));
    return nowLocal() >= end;
  }catch{ return false; }
}

/* =================== KATALOG & etiketler =================== */

function labelFromBooking(b){
  if (isBlockedBooking(b)) {
    const note = String(b.notes || '').trim();
    return note || 'Dolu';
  }
  if (b.serviceName) return b.serviceName;

  const names = [];

  if (b.serviceId && SERVICE_MAP.has(b.serviceId)){
    const svc = SERVICE_MAP.get(b.serviceId);
    const nm = (svc?.name || svc?.title || "").trim();
    if (nm) names.push(nm);
  }

  const arr = Array.isArray(b.items) ? b.items
             : (Array.isArray(b.services) ? b.services : []);
  arr.forEach(i=>{
    const nm = (i?.name || i?.label || "").trim();
    if (nm && !names.includes(nm)) names.push(nm);
  });

  if (names.length) return names.join(", ");

  if (b.serviceId){
    const raw = String(b.serviceId||"");
    const cleaned = raw.replace(/[_-]+/g," ").replace(/\s+/g," ").trim();
    if (!cleaned) return "Randevu";
    return cleaned.split(" ").map(w => w ? w[0].toLocaleUpperCase("tr-TR") + w.slice(1) : "").join(" ");
  }

  return "Randevu";
}

function priceFromBooking(b){
  if (typeof b.total === "number" && b.total > 0) return b.total;

  const arr = Array.isArray(b.items) ? b.items
             : (Array.isArray(b.services) ? b.services : []);
  let sum = 0;
  let hasAny = false;

  for (const i of arr){
    const cand = [i?.price, i?.amount, i?.total, i?.fee]
      .find(v => typeof v === "number" && !isNaN(v) && v > 0);
    if (cand){
      sum += cand;
      hasAny = true;
    }
  }
  if (hasAny) return sum;

  if (b.serviceId && SERVICE_MAP.has(b.serviceId)){
    const svc = SERVICE_MAP.get(b.serviceId);
    const val = [svc?.price, svc?.amount, svc?.total, svc?.fee]
      .find(v => typeof v === "number" && !isNaN(v) && v > 0);
    if (val) return val;
  }

  return null;
}

/* =================== Booking normalize (PHP API) =================== */

function normalizeAppointment(raw){
  if (!raw) return null;

  const parseDT = (v)=>{
    if (!v) return null;
    if (v instanceof Date) return v;
    if (typeof v === "number") return new Date(v);
    let s = String(v).trim();
    if (!s) return null;

    // "YYYY-MM-DD HH:MM:SS" -> "YYYY-MM-DDTHH:MM:SS"
    if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(s)) s = s.replace(" ", "T");
    // "YYYY-MM-DD" -> "YYYY-MM-DDT00:00:00"
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) s = s + "T00:00:00";

    const d = new Date(s);
    if (!isNaN(d.getTime())) return d;
    return null;
  };

  const start = parseDT(
    raw.startAt || raw.start_at || raw.start || raw.startISO || raw.start_iso
  );
  const end0 = parseDT(
    raw.endAt || raw.end_at || raw.end || raw.endISO || raw.end_iso
  );

  if (!start) return null;

  let end = end0;
  let totalMin =
    raw.totalMin ?? raw.durationMin ?? raw.totalMinutes ?? raw.duration_min ?? raw.total_min ?? null;

  if (!end) {
    const minutes = Number(totalMin || 30);
    end = new Date(start.getTime() + minutes * 60000);
  } else if (!totalMin) {
    totalMin = Math.max(1, Math.round((end.getTime() - start.getTime()) / 60000));
  }

  const customer = raw.customer || {};
  const cName  = customer.name || customer.fullName || customer.displayName ||
                 raw.customerName || raw.customer_name || raw.userName || raw.customer ||
                 null;
  const cPhone = customer.phone || customer.phoneNumber || customer.tel ||
                 raw.customerPhone || raw.customer_phone || raw.userPhone || raw.phone ||
                 null;
  const cEmail = customer.email || raw.customerEmail || raw.customer_email || raw.email || null;
  const cUid   = customer.uid || raw.customerUid || raw.customer_uid || raw.userUid || raw.user_uid || null;
  const rawStatus = String(raw.status || "pending").toLowerCase();

  const staffName = raw.staffName || raw.staff_name || raw.staff || null;
  const staffId   = raw.staffId   || raw.staff_id   || null;

  const serviceId   = raw.serviceId   || raw.service_id || null;
  const serviceName = raw.serviceName || raw.service_name || raw.title || null;

  // attended: 1/0, "1"/"0" veya true/false gelebilir
  const attRaw = (raw.attended ?? raw.isAttended ?? raw.came ?? null);
  const attended =
    (attRaw === true) ? true :
    (attRaw === false) ? false :
    (attRaw === 1 || attRaw === "1") ? true :
    (attRaw === 0 || attRaw === "0") ? false :
    null;

  return {
    _src: "api",
    id: String(raw.id ?? raw.appointmentId ?? raw.appointment_id ?? ""),
    businessId: raw.businessId || raw.business_id || BUSINESS_ID,
    startAt: start,
    endAt: end,
    totalMin,

    serviceId: serviceId ? String(serviceId) : null,
    serviceName: serviceName || null,
    total: (typeof raw.total === "number") ? raw.total : (raw.total ? Number(raw.total) : null),
    notes: raw.notes || raw.note || "",

    customer: {
      ...customer,
      name: cName,
      phone: cPhone,
      email: cEmail,
      uid: cUid,
    },

    status: (
      String(cName || "").trim() === '[DOLU]' &&
      !['cancelled','canceled','rejected','declined','no_show','completed'].includes(rawStatus)
    ) ? 'blocked' : rawStatus,
    attended,

    staffName: staffName || null,
    staffId: staffId ? String(staffId) : null,
    dayKey: raw.dayKey || raw.day || null,
    startMin: raw.startMin ?? null,
    endMin: raw.endMin ?? null,

    items: raw.items || null,
    services: raw.services || null,
  };
}

/* =================== Booking → personel adı =================== */

function canonicalName(name, ownerName){
  const t = String(name||"").trim().toLowerCase();
  const o = String(ownerName||"").trim().toLowerCase();
  if (!t) return "";
  if (t === "admin" || t === "owner" || t === "sahip" || t === o) return ownerName;
  return String(name||"").trim();
}

function bookingStaffName(b){
  let raw = b.staffName;
  if (!raw && b.staffId && Array.isArray(STAFF_DOCS) && STAFF_DOCS.length){
    const rec = STAFF_DOCS.find(s => s.id === b.staffId);
    if (rec) raw = (rec.data?.name || raw);
  }
  raw = raw || OWNER;
  return canonicalName(raw, OWNER) || OWNER;
}

/* =================== Bildirim paneli (sade) =================== */

const SOUND_EL    = ()=> document.getElementById('notiSound');
const BELL_COUNT  = ()=> document.getElementById('bellCount');
const NOTIFY_BODY = ()=> document.getElementById('notifyBody');

function playNoti(){ try{ SOUND_EL()?.play()?.catch(()=>{}); }catch{} }
function countCards(){ const body = NOTIFY_BODY(); if(!body) return 0; return body.querySelectorAll('.noti-card').length; }

function setBell(n){
  const c = BELL_COUNT(); if(!c) return;
  n = Number(n||0);
  c.textContent = String(n);
  if(n>0) c.classList.add('show');
  else    c.classList.remove('show');
}
function syncEmptyState(){
  const body = NOTIFY_BODY(); if(!body) return;
  if (countCards()===0){
    body.innerHTML = `<div class="notif-empty">Henüz bildiriminiz yok…</div>`;
  }
}
function syncBellFromDom(){
  setBell(countCards());
  if(countCards()===0) syncEmptyState();
}
function ensureNotifyPanel(){
  const panel = document.getElementById('notify'); if(!panel) return;

  if (!NOTIFY_BODY()){
    const body = document.createElement('div');
    body.id = 'notifyBody';
    body.className = 'notify-body';
    panel.appendChild(body);
  }

  if (!panel.dataset.bound){
    panel.dataset.bound = "1";
    document.getElementById('notifyClose')?.addEventListener('click', closeAllModals);
    document.getElementById('bellBtn')?.addEventListener('click', (e)=>{
      __lastFocusEl = e.currentTarget || document.activeElement || null;
      openModal({ id:'notify', panelClassOpen:'open' });
    });
  }

  syncEmptyState();
  syncBellFromDom();
}

function escapeHtml(s=""){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;")
    .replace(/'/g,"&#39;");
}

function pushWelcomeOnce(){
  // BUSINESS_ID henüz set edilmemiş olabilir — bootstrapCalendar içinden çağrılıyor
  const KEY = 'wb_welcome_v4_' + (BUSINESS_ID || 'x');
  if(localStorage.getItem(KEY)==='1') return;

  const body = NOTIFY_BODY(); if(!body) return;
  body.querySelector('.notif-empty')?.remove();

  const now = new Date();
  const card = document.createElement('div');
  card.className = 'noti-card sys';
  card.dataset.id = 'welcome';
  card.innerHTML = `
    <div class="noti-hd">Sistem Mesajı</div>
    <div class="noti-meta">${now.toLocaleDateString("tr-TR")} • ${pad(now.getHours())}:${pad(now.getMinutes())}</div>
    <div class="noti-msg">Hoş geldiniz ${escapeHtml(OWNER)}. Takvim ve ayarlar sayfalarını kullanarak işletmenizi yönetebilirsiniz. Dükkanınız otomatik olarak yayınlanmıştır.</div>
    <div class="noti-row">
      <div></div>
      <div class="btns">
        <a class="btn xs" href="settings.html">Ayarlar</a>
        <button class="btn xs danger" data-dismiss>Bildirimi Sil</button>
      </div>
    </div>
  `;
  card.querySelector('[data-dismiss]')?.addEventListener('click', ()=>{
    card.remove();
    syncBellFromDom();
  });
  body.prepend(card);

  localStorage.setItem(KEY,'1');
  // Eski key'leri temizle
  try { localStorage.removeItem('mbs_welcome_added_v3'); } catch {}
  playNoti();
  syncBellFromDom();
}

/* =================== CSS enjeksiyonu (randevu kartları) =================== */

function injectBookingStyles(){
  if(document.getElementById("bk-style")) return;
  const css = `
    .staff-col{position:relative}

    .booking{
      position:absolute;
      left:6px;
      right:6px;
      background:#0ea5e9;
      color:#fff;
      border-radius:10px;
      padding:6px 10px;
      box-shadow:0 8px 18px rgba(0,0,0,.18);
      display:flex;
      align-items:flex-start;
      cursor:pointer;
      overflow:hidden;
      z-index:4;
    }
    .booking.approved{background:#10b981}
    .booking.blocked{background:#334155;border:1px dashed rgba(255,255,255,.35)}
    .booking.cancelled{background:#94a3b8}
    .booking.overdue{background:#ef4444}
    .booking.late{background:#f59e0b;color:#111}

    .wk-chip{
      display:inline-flex;
      flex-direction:column;
      align-items:flex-start;
      margin:4px 4px 0 0;
      background:#0ea5e9;
      color:#fff;
      border-radius:999px;
      padding:6px 10px;
      font-weight:800;
      font-size:12px;
      box-shadow:0 6px 12px rgba(0,0,0,.15);
      cursor:pointer;
      line-height:1.25;
      max-width:100%;
    }
    .wk-chip.approved{background:#10b981}
    .wk-chip.blocked{background:#334155}
    .wk-chip.cancelled{background:#94a3b8}
    .wk-chip.overdue{background:#ef4444}
    .wk-chip.late{background:#f59e0b;color:#111}

    .wk-col-inner{position:relative;height:var(--wkRowH);overflow-y:auto;overflow-x:hidden;padding:8px;scrollbar-gutter:stable;}
    .wk-col-inner.closed{overflow:hidden;}

    .notif-empty{ color:#9aa3b2; text-align:center; padding:40px 0; }

    .now-line{ position:absolute; left:0; right:0; height:1px; background:#ef4444; z-index:5; }
  `;
  const el=document.createElement("style"); el.id="bk-style"; el.textContent=css; document.head.appendChild(el);
}

/* =================== AUTH + BOOTSTRAP (PHP tarafı) =================== */

async function bootstrapCalendar(){
  const raw = await apiGet("/api/calendar/bootstrap.php");
  const data = unwrapPayload(raw);
  if (!data) return;

  // API farklı formatlarda dönebilir; burası tolerant.
  const user  = data.user || data.owner || data.me || {};
  const owner = data.owner || user || {};
  const biz   = data.business || {};

  OWNER = (owner.name || user.name || "Admin");
  ADMIN_UID = String(user.uid || user.id || "");
  OWNER_UID = String(owner.uid || owner.id || ADMIN_UID || "");
  BUSINESS_ID = String(
    biz.id || data.business_id || data.businessId || data.businessID || OWNER_UID || "session"
  );

  // Business adı / mail (modal için)
  const bizName = biz.name || data.business_name || data.businessName || "İşletmeniz";
  const email   = user.email || "";

  // Çalışma saatleri: old/new formatlardan defaultWeek’e çevir
  defaultWeek = normalizeHoursToDefaultWeek(
    biz.defaultHours || biz.working_hours || biz.workingHours || data.defaultHours || data.working_hours || null
  );
  bizHoursUI  = defaultHoursToUI(defaultWeek);

  // Staff
  const staffArr = Array.isArray(data.staff) ? data.staff
                : Array.isArray(data.staffs) ? data.staffs
                : Array.isArray(data.employees) ? data.employees
                : [];
  STAFF_DOCS = staffArr.map(s => ({
    id: String(s.id ?? s.staffId ?? s.staff_id ?? ""),
    data: {
      ...s,
      // olası saat override formatlarını normalize et
      hoursOverride: normalizeHoursToDefaultWeek(s.hoursOverride || s.hours_override || s.hours || null)
    }
  }));

  rebuildStaffNamesFromDocs();

  // Services / Catalog
  const catalogArr = Array.isArray(data.catalog) ? data.catalog
                  : Array.isArray(data.services) ? data.services
                  : Array.isArray(data.service_catalog) ? data.service_catalog
                  : [];
  SERVICE_MAP.clear();
  catalogArr.forEach(s=>{
    if (!s) return;
    const id = s.id ?? s.serviceId ?? s.service_id;
    if (!id) return;
    SERVICE_MAP.set(String(id), {
      id: String(id),
      name: s.name || s.title || s.label || "Hizmet",
      price: (typeof s.price === "number") ? s.price : (s.price ? Number(s.price) : (s.amount ? Number(s.amount) : null)),
      duration_min: s.duration_min ?? s.durationMin ?? s.duration ?? null,
      durationMin: s.durationMin ?? s.duration_min ?? s.duration ?? null,
      ...s
    });
  });

  setBusinessModalData({ name: OWNER, email, business: bizName });

  loadHidden();
  injectBookingStyles();
  if (!window.__WB_NOTIF_ACTIVE) {
    ensureNotifyPanel();
    pushWelcomeOnce();
    startNotificationPolling();
    startCancellationPolling();
  }

  // boot() zaten setView() içinden randevuları çağırıyor → ikinci kez fetch yapma
  boot();
}

/* =================== Yeni Randevu Bildirimleri (Poll) =================== */

let _notifLastTs = Math.floor(Date.now() / 1000) - 300; // son 5 dakikadaki bekleyen randevuları göster
let _notifSeenIds = new Set();
let _notifPollTimer = null;

// wb-notifications.js zaten yüklüyse bildirim kartlarını o gösteriyor;
// calendar.js sadece takvim görünümünü yeniler (çift bildirim önlenir).
async function pollNewAppointments() {
  try {
    const res = await apiGet('/api/calendar/pending-notifications.php', { since: _notifLastTs });
    if (!res || !res.ok) return;
    const _calPendingItems = res.data?.items ?? res.items ?? [];
    if (!Array.isArray(_calPendingItems)) return;
    _notifLastTs = res.data?.ts ?? res.ts ?? Math.floor(Date.now() / 1000);
    const newItems = _calPendingItems.filter(it => !_notifSeenIds.has(it.id));
    if (!newItems.length) return;
    newItems.forEach(it => _notifSeenIds.add(it.id));
    // wb-notifications.js yoksa biz göster, varsa o zaten gösteriyor
    if (!window.__WB_NOTIF_ACTIVE) {
      newItems.forEach(it => pushAppointmentNotif(it));
    }
    // Her iki durumda da takvimi yenile
    try { loadAppointmentsForCurrent(); } catch {}
  } catch {}
}



function fmtNotifDT(isoOrSql) {
  if (!isoOrSql) return '';
  const s = String(isoOrSql).replace(' ', 'T');
  const d = new Date(s);
  if (isNaN(d.getTime())) return '';
  return `${pad(d.getDate())}.${pad(d.getMonth()+1)}.${d.getFullYear()} • ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function pushAppointmentNotif(it) {
  ensureNotifyPanel();
  const body = NOTIFY_BODY();
  if (!body) return;
  body.querySelector('.notif-empty')?.remove();

  const card = document.createElement('div');
  card.className = 'noti-card new';
  card.dataset.id = it.id;
  const staffTxt = it.staffName ? ` • ${escapeHtml(it.staffName)}` : '';
  const notifTime = fmtNotifDT(it.createdAt) || fmtNotifDT(new Date().toISOString());
  const apptTime  = escapeHtml(it.startFmt || '');
  card.innerHTML = `
    <div class="noti-hd">🔔 Yeni Randevu Talebi</div>
    <div class="noti-meta" style="display:flex;flex-direction:column;gap:2px">
      <span style="font-weight:700;color:#374151">${notifTime}</span>
      <span>Randevu: ${apptTime}${staffTxt}</span>
    </div>
    <div class="noti-msg">
      <strong>${escapeHtml(it.customerName || '—')}</strong>
      ${it.customerPhone ? ' • ' + escapeHtml(it.customerPhone) : ''}<br>
      ${escapeHtml(it.serviceName || 'Hizmet')}
    </div>
    <div class="noti-row">
      <div></div>
      <div class="btns">
        <button class="btn xs primary" data-appt-id="${escapeHtml(it.id)}" data-action="approve">Onayla</button>
        <button class="btn xs" data-appt-id="${escapeHtml(it.id)}" data-action="reject">Reddet</button>
        <button class="btn xs danger" data-dismiss>Bildirimi Sil</button>
      </div>
    </div>`;

  card.querySelector('[data-dismiss]')?.addEventListener('click', () => {
    card.remove();
    syncBellFromDom();
  });

  card.querySelector('[data-action="approve"]')?.addEventListener('click', async (e) => {
    e.stopPropagation();
    const btn = e.currentTarget;
    btn.disabled = true;
    btn.textContent = '...';
    try {
      await apiPost('/api/calendar/update-appointment.php', { id: it.id, status: 'approved' });
      card.querySelector('.noti-hd').textContent = '✅ Onaylandı';
      card.querySelector('.btns').innerHTML = '<button class="btn xs" data-dismiss>Bildirimi Sil</button>';
      card.querySelector('[data-dismiss]')?.addEventListener('click', () => { card.remove(); syncBellFromDom(); });
      try { loadAppointmentsForCurrent(); } catch {}
    } catch { btn.disabled = false; btn.textContent = 'Onayla'; }
  });

  card.querySelector('[data-action="reject"]')?.addEventListener('click', async (e) => {
    e.stopPropagation();
    const btn = e.currentTarget;
    btn.disabled = true;
    btn.textContent = '...';
    try {
      await apiPost('/api/calendar/update-appointment.php', { id: it.id, status: 'cancelled' });
      card.querySelector('.noti-hd').textContent = '❌ Reddedildi';
      card.querySelector('.btns').innerHTML = '<button class="btn xs" data-dismiss>Bildirimi Sil</button>';
      card.querySelector('[data-dismiss]')?.addEventListener('click', () => { card.remove(); syncBellFromDom(); });
      try { loadAppointmentsForCurrent(); } catch {}
    } catch { btn.disabled = false; btn.textContent = 'Reddet'; }
  });

  body.prepend(card);
  playNoti();
  syncBellFromDom();
}

function startNotificationPolling() {
  if (_notifPollTimer) clearInterval(_notifPollTimer);
  // İlk 5sn bekle, sonra her 15sn
  setTimeout(() => {
    pollNewAppointments();
    _notifPollTimer = setInterval(pollNewAppointments, 15000);
  }, 5000);
}

/* =================== STAFF isimlerini kur =================== */

function rebuildStaffNamesFromDocs(){
  const arr = [];
  const fromSub = STAFF_DOCS.map(x => (x.data?.name || "").trim()).filter(Boolean);
  if (fromSub.length) arr.push(...fromSub);
  arr.unshift(OWNER);
  STAFF_NAMES = uniqueNames(arr);
  if (!STAFF_NAMES.length) STAFF_NAMES = [OWNER];
  if (!selectedStaff.length) selectedStaff = [...STAFF_NAMES];
  buildStaffPopover();
}

/* =================== Booking yükleme (PHP API) =================== */

function dayStart(d){ return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0,0,0,0); }
function dayEnd(d){ return new Date(d.getFullYear(), d.getMonth(), d.getDate()+1, 0,0,0,0); }
function weekStart(d){ const s=new Date(d); s.setDate(s.getDate()-s.getDay()); return dayStart(s); }
function weekEnd(d){ const s=weekStart(d); const e=new Date(s); e.setDate(e.getDate()+7); return e; }

// yarış koşullarını engellemek için request id
let _apptsReqId = 0;

async function loadAppointmentsForCurrent(){
  const rid = ++_apptsReqId;

  const rangeStart = (view==="day") ? dayStart(current) : weekStart(current);
  const rangeEnd   = (view==="day") ? dayEnd(current)   : weekEnd(current);

  const raw = await apiGet("/api/calendar/appointments.php", {
    start: toSqlDateTimeLocal(rangeStart),
    end:   toSqlDateTimeLocal(rangeEnd)
  });

  // eski istek döndüyse atla
  if (rid !== _apptsReqId) return;

  const data = unwrapPayload(raw);
  if (!data) return;

  const arr = Array.isArray(data) ? data
            : (Array.isArray(data.appointments) ? data.appointments : []);

  BOOKINGS = [];
  BOOKING_MAP.clear();

  for (const item of arr){
    const b = normalizeAppointment(item);
    if (!b || !b.startAt) continue;
    BOOKINGS.push(b);
    BOOKING_MAP.set(bookingKey(b), b);
  }

  (view==="day") ? renderDay() : renderWeek();
}

function watchBookingsForCurrent(){
  loadAppointmentsForCurrent().catch(err=>{
    console.error("[calendar] appointments hata:", err);
  });
}

/* =================== Booking statü güncelle (PHP API) =================== */

async function updateApptStatusApi(b, { status, attended, noShow } = {}) {
  if (!b || !b.id) throw new Error("Randevu kimliği yok.");

  // Hem yeni hem eski backend'lerle uyum için iki alanı da gönderiyoruz.
  const payload = { id: String(b.id), appointmentId: String(b.id) };

  // noShow true ise status otomatik "no_show"
  if (typeof noShow === "boolean" && noShow) {
    payload.status = "no_show";
  } else if (status) {
    payload.status = status;
  }

  if (typeof attended === "boolean") {
    payload.attended = attended;
  }

  const rawResp = await apiPost("/api/calendar/update-appointment.php", payload);
  if (!rawResp || rawResp.ok !== true) {
    throw new Error(rawResp?.error || rawResp?.message || "Randevu gÃ¼ncellenemedi.");
  }
  const resp = unwrapPayload(rawResp);
  if (!resp) return;

  // Backend döndürdüyse onu baz al (attended no_show ile otomatik 0 çekilebilir)
  const newStatus = resp.status ?? payload.status ?? null;
  let newAtt = (resp.attended !== undefined) ? resp.attended
            : (payload.attended !== undefined ? payload.attended : undefined);

  // no_show gönderildiyse attended boş olsa bile false varsay
  if (newStatus === "no_show" && newAtt === undefined) newAtt = false;

  const key = bookingKey(b);
  const existing = BOOKING_MAP.get(key);

  if (existing) {
    if (newStatus) existing.status = newStatus;
    if (newAtt !== undefined) existing.attended = newAtt;
    BOOKING_MAP.set(key, existing);

    // BOOKINGS array'indeki referansı da güncelle (renderDay/renderWeek bunu kullanıyor)
    const idx = BOOKINGS.findIndex(x => bookingKey(x) === key);
    if (idx !== -1) {
      if (newStatus) BOOKINGS[idx].status = newStatus;
      if (newAtt !== undefined) BOOKINGS[idx].attended = newAtt;
    }
  }

  (view === "day") ? renderDay() : renderWeek();
  return BOOKING_MAP.get(key) || existing || b;
}

async function cancelAppointment(b){
  await updateApptStatusApi(b, { status:"cancelled" });
}

/* =================== Scroll helper =================== */

function scrollToStart(){
  requestAnimationFrame(()=>{
    const cal = document.querySelector('.calendar');
    if (cal) { cal.scrollLeft = 0; requestAnimationFrame(()=> cal.scrollLeft = 0); }
    const week = document.getElementById('weekView');
    if (week) { week.scrollLeft = 0; requestAnimationFrame(()=> week.scrollLeft = 0); }
  });
}

/* =================== BOOKING PANEL =================== */

function toastMini(msg){ try{ console.log(msg); }catch{} }

function ensureBookingPanel(){
  let el = document.getElementById('bkPanel');
  if (!el){
    el = document.createElement('aside');
    el.id = 'bkPanel';
    el.className = 'drawer';
    el.innerHTML = `
      <div class="drawer-head">
        <h3 id="bkTitle">Randevu</h3>
        <button class="icon-btn" id="bkClose" aria-label="Kapat">✕</button>
      </div>
      <div class="drawer-body" id="bkBody"></div>
      <div class="drawer-footer" id="bkFooter">
        <button class="btn detail" id="bkHide" hidden>Takvimden Sil</button>
        <button class="btn yes" id="bkCame" hidden>Evet, geldi</button>
        <button class="btn no" id="bkNoShow" hidden>Gelmedi</button>
        <button class="btn approve" id="bkApprove" hidden>Onayla</button>
        <button class="btn reject" id="bkReject" hidden>İptal Et</button>
      </div>
    `;
    document.body.appendChild(el);
  }

  if (el.dataset.bound) return;
  el.dataset.bound = "1";

  $('#bkClose')?.addEventListener('click', closeAllModals);

  el.querySelector('#bkFooter')?.addEventListener('click', async (ev)=>{
    const btn = ev.target.closest('button'); if(!btn) return;
    const key = el.dataset.key;
    const b   = BOOKING_MAP.get(key);
    if(!b) return;

    if (el.dataset.busy === '1') return;
    const setBusy = (v)=>{
      el.dataset.busy = v ? '1' : '0';
      try{
        // tüm footer butonlarını kilitle
        el.querySelectorAll('#bkFooter button').forEach(x=> x.disabled = !!v);
      }catch{}
    };

    try{
      const blocked = isBlockedBooking(b);
      if (btn.id === 'bkApprove'){
        if (blocked) {
          alert('Dolu gösterilen zaman aralığı onaylanamaz.');
          return;
        }
        setBusy(true);
        const fresh = await updateApptStatusApi(b, { status:"approved" });
        toastMini("Randevu onaylandı.");
        openBookingPanel(fresh || { ...b, status:"approved" });
      }
      else if (btn.id === 'bkReject'){
        const msg = blocked
          ? "Bu dolu işaretini kaldırmak istediğinize emin misiniz?"
          : (b.status === 'approved')
            ? "Bu randevuyu iptal etmek istediğinize emin misiniz?"
            : "Bu randevu isteğini reddetmek istediğinize emin misiniz?";
        if(!confirm(msg)) return;
        setBusy(true);
        await cancelAppointment(b);
        toastMini(blocked ? "Dolu işareti kaldırıldı." : "Randevu iptal edildi.");
        closeAllModals();
      }
      else if (btn.id === 'bkCame'){
        setBusy(true);
        await updateApptStatusApi(b, { attended:true });
        toastMini("Katılım kaydedildi.");
        closeAllModals();
      }
      else if (btn.id === 'bkNoShow'){
        setBusy(true);
        await updateApptStatusApi(b, { status:"no_show", attended:false, noShow:true });
        toastMini("Gelmedi olarak işaretlendi.");
        closeAllModals();
      }
      else if (btn.id === 'bkHide'){
        HIDDEN_BOOKINGS.add(key);
        persistHidden();
        (view==="day") ? renderDay() : renderWeek();
        toastMini("Randevu görünümden kaldırıldı.");
        closeAllModals();
      }
    }catch(err){
      console.warn('[bkPanel]', err);
      alert(err?.message || 'İşlem tamamlanamadı. Lütfen yeniden deneyin.');
    }finally{
      setBusy(false);
    }
  });
}

function statusBadge(status){
  const s = (status||"pending");
  if (s==="blocked") return "Dolu";
  if (s==="approved") return "Onaylandı";
  if (s==="cancelled" || s==="canceled") return "İptal";
  if (s==="no_show") return "Gelmedi";
  return "Onay bekliyor";
}

/* =================== Booking panel aç =================== */

function openBookingPanel(b){
  ensureBookingPanel();
  const key = bookingKey(b);
  const pnl = $('#bkPanel');

  const start = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt || Date.now());
  const end   = (b.endAt   instanceof Date) ? b.endAt :
                new Date(start.getTime() + (b.totalMin||b.durationMin||30)*60000);
  const staff = bookingStaffName(b);
  const title = labelFromBooking(b);
  const status = (b.status||"pending");
  const blocked = isBlockedBooking(b);

  const tel10  = normalizeCustomerPhone(b.customer||{});
  const telStr = tel10 ? `+90 ${tel10}` : "—";
  const priceNum = priceFromBooking(b);
  const price    = (priceNum != null)
    ? `₺${priceNum.toLocaleString('tr-TR')}`
    : "—";

  pnl.dataset.key = key;
  $('#bkTitle').textContent = blocked ? "Dolu Zaman" : "Randevu Detayı";
  $('#bkBody').innerHTML = `
    <div class="field">
      <div class="label">${blocked ? 'Durum' : 'Müşteri'}</div>
      <div class="input readonly"><span>${escapeHtml(blocked ? 'Bu zaman aralığı dolu gösterildi' : (b.customer?.name || b.customer?.fullName || b.customer?.displayName || "-"))}</span></div>
    </div>
    <div class="field">
      <div class="label">${blocked ? 'Not' : 'Telefon'}</div>
      <div class="input readonly"><span>${escapeHtml(blocked ? (b.notes || 'Dolu') : telStr)}</span></div>
    </div>
    <div class="field">
      <div class="label">${blocked ? 'Blok Türü' : 'Hizmet(ler)'}</div>
      <div class="input readonly"><span>${escapeHtml(blocked ? 'Dolu göster' : title)}</span></div>
    </div>
    <div class="field">
      <div class="label">${blocked ? 'Ücret' : 'Ücret'}</div>
      <div class="input readonly"><span>${blocked ? '—' : price}</span></div>
    </div>
    <div class="field">
      <div class="label">Tarih & Saat</div>
      <div class="input readonly"><span>${start.toLocaleDateString("tr-TR")} • ${fmtHM(start)} – ${fmtHM(end)}</span></div>
    </div>
    <div class="field">
      <div class="label">Personel</div>
      <div class="input readonly"><span>${escapeHtml(staff)}</span></div>
    </div>
    <div class="total">
      <div>Durum</div>
      <strong>${statusBadge(status)}${b.attended===true ? " • Geldi" : ""}</strong>
    </div>
  `;

  const approveBtn = $('#bkApprove');
  const rejectBtn  = $('#bkReject');
  const cameBtn    = $('#bkCame');
  const noBtn      = $('#bkNoShow');
  const hideBtn    = $('#bkHide');

  approveBtn.hidden = true;
  rejectBtn.hidden  = true;
  cameBtn.hidden    = true;
  noBtn.hidden      = true;
  hideBtn.hidden    = true;
  hideBtn.disabled  = false;
  rejectBtn.textContent = blocked ? 'Dolu İşaretini Kaldır' : 'İptal Et';

  const pastNeedsAttend = (status === 'approved') && isOverdue(b) && b.attended !== true;
  const pastApproved    = (status === 'approved') && isPastBooking(b);

  if (blocked) {
    approveBtn.hidden = true;
    rejectBtn.hidden  = false;
    cameBtn.hidden    = true;
    noBtn.hidden      = true;
    hideBtn.hidden    = false;
  } else if (status === 'approved'){
    if (pastApproved){
      rejectBtn.hidden = true;
      hideBtn.hidden   = false;
    }else{
      rejectBtn.hidden = false;
    }
    if (pastNeedsAttend){ cameBtn.hidden = false; noBtn.hidden = false; }
  } else {
    approveBtn.hidden = false;
    rejectBtn.hidden  = false;
    hideBtn.hidden    = true;
  }

  openModal({ id:'bkPanel', panelClassOpen:'open' });
}

/* =================== GÜN GÖRÜNÜMÜ =================== */

let NOW_LINE_TIMER = null;

function addOrUpdateNowLine(){
  const today = new Date(); today.setHours(0,0,0,0);
  const cur0  = new Date(current); cur0.setHours(0,0,0,0);
  $$(".now-line").forEach(n=> n.remove());
  if (today.getTime() !== cur0.getTime()) return;

  selectedStaff.forEach(name=>{
    const col = DAY_COL_MAP.get(name);
    if(!col) return;
    const line = document.createElement("div");
    line.className = "now-line";
    col.appendChild(line);
  });
  positionNowLine();
  if (NOW_LINE_TIMER) clearInterval(NOW_LINE_TIMER);
  NOW_LINE_TIMER = setInterval(positionNowLine, 60*1000);
}
function positionNowLine(){
  const n = new Date();
  const hh = n.getHours() + n.getMinutes()/60 + n.getSeconds()/3600;
  const top = (Math.max(hh, VSTART) - VSTART) * cellH();
  $$(".now-line").forEach(el=> el.style.top = px(top) + "px");
}

function renderDay(){
  $("#dayView").hidden  = false;
  $("#weekView").hidden = true;

  $("#dateLabel").textContent = fmtTR.format(current);
  $("#dateRange").textContent = "";

  const row  = $("#staffRow");
  const grid = $("#dayGrid");
  row.innerHTML = "";
  grid.innerHTML = "";

  DAY_COL_MAP = new Map();

  const timeHead = document.createElement("div");
  timeHead.className = "time-head";
  row.appendChild(timeHead);

  const CH    = cellH();
  const HOURS = VEND - VSTART;
  const colH  = px(HOURS * CH) + "px";
  document.documentElement.style.setProperty("--calH", colH);

  const timeCol = document.createElement("div");
  timeCol.id = "timeCol";
  timeCol.className = "time-col";
  timeCol.style.height = colH;

  for (let h = VSTART; h < VEND; h++) {
    const t = document.createElement("div");
    t.className = "time-cell";
    t.textContent = `${String(h).padStart(2,'0')}:00`;
    t.style.height = px(CH) + "px";
    timeCol.appendChild(t);
  }
  const tend = document.createElement("div");
  tend.className = "time-end";
  tend.textContent = "24:00";
  timeCol.appendChild(tend);

  grid.appendChild(timeCol);

  selectedStaff.forEach(name=>{
    const {open,start,end} = hoursFor(name, current);

    // STAFF_DOCS'tan color al
    const staffDoc   = STAFF_DOCS.find(s => (s.data?.name||"").trim() === name.trim());
    const staffColor = filterGreen(staffDoc?.data?.color || avatarColorCal(name));

    const ini       = initials(name);
    // Webey ana rengine sabitle - kullanıcı tanımlı renk varsa onu kullan, yoksa turkuaz
    const safeColor = (staffColor && staffColor !== '#16a34a' && staffColor !== '#059669') ? staffColor : '#0ea5b3';
    const avatarHtml = `<div class="avatar" style="background:${escapeHtml(safeColor)}">${ini}</div>`;

    const h=document.createElement("div");
    h.className="staff-head";
    h.dataset.head=name;
    h.innerHTML = `
      ${avatarHtml}
      <div class="meta">
        <div class="name">${escapeHtml(name)}</div>
        <div class="sub">${ open ? `${floatToHM(start)}–${floatToHM(end)}` : "Kapalı" }</div>
      </div>`;
    row.appendChild(h);

    const c=document.createElement("div");
    c.className="staff-col";
    c.dataset.staff=name;
    c.style.height = colH;

    for (let hh = VSTART; hh < VEND; hh++) {
      const cell=document.createElement("div");
      cell.className="hour-cell";
      cell.style.height = px(CH) + "px";
      c.appendChild(cell);
    }

    if(open){
      addOff(c, VSTART, start);
      addOff(c, end, VEND);
    }else{
      c.classList.add("closed");
      const full=document.createElement("div");
      full.className="offband";
      full.style.top="0";
      full.style.height=colH;
      c.appendChild(full);
    }

    DAY_COL_MAP.set(name, c);
    grid.appendChild(c);
  });

  {
    const cal   = document.querySelector('.calendar');
    const calW  = (cal?.clientWidth || 0);
    const timeW = cssVarPx('--timeW', document.documentElement) || 80;
    const minColW = 220;

    const nStaff = Math.max(1, selectedStaff.length);
    const avail  = Math.max(0, calW - timeW);

    let visible;
    if (calW <= 0) {
      visible = Math.min(2, nStaff);
    } else {
      const fit = Math.max(1, Math.floor(avail / minColW));
      visible = Math.min(5, fit);
      if (nStaff >= 2) visible = Math.max(2, visible);
      visible = Math.min(visible, nStaff);
    }

    const colW = Math.max(minColW, Math.floor(avail / Math.max(1, visible)));

    const tpl  = `var(--timeW) repeat(${visible}, ${colW}px)`;
    const auto = `${colW}px`;
    row.style.gridTemplateColumns  = tpl;
    grid.style.gridTemplateColumns = tpl;
    row.style.gridAutoColumns      = auto;
    grid.style.gridAutoColumns     = auto;

    const min = `calc(var(--timeW) + ${visible*colW}px)`;
    row.style.minWidth  = min;
    grid.style.minWidth = min;

    if (cal) cal.style.overflowX = 'auto';
  }

  addOrUpdateNowLine();
  drawDayBookings();
  scrollToStart();
}

function drawDayBookings(){
  const sDay = dayStart(current), eDay = dayEnd(current);

  BOOKINGS
    .filter(b => {
      if (!b.startAt) return false;
      const d = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
      return d >= sDay && d < eDay;
    })
    .filter(b => {
      const st = (b.status || 'pending');
      return st !== 'cancelled' && st !== 'canceled';
    })
    .forEach(b => {
      if (!b.startAt) return;

      const key = bookingKey(b);
      if (HIDDEN_BOOKINGS.has(key)) return;

      const start = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
      const end   = (b.endAt   instanceof Date) ? b.endAt :
                    new Date(start.getTime() + (b.totalMin||b.durationMin||30)*60000);

      const stf = bookingStaffName(b);
      const col = DAY_COL_MAP.get(stf) || $(`.staff-col[data-staff="${cssEscape(stf)}"]`);
      if (!col) return;

      const sh = start.getHours() + start.getMinutes() / 60;
      const eh = end.getHours()   + end.getMinutes()   / 60;

      const top = (Math.max(sh, VSTART) - VSTART) * cellH();
      const h   = Math.max(14, (Math.min(eh, VEND) - Math.max(sh, VSTART)) * cellH() - 6);

      const el = document.createElement("div");
      el.className = "booking";
      el.setAttribute("role","button");
      el.setAttribute("tabindex","0");
      el.dataset.key = key;

      const s = (b.status || "pending");
      if (s === 'approved') el.classList.add('approved');
      if (isOverdue(b))     el.classList.add('overdue');
      if (isLate(b))        el.classList.add('late');

      const serviceName  = labelFromBooking(b);
      const customerName = isBlockedBooking(b)
        ? (b.notes || 'Dolu')
        : (b.customer?.name || b.customer?.fullName || b.customer?.displayName || "");
      const timeStr      = `${fmtHM(start)} – ${fmtHM(end)}`;

      if (h < 40) {
        el.classList.add("compact");
        el.innerHTML = `
          <div class="b-line">
            <span class="b-time">${timeStr}</span>
            <span class="b-dot">•</span>
            <span class="b-label">${escapeHtml(serviceName)}</span>
          </div>
        `;
      } else {
        el.innerHTML = `
          <div class="b-title">${escapeHtml(serviceName)}</div>
          <div class="b-time">
            ${timeStr}${customerName ? " • " + escapeHtml(customerName) : ""}
          </div>
        `;
      }

      el.style.top    = px(top) + "px";
      el.style.height = px(h) + "px";

      el.addEventListener('click', () => {
        const fresh = BOOKING_MAP.get(key) || b;
        openBookingPanel(fresh);
      });
      el.addEventListener('keydown', (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          const fresh = BOOKING_MAP.get(key) || b;
          openBookingPanel(fresh);
        }
      });

      col.appendChild(el);
    });
}

/* =================== HAFTA GÖRÜNÜMÜ =================== */

function startOfWeek(d){
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - x.getDay());
  return x;
}
function endOfWeek(d){
  const s = startOfWeek(d);
  const e = new Date(s);
  e.setDate(s.getDate()+6);
  return e;
}

function renderWeek(){
  $("#dayView").hidden  = true;
  $("#weekView").hidden = false;

  const s = startOfWeek(current), e = endOfWeek(current);
  $("#dateLabel").textContent = `${dShort.format(s)} – ${dShort.format(e)}`;
  $("#dateRange").textContent = "";

  const head = $("#wkHead");
  const grid = $("#wkGrid");
  head.innerHTML = "";
  grid.innerHTML = "";

  const left = document.createElement("div");
  left.className = "left";
  left.textContent = "";
  head.appendChild(left);

  for(let i=0;i<7;i++){
    const d=new Date(s); d.setDate(s.getDate()+i);

    let sub = "Kapalı";
    const effBase = defaultWeek?.[d.getDay()];
    if (effBase?.open && Array.isArray(effBase.ranges) && effBase.ranges.length){
      const r = effBase.ranges[0];
      sub = `${m2t(r.startMin)}–${m2t(r.endMin)}`;
    }

    const btn = document.createElement("button");
    btn.className = "wk-day-btn";
    btn.innerHTML = `<div class="date">${DAY_TR_SHORT[d.getDay()]} ${String(d.getDate()).padStart(2,"0")}</div>
                     <div class="sub">${sub}</div>`;
    btn.addEventListener("click", ()=>{
      current = new Date(d);
      setView("day");
    });
    const day = document.createElement("div");
    day.className = "wk-day";
    day.appendChild(btn);
    head.appendChild(day);
  }

  selectedStaff.forEach(name=>{
    // STAFF_DOCS'tan color al
    const staffDoc   = STAFF_DOCS.find(s => (s.data?.name||"").trim() === name.trim());
    const staffColor = filterGreen(staffDoc?.data?.color || avatarColorCal(name));

    const wkIni      = initials(name);
    const safeColorWk = (staffColor && staffColor !== '#16a34a' && staffColor !== '#059669') ? staffColor : '#0ea5b3';
    const avatarHtml = `<div class="avatar" style="background:${escapeHtml(safeColorWk)}">${wkIni}</div>`;

    const staffCell = document.createElement("div");
    staffCell.className = "wk-staff";
    staffCell.innerHTML = `${avatarHtml}<span class="wk-staff-name">${escapeHtml(name)}</span>`;
    staffCell.dataset.staff = name;
    grid.appendChild(staffCell);

    for(let i=0;i<7;i++){
      const d=new Date(s); d.setDate(s.getDate()+i);
      const col = document.createElement("div");
      col.className = "wk-col";
      const inner = document.createElement("div");
      inner.className = "wk-col-inner";
      inner.dataset.staff = name;
      inner.dataset.date  = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;

      const idx = d.getDay();
      const eff = effectiveDayForStaff(idx, name);
      if(!eff.open){ inner.classList.add("closed"); }
      col.appendChild(inner);
      grid.appendChild(col);
    }
  });

  const wkView = $("#weekView");
  const headH  = $("#wkHead").getBoundingClientRect().height || 0;
  const rowH = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--wkRowH')) || 220;
  const visibleRows = 2;
  wkView.style.maxHeight = px(headH + visibleRows*rowH + 24) + "px";
  wkView.style.overflowY = (selectedStaff.length > visibleRows) ? "auto" : "visible";

  drawWeekBookings();
  scrollToStart();
}

function drawWeekBookings(){
  const ws = weekStart(current), we = weekEnd(current);

  const cellMap = {};
  $$(".wk-col-inner").forEach(el=>{
    cellMap[`${el.dataset.staff}__${el.dataset.date}`] = el;
  });

  const seen = new Set();

  BOOKINGS
    .filter(b=>{
      if (!b.startAt) return false;
      const d = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
      return d >= ws && d < we;
    })
    .filter(b => (b.status||'pending')!=='cancelled' && (b.status||'pending')!=='canceled')
    .forEach(b=>{
      const start = (b.startAt instanceof Date) ? b.startAt : new Date(b.startAt);
      const stf   = bookingStaffName(b);
      const keyAll= bookingKey(b);
      if (HIDDEN_BOOKINGS.has(keyAll)) return;

      const key   = `${stf}__${start.getFullYear()}-${pad(start.getMonth()+1)}-${pad(start.getDate())}`;
      const cell  = cellMap[key];
      if(!cell) return;

      const serviceName  = labelFromBooking(b);
      const customerName = isBlockedBooking(b)
        ? (b.notes || 'Dolu')
        : (b.customer?.name || b.customer?.fullName || b.customer?.displayName || "Müşteri");
      const sign  = `${key}|${fmtHM(start)}|${serviceName.toLowerCase()}`;
      if (seen.has(sign)) return;
      seen.add(sign);

      const chip  = document.createElement("button");
      chip.className = "wk-chip";
      chip.type = "button";
      chip.innerHTML = `
        <div class="wk-time">${fmtHM(start)}</div>
        <div class="wk-service">${escapeHtml(serviceName)}</div>
        <div class="wk-customer">${escapeHtml(customerName)}</div>
      `;

      const s = (b.status||"pending");
      if (s==='approved') chip.classList.add('approved');
      if (isOverdue(b)) chip.classList.add('overdue');
      if (isLate(b))    chip.classList.add('late');

      chip.addEventListener('click', () => {
        const fresh = BOOKING_MAP.get(bookingKey(b)) || b;
        openBookingPanel(fresh);
      });

      cell.appendChild(chip);
    });
}

/* =================== VIEW SWITCH =================== */

function syncViewMenu() {
  const label = (view === "week" ? "Hafta" : "Gün");
  $$(".view-item").forEach(btn => {
    const isActive = btn.dataset.view === label;
    btn.classList.toggle("selected", isActive);
  });
}

function setView(next){
  view = next;
  try { localStorage.setItem("calendar_view", view); } catch {}
  $("#currentView").textContent = (view==="day" ? "Gün" : "Hafta");
  syncViewMenu();
  if(view==="day") renderDay(); else renderWeek();
  watchBookingsForCurrent();
}

function bindViewSelect(){
  const chip = $("#viewChip");
  const pop  = $("#viewPop");
  if(!chip || !pop) return;

  if (!chip.dataset.bound){
    chip.dataset.bound = "1";
    chip.addEventListener("click", ()=>{
      const willOpen = !pop.classList.contains("open");
      pop.classList.toggle("open");
      chip.setAttribute('aria-expanded', String(willOpen));
    });

    document.addEventListener("mousedown",(e)=>{
      if(pop?.classList.contains("open") && !pop.contains(e.target) && !chip.contains(e.target)){
        pop.classList.remove("open");
        chip.setAttribute('aria-expanded','false');
      }
    });

    $$(".view-item").forEach(btn=>{
      btn.addEventListener("click", ()=>{
        const v = btn.dataset.view === "Hafta" ? "week" : "day";
        setView(v);
        pop.classList.remove("open");
        chip.setAttribute('aria-expanded','false');
      });
    });
  }
}

/* =================== PERSONEL POPUP =================== */

function buildStaffPopover(){
  const wrap = $("#staffChkWrap");
  const btn  = $("#staffBtn");
  const pop  = $("#staffPop");
  if(!wrap || !btn || !pop) return;

  wrap.innerHTML = `
    <label class="chk"><input type="checkbox" id="allChk" checked><span>Tümünü seç</span></label>
    <div id="staffChkList"></div>
  `;
  const list = $("#staffChkList");
  list.innerHTML = "";
  STAFF_NAMES.forEach(n=>{
    const id = "st_"+n.replace(/\s+/g,"_");

    const staffDoc   = STAFF_DOCS.find(s => (s.data?.name||"").trim() === n.trim());
    const staffColor = filterGreen(staffDoc?.data?.color || avatarColorCal(n));
    const ini        = initials(n);

    const safeColorSp = (staffColor && staffColor !== '#16a34a' && staffColor !== '#059669') ? staffColor : '#0ea5b3';
    const avatarHtml = `<span class="sp-avatar" style="background:${escapeHtml(safeColorSp)}">${ini}</span>`;

    const row=document.createElement("label");
    row.className = "chk";
    row.innerHTML = `<input type="checkbox" id="${id}" class="staffChk" data-name="${n}" ${selectedStaff.includes(n)?"checked":""}>
                     ${avatarHtml}
                     <span>${escapeHtml(n)}</span><span class="dot"></span>`;
    list.appendChild(row);
  });

  const all = $("#allChk");
  const boxes = ()=> $$(".staffChk");
  const syncAll = ()=>{
    const list = boxes();
    const allChecked  = list.every(b => b.checked);
    const noneChecked = list.every(b => !b.checked);
    all.checked = allChecked;
    all.indeterminate = !allChecked && !noneChecked;
  };
  syncAll();

  all.addEventListener("change",()=>{ boxes().forEach(b=> b.checked = all.checked); });

  if(!btn.dataset.bound){
    btn.dataset.bound="1";
    btn.addEventListener("click",()=>{
      const willOpen = !pop.classList.contains("open");
      pop.classList.toggle("open");
      btn.setAttribute('aria-expanded', String(willOpen));
    });
    document.addEventListener("mousedown",(e)=>{
      if(pop.classList.contains("open") && !pop.contains(e.target) && !btn.contains(e.target)){
        pop.classList.remove("open");
        btn.setAttribute('aria-expanded','false');
      }
    });
  }

  const applyBtn = $("#applyStaff");
  if (applyBtn && !applyBtn.dataset.bound) {
    applyBtn.dataset.bound = "1";
    applyBtn.addEventListener("click",()=>{
      const sel = boxes().filter(b=>b.checked).map(b=>b.dataset.name);
      if (!sel.length) {
        // 0 personel seçilemez — butonu salla ve hata göster
        applyBtn.textContent = "⚠ En az 1 personel seçin";
        applyBtn.style.background = "#ef4444";
        setTimeout(()=>{
          applyBtn.textContent = "UYGULA";
          applyBtn.style.background = "";
        }, 2000);
        return;
      }
      selectedStaff = sel;
      pop.classList.remove("open");
      btn.setAttribute('aria-expanded','false');
      (view==="day") ? renderDay() : renderWeek();
      watchBookingsForCurrent();
    });
  }

  list.addEventListener("change", syncAll);
}

/* =================== TARİH NAV =================== */

function bindDateNav(){
  $("#prevDay")?.addEventListener("click",()=>{
    current.setDate(current.getDate() + (view==="week" ? -7 : -1));
    (view==="day") ? renderDay() : renderWeek();
    watchBookingsForCurrent();
  });
  $("#nextDay")?.addEventListener("click",()=>{
    current.setDate(current.getDate() + (view==="week" ? 7 : 1));
    (view==="day") ? renderDay() : renderWeek();
    watchBookingsForCurrent();
  });
  $("#todayBtn")?.addEventListener("click", ()=>{
    const now = new Date();
    current = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    (view==="day") ? renderDay() : renderWeek();
    watchBookingsForCurrent();
  });
}

/* =================== MINI TAKVİM =================== */

let calCursor = new Date(current.getFullYear(), current.getMonth(), 1);

function bindMiniCalendar(){
  const dateWrap = document.getElementById('dateLabelWrap') || document.querySelector('.date-chip');
  if(!dateWrap || dateWrap.dataset.bound) return;
  dateWrap.dataset.bound = "1";

  dateWrap.addEventListener("click",()=>{
    const pop = document.getElementById('calendarPopover') || document.querySelector('.center-pop');
    const willOpen = !pop?.classList.contains("open");
    closeAllModals();
    if (willOpen && pop) {
      pop.classList.add("open");
      dateWrap.setAttribute('aria-expanded','true');
      pop.setAttribute('aria-hidden','false');
      calCursor = new Date(current.getFullYear(), current.getMonth(), 1);
      drawMini(calCursor);
    }
  });

  document.addEventListener("mousedown",(e)=>{
    const pop = document.getElementById('calendarPopover') || document.querySelector('.center-pop');
    if(pop?.classList.contains("open") && !pop.contains(e.target) && !dateWrap?.contains(e.target)){
      pop.classList.remove("open");
      pop.setAttribute('aria-hidden','true');
      dateWrap?.setAttribute('aria-expanded','false');
    }
  });

  $("#calPrev")?.addEventListener("click",(e)=>{ e.stopPropagation(); calCursor.setMonth(calCursor.getMonth()-1); drawMini(calCursor); });
  $("#calNext")?.addEventListener("click",(e)=>{ e.stopPropagation(); calCursor.setMonth(calCursor.getMonth()+1); drawMini(calCursor); });
}

function drawMini(ref){
  const panel = document.getElementById('calendarPopover') || document.querySelector('.center-pop');
  if(!panel) return;

  const monthLbl = panel.querySelector('.calendar-head strong');
  const grid = panel.querySelector('.calendar-grid');

  if (monthLbl) monthLbl.textContent = monthTR(ref);
  if (!grid) return;
  grid.innerHTML = "";

  const y=ref.getFullYear(), m=ref.getMonth();
  const start=new Date(y,m,1), end=new Date(y,m+1,0);

  const lead = (start.getDay() + 6) % 7;
  const total = lead + end.getDate();
  const cells = Math.ceil(total/7)*7;

  const today=new Date(); today.setHours(0,0,0,0);

  for(let i=0;i<cells;i++){
    const day=i-lead+1; const cell=document.createElement("div"); cell.className="cell";
    if(day>0 && day<=end.getDate()){
      const d=new Date(y,m,day); const eq = d.toDateString()===current.toDateString();
      cell.textContent = day;
      if(today.toDateString()===d.toDateString()) cell.classList.add("today");
      if(eq) cell.classList.add("selected");
      cell.addEventListener("click",()=>{
        current=new Date(y,m,day);
        (view==="day") ? renderDay() : renderWeek();
        const pop = document.getElementById('calendarPopover') || document.querySelector('.center-pop');
        pop?.classList.remove('open');
        pop?.setAttribute('aria-hidden','true');
        (document.getElementById('dateLabelWrap') || document.querySelector('.date-chip'))?.setAttribute('aria-expanded','false');
        watchBookingsForCurrent();
      });
    }else cell.style.visibility="hidden";
    grid.appendChild(cell);
  }
}

/* =================== LOGOUT & PROFİL =================== */

function bindProfile(){
  $("#bmLogout")?.addEventListener("click", async ()=>{
    try { await apiPost("/api/auth/logout.php", {}); } catch {}
    location.href="index.html";
  });

  document.addEventListener('click', (e)=>{
    if (e.target.closest('.rail')) return;
    const trigger = e.target.closest('#bmOpen, #topProfileBtn, [data-open="bm"]');
    if(!trigger) return;
    e.preventDefault();
    const bm = document.getElementById('bmModal');
    bm?.classList.add('show');
    bm?.setAttribute('aria-hidden','false');
  }, true);

  $("#bmClose")?.addEventListener('click', closeAllModals);
}

/* =================== CUSTOMER MODAL FALLBACK =================== */

function openCustomerInfoFallback(customer={}, ctx={}){
  const wrap  = document.getElementById('customerModalWrap');
  const modal = document.getElementById('customerModal');
  const body  = document.getElementById('ciBody');

  if (body){
    const name = customer?.name || customer?.fullName || customer?.displayName || '—';
    const tel10  = normalizeCustomerPhone(customer);
    body.innerHTML = `
      <div style="display:grid; gap:8px">
        <div><strong>Ad Soyad:</strong> ${escapeHtml(name)}</div>
        <div><strong>Telefon:</strong> ${escapeHtml(tel10 || "—")}</div>
        <div class="muted">Detay modülü yüklenemedi. Özet gösteriliyor.</div>
      </div>
    `;
  }
  wrap?.setAttribute('aria-hidden','false');
  modal?.classList.add('open');
  document.getElementById('ciClose')?.addEventListener('click', ()=>{
    modal?.classList.remove('open');
    wrap?.setAttribute('aria-hidden','true');
  }, { once:true });
}

/* =================== İptal Bildirimleri (Poll) =================== */

let _cancelPollTimer = null;
let _cancelSeenIds   = new Set();

async function pollCancellationRequests() {
  try {
    const res = await apiGet('/api/calendar/cancellation-requests.php');
    if (!res) return; // 401 → redirectToLogin zaten çağrıldı

    if (!res.ok) {
      console.warn('[cancellationPoll] API error:', res.error);
      return;
    }

    const _calCancelItems = res.data?.items ?? res.items ?? [];
    if (!Array.isArray(_calCancelItems)) {
      console.warn('[cancellationPoll] items is not array:', res);
      return;
    }

    // Sadece daha önce gösterilmemiş olanları push et
    const newItems = _calCancelItems.filter(it => it && it.id && !_cancelSeenIds.has('cancel_' + it.id));
    newItems.forEach(it => {
      _cancelSeenIds.add('cancel_' + it.id);
      pushCancellationNotif(it);
    });

    // Artık DB'de olmayan (admin işlem yapmış) kartları temizle
    const liveIds = new Set(_calCancelItems.map(it => 'cancel_' + it.id));
    document.querySelectorAll('[data-cancel-id]').forEach(card => {
      const cid = card.dataset.cancelId;
      if (cid && !liveIds.has(cid)) {
        card.remove();
        syncBellFromDom();
      }
    });
  } catch(err) {
    console.warn('[cancellationPoll] exception:', err);
  }
}

function pushCancellationNotif(it) {
  ensureNotifyPanel();
  const body = NOTIFY_BODY();
  if (!body) return;
  body.querySelector('.notif-empty')?.remove();

  // Aynı randevu için zaten kart varsa güncelle
  const existingCard = body.querySelector(`[data-cancel-id="cancel_${it.id}"]`);
  if (existingCard) return;

  const card = document.createElement('div');
  card.className = 'noti-card';
  card.dataset.cancelId = 'cancel_' + it.id;
  card.style.cssText = 'border-left:3px solid #f59e0b; border-radius:12px; padding:14px 16px; margin-bottom:10px; background:#fff; box-shadow:0 2px 10px rgba(0,0,0,.07);';

  const notifTime  = fmtNotifDT(it.cancelledAt || new Date().toISOString());
  const staffTxt   = it.staffName ? ` • ${escapeHtml(it.staffName)}` : '';
  const phoneTxt   = it.customerPhone ? `<span style="color:#6b7280"> • ${escapeHtml(it.customerPhone)}</span>` : '';

  card.innerHTML = `
    <div style="display:flex;align-items:center;gap:6px;margin-bottom:6px">
      <span style="font-size:18px">⚠️</span>
      <span style="font-weight:800;font-size:13px;color:#92400e">Randevu İptal Talebi</span>
    </div>
    <div style="font-size:11px;color:#9ca3af;margin-bottom:8px">${notifTime}</div>
    <div style="background:#fffbeb;border:1px solid #fde68a;border-radius:8px;padding:10px 12px;margin-bottom:10px;font-size:13px;line-height:1.6">
      <div><strong>${escapeHtml(it.customerName || '—')}</strong>${phoneTxt}</div>
      <div style="color:#374151">🗓 ${escapeHtml(it.startFmt || '')}${staffTxt}</div>
      <div style="color:#374151">✂️ ${escapeHtml(it.serviceName || 'Hizmet')}</div>
    </div>
    <div style="font-size:12px;color:#6b7280;margin-bottom:10px">
      Müşteri bu randevuyu iptal etmek istiyor. İptali onaylıyor musunuz?
    </div>
    <div style="display:flex;gap:8px;flex-wrap:wrap">
      <button class="btn xs" data-action="approve-cancel"
        style="flex:1;background:#10b981;color:#fff;border-color:#10b981;font-size:12px;padding:8px 6px;border-radius:8px;font-weight:700;cursor:pointer">
        ✅ Evet, İptali Onayla
      </button>
      <button class="btn xs" data-action="reject-cancel"
        style="flex:1;background:#f3f4f6;color:#374151;border-color:#d1d5db;font-size:12px;padding:8px 6px;border-radius:8px;font-weight:700;cursor:pointer">
        ❌ Hayır, Onaylamıyorum
      </button>
    </div>
    <div class="cancel-notif-result" style="display:none;margin-top:8px;font-size:12px;font-weight:700;text-align:center"></div>`;

  /* ── Onayla ── */
  card.querySelector('[data-action="approve-cancel"]')?.addEventListener('click', async (e) => {
    e.stopPropagation();
    const approveBtn = card.querySelector('[data-action="approve-cancel"]');
    const rejectBtn  = card.querySelector('[data-action="reject-cancel"]');
    const result     = card.querySelector('.cancel-notif-result');
    approveBtn.disabled = true; approveBtn.textContent = '⏳ İşleniyor…';
    rejectBtn.disabled  = true;
    try {
      await apiPost('/api/calendar/approve-cancellation.php', { id: it.id });
      // Butonları gizle, başarı göster
      approveBtn.style.display = 'none';
      rejectBtn.style.display  = 'none';
      result.style.display     = 'block';
      result.style.color       = '#10b981';
      result.innerHTML = '✅ İptal onaylandı. Randevu iptal edildi.';
      card.style.borderLeftColor = '#10b981';
      // Takvimi yenile
      try { loadAppointmentsForCurrent(); } catch {}
      // 6 sn sonra kartı otomatik kaldır
      setTimeout(() => { card.remove(); syncBellFromDom(); }, 6000);
    } catch (err) {
      approveBtn.disabled = false; approveBtn.textContent = '✅ Evet, İptali Onayla';
      rejectBtn.disabled  = false;
      result.style.display  = 'block';
      result.style.color    = '#ef4444';
      result.textContent    = 'Hata: ' + (err.message || 'İşlem başarısız');
    }
  });

  /* ── Onaylama ── */
  card.querySelector('[data-action="reject-cancel"]')?.addEventListener('click', async (e) => {
    e.stopPropagation();
    const approveBtn = card.querySelector('[data-action="approve-cancel"]');
    const rejectBtn  = card.querySelector('[data-action="reject-cancel"]');
    const result     = card.querySelector('.cancel-notif-result');
    rejectBtn.disabled  = true; rejectBtn.textContent = '⏳ İşleniyor…';
    approveBtn.disabled = true;
    try {
      await apiPost('/api/calendar/reject-cancellation.php', { id: it.id });
      approveBtn.style.display = 'none';
      rejectBtn.style.display  = 'none';
      result.style.display     = 'block';
      result.style.color       = '#6b7280';
      result.innerHTML = '🔄 Randevu iptal edilmedi. Durum eski haline döndürüldü.';
      card.style.borderLeftColor = '#6b7280';
      try { loadAppointmentsForCurrent(); } catch {}
      setTimeout(() => { card.remove(); syncBellFromDom(); }, 6000);
    } catch (err) {
      rejectBtn.disabled  = false; rejectBtn.textContent = '❌ Hayır, Onaylamıyorum';
      approveBtn.disabled = false;
      result.style.display  = 'block';
      result.style.color    = '#ef4444';
      result.textContent    = 'Hata: ' + (err.message || 'İşlem başarısız');
    }
  });

  body.prepend(card);
  playNoti();
  syncBellFromDom();
}

function startCancellationPolling() {
  if (_cancelPollTimer) clearInterval(_cancelPollTimer);
  // Hemen başlat, sonra her 10sn
  pollCancellationRequests();
  _cancelPollTimer = setInterval(pollCancellationRequests, 10000);
}

/* =================== FAB (Hızlı İşlemler) =================== */

function toDateInputValue(d){
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
}

function timeStrToMin(v){
  const m = String(v || '').match(/^(\d{2}):(\d{2})$/);
  if (!m) return null;
  return (Number(m[1]) * 60) + Number(m[2]);
}

function minToTimeStr(min){
  const clamped = Math.max(0, Math.min(1439, Number(min || 0)));
  return `${pad(Math.floor(clamped / 60))}:${pad(clamped % 60)}`;
}

function roundUpToQuarter(date = new Date()){
  const total = (date.getHours() * 60) + date.getMinutes();
  const rounded = Math.ceil(total / 15) * 15;
  return Math.min(23 * 60 + 15, rounded);
}

function dateStrFromCurrentOrToday(){
  const today = new Date();
  const candidate = new Date(current);
  const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const currentStart = new Date(candidate.getFullYear(), candidate.getMonth(), candidate.getDate());
  return toDateInputValue(currentStart < todayStart ? today : candidate);
}

function staffDocById(staffId){
  return STAFF_DOCS.find(s => String(s.id) === String(staffId)) || null;
}

function effectiveRangesForStaffId(staffId, dateStr){
  if (!dateStr) return { open:false, ranges:[], label:'Tarih seçin' };
  const dateObj = new Date(`${dateStr}T00:00:00`);
  if (Number.isNaN(dateObj.getTime())) return { open:false, ranges:[], label:'Geçersiz tarih' };
  const idx = dateObj.getDay();
  const base = defaultWeek?.[idx] || { open:false, ranges:[] };
  const override = staffDocById(staffId)?.data?.hoursOverride?.[idx];
  const eff = override ?? base;
  const ranges = (eff?.open && Array.isArray(eff.ranges))
    ? eff.ranges.filter(r => Number.isFinite(r?.startMin) && Number.isFinite(r?.endMin) && r.endMin > r.startMin)
    : [];
  return {
    open: ranges.length > 0,
    ranges,
    label: ranges.length ? ranges.map(r => `${minToTimeStr(r.startMin)} - ${minToTimeStr(r.endMin)}`).join(', ') : 'Kapalı'
  };
}

function isRangeWithinOpenHours(schedule, startMin, endMin){
  if (!schedule?.open || !Array.isArray(schedule.ranges) || !schedule.ranges.length) return false;
  return schedule.ranges.some(r => startMin >= r.startMin && endMin <= r.endMin);
}

function isFabConflictBooking(b){
  const status = String(b?.status || 'pending').toLowerCase();
  return !['cancelled','canceled','rejected','declined','no_show','cancellation_requested'].includes(status);
}

function isBlockedBooking(b){
  const status = String(b?.status || '').toLowerCase();
  if (status === 'blocked') return true;
  if (['cancelled','canceled','rejected','declined','no_show','completed'].includes(status)) return false;
  return String(b?.customer?.name || '').trim() === '[DOLU]';
}

function bookingDateStr(b){
  const start = (b?.startAt instanceof Date) ? b.startAt : new Date(b?.startAt || '');
  if (Number.isNaN(start.getTime())) return '';
  return toDateInputValue(start);
}

function getRangeConflicts({ staffId, dateStr, startMin, endMin }){
  return BOOKINGS.filter(b => {
    if (!isFabConflictBooking(b)) return false;
    if (String(b?.staffId || '') !== String(staffId || '')) return false;
    if (bookingDateStr(b) !== dateStr) return false;
    const bStart = (b?.startAt instanceof Date) ? b.startAt : new Date(b?.startAt || '');
    const bEnd   = (b?.endAt instanceof Date) ? b.endAt : new Date(bStart.getTime() + Number(b?.totalMin || 30) * 60000);
    if (Number.isNaN(bStart.getTime()) || Number.isNaN(bEnd.getTime())) return false;
    const bookingStartMin = (bStart.getHours() * 60) + bStart.getMinutes();
    const bookingEndMin   = (bEnd.getHours() * 60) + bEnd.getMinutes();
    return bookingStartMin < endMin && bookingEndMin > startMin;
  });
}

function setFabFeedback(id, message, tone = 'info'){
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = message || '';
  el.dataset.tone = tone;
  el.hidden = !message;
}

function getQuickApptDuration(){
  const svcSel = document.getElementById('qaService');
  const svcObj = SERVICE_MAP.get(svcSel?.value || '');
  return Number(svcObj?.durationMin || svcObj?.duration_min || 30);
}

function validateRangeForCalendarAction({ staffId, dateStr, startMin, endMin, mode }){
  const saveBtn = document.getElementById(mode === 'quick' ? 'qaSave' : 'btSave');
  const feedbackId = mode === 'quick' ? 'qaFeedback' : 'btFeedback';
  const labels = mode === 'quick'
    ? {
        incomplete: 'Personel, hizmet, tarih ve saat seçildiğinde uygunluk burada gösterilir.',
        past: 'Geçmiş zamana hızlı randevu oluşturulamaz.',
        closed: 'Seçilen gün dükkan veya personel için kapalı. Bu güne hızlı randevu oluşturulamaz.',
        outside: schedule => `Seçilen saat çalışma aralığının dışında. Uygun aralık: ${schedule.label}.`,
        blocked: 'Bu saat aralığı dolu gösterilmiş. Önce dolu işaretini kaldırın.',
        conflict: 'Bu saat aralığında randevu var. Önce mevcut randevuyu iptal etmelisiniz.',
        success: schedule => `Uygun saat aralığı: ${schedule.label}. Randevu seçilen süreyle oluşturulacak.`
      }
    : {
        incomplete: 'Personel, tarih ve saat seçildiğinde bu alanı doğrulayacağız.',
        past: 'Geçmiş zaman dilimi dolu gösterilemez.',
        closed: 'Seçilen gün dükkan veya personel kapalı olduğu için dolu gösterilemez.',
        outside: schedule => `Sadece çalışma saatleri içinde dolu gösterebilirsiniz. Uygun aralık: ${schedule.label}.`,
        blocked: 'Bu saat aralığı zaten dolu gösterilmiş.',
        conflict: 'Bu saat aralığında randevunuz var. Önce randevuyu iptal etmelisiniz.',
        success: schedule => `Seçilen aralık çalışma saati içinde. Uygun aralık: ${schedule.label}.`
      };

  const fail = (message)=>{
    setFabFeedback(feedbackId, message, 'error');
    if (saveBtn) saveBtn.disabled = true;
    return false;
  };

  if (!staffId || !dateStr || startMin == null || endMin == null) {
    setFabFeedback(feedbackId, labels.incomplete, 'info');
    if (saveBtn) saveBtn.disabled = false;
    return true;
  }

  const schedule = effectiveRangesForStaffId(staffId, dateStr);
  const startDate = new Date(`${dateStr}T${minToTimeStr(startMin)}:00`);
  if (Number.isNaN(startDate.getTime()) || startDate < new Date()) {
    return fail(labels.past);
  }
  if (!schedule.open) {
    return fail(labels.closed);
  }
  if (!isRangeWithinOpenHours(schedule, startMin, endMin)) {
    return fail(labels.outside(schedule));
  }

  const conflicts = getRangeConflicts({ staffId, dateStr, startMin, endMin });
  const blocked = conflicts.find(isBlockedBooking);
  if (blocked) {
    return fail(labels.blocked);
  }
  if (conflicts.length) {
    return fail(labels.conflict);
  }

  setFabFeedback(feedbackId, labels.success(schedule), 'success');
  if (saveBtn) saveBtn.disabled = false;
  return true;
}

function validateQuickApptForm(){
  const staffId = document.getElementById('qaStaff')?.value || '';
  const dateStr = document.getElementById('qaDate')?.value || '';
  const timeStr = document.getElementById('qaTime')?.value || '';
  const startMin = timeStrToMin(timeStr);
  const duration = getQuickApptDuration();
  const endMin = (startMin == null) ? null : startMin + duration;
  const ok = validateRangeForCalendarAction({ staffId, dateStr, startMin, endMin, mode: 'quick' });
  if (ok && staffId && dateStr && startMin != null && endMin != null) {
    const schedule = effectiveRangesForStaffId(staffId, dateStr);
    setFabFeedback('qaFeedback', `Uygun saat aralığı: ${schedule.label}. Randevu ${duration} dakika olarak oluşturulacak.`, 'success');
  }
  return ok;
}

function validateBlockTimeForm(){
  const staffId = document.getElementById('btStaff')?.value || '';
  const dateStr = document.getElementById('btDate')?.value || '';
  const startStr = document.getElementById('btStart')?.value || '';
  const endStr = document.getElementById('btEnd')?.value || '';
  const startMin = timeStrToMin(startStr);
  const endMin = timeStrToMin(endStr);
  if (endMin <= startMin) {
    setFabFeedback('btFeedback', 'Bitiş saati başlangıç saatinden sonra olmalı.', 'error');
    const saveBtn = document.getElementById('btSave');
    if (saveBtn) saveBtn.disabled = true;
    return false;
  }
  return validateRangeForCalendarAction({ staffId, dateStr, startMin, endMin, mode: 'block' });
}

function syncFabDefaultValues(force = false){
  const baseDateStr = dateStrFromCurrentOrToday();
  const todayStr = toDateInputValue(new Date());
  const startMin = roundUpToQuarter(new Date());
  const blockEndMin = Math.min(startMin + 30, 23 * 60 + 45);

  ['qaDate', 'btDate'].forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    el.min = todayStr;
    if (force || !el.value) el.value = baseDateStr;
  });

  const qaTime = document.getElementById('qaTime');
  const btStart = document.getElementById('btStart');
  const btEnd = document.getElementById('btEnd');
  if (qaTime && (force || !qaTime.value)) qaTime.value = minToTimeStr(startMin);
  if (btStart && (force || !btStart.value)) btStart.value = minToTimeStr(startMin);
  if (btEnd && (force || !btEnd.value)) btEnd.value = minToTimeStr(blockEndMin);
}

function bindFabLiveValidation(){
  [
    ['qaStaff','change'], ['qaService','change'], ['qaDate','input'], ['qaTime','input']
  ].forEach(([id, evt]) => {
    document.getElementById(id)?.addEventListener(evt, () => {
      const svc = SERVICE_MAP.get(document.getElementById('qaService')?.value || '');
      const priceInp = document.getElementById('qaPrice');
      if (svc && priceInp && !priceInp.dataset.touched) {
        const svcPrice = svc.price ?? svc.amount ?? svc.total ?? '';
        priceInp.value = svcPrice !== '' && svcPrice != null ? String(svcPrice) : '';
      }
      validateQuickApptForm();
    });
  });

  [
    ['btStaff','change'], ['btDate','input'], ['btStart','input'], ['btEnd','input']
  ].forEach(([id, evt]) => {
    document.getElementById(id)?.addEventListener(evt, () => validateBlockTimeForm());
  });

  document.getElementById('qaPrice')?.addEventListener('input', (e) => {
    e.currentTarget.dataset.touched = '1';
  });

  document.getElementById('qaPhone')?.addEventListener('input', (e) => {
    const digits = String(e.currentTarget.value || '').replace(/\D/g, '').slice(0, 10);
    e.currentTarget.value = digits;
  });
}

function initFAB() {
  const fabWrap = document.getElementById('fabWrap');
  const fabBtn  = document.getElementById('fabBtn');
  const fabMenu = document.getElementById('fabMenu');
  if (!fabWrap || !fabBtn || !fabMenu) return;
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const isMobileFabViewport = () => window.matchMedia('(max-width: 640px)').matches;
  const getFabPosKey = () => isMobileFabViewport()
    ? 'wb.calendar.fabPos.mobile.v2'
    : 'wb.calendar.fabPos.desktop.v2';
  const getFabMaxTop = () => {
    if (isMobileFabViewport()) return 800;
    return 900;
  };
  const getFabSurfaceRect = () => {
    const daySurface = document.querySelector('.calendar');
    const weekSurface = document.querySelector('.week');
    const candidate = (!weekSurface || weekSurface.hidden) ? daySurface : weekSurface;
    return candidate?.getBoundingClientRect?.() || null;
  };

  const applyFabPosition = (left, top) => {
    const wrapRect = fabWrap.getBoundingClientRect();
    const btnRect = fabBtn.getBoundingClientRect();
    const offsetLeft = Math.max(0, wrapRect.width - btnRect.width);
    const offsetTop = Math.max(0, wrapRect.height - btnRect.height);
    let minLeft = 8;
    let maxLeft = Math.max(8, window.innerWidth - btnRect.width - 8);
    let minTop = 8;
    const viewportMaxTop = Math.max(8, window.innerHeight - btnRect.height - 8);
    let maxTop = Math.min(viewportMaxTop, getFabMaxTop());

    if (isMobileFabViewport()) {
      const surfaceRect = getFabSurfaceRect();
      if (surfaceRect) {
        minLeft = Math.max(8, surfaceRect.left);
        maxLeft = Math.max(minLeft, surfaceRect.right - btnRect.width);
        minTop = Math.max(8, surfaceRect.top);
        maxTop = Math.max(minTop, Math.min(surfaceRect.bottom - btnRect.height, getFabMaxTop()));
      }
    }

    const clampedLeft = clamp(left, minLeft, maxLeft);
    const clampedTop = clamp(top, minTop, maxTop);
    fabWrap.style.setProperty('left', `${clampedLeft - offsetLeft}px`, 'important');
    fabWrap.style.setProperty('top', `${clampedTop - offsetTop}px`, 'important');
    fabWrap.style.setProperty('right', 'auto', 'important');
    fabWrap.style.setProperty('bottom', 'auto', 'important');
    fabWrap.style.alignItems = 'flex-end';
  };

  try {
    const saved = JSON.parse(localStorage.getItem(getFabPosKey()) || 'null');
    if (saved && Number.isFinite(saved.left) && Number.isFinite(saved.top)) {
      requestAnimationFrame(() => applyFabPosition(saved.left, saved.top));
    }
  } catch {}

  const toggleFab = (force) => {
    const open = (force !== undefined) ? force : !fabMenu.classList.contains('open');
    fabMenu.classList.toggle('open', open);
    fabMenu.setAttribute('aria-hidden', String(!open));
    fabBtn.classList.toggle('open', open);
    fabBtn.setAttribute('aria-expanded', String(open));
  };

  let dragState = null;
  let suppressFabClick = false;

  fabBtn.style.touchAction = 'none';

  fabBtn.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 && e.pointerType !== 'touch') return;
    const rect = fabBtn.getBoundingClientRect();
    dragState = {
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      startLeft: rect.left,
      startTop: rect.top,
      moved: false,
    };
    fabBtn.setPointerCapture?.(e.pointerId);
  });

  fabBtn.addEventListener('pointermove', (e) => {
    if (!dragState || dragState.pointerId !== e.pointerId) return;
    const dx = e.clientX - dragState.startX;
    const dy = e.clientY - dragState.startY;
    if (!dragState.moved && Math.hypot(dx, dy) < 8) return;
    dragState.moved = true;
    suppressFabClick = true;
    toggleFab(false);
    applyFabPosition(dragState.startLeft + dx, dragState.startTop + dy);
  });

  const finishFabDrag = (e) => {
    if (!dragState || dragState.pointerId !== e.pointerId) return;
    fabBtn.releasePointerCapture?.(e.pointerId);
    if (dragState.moved) {
      const rect = fabBtn.getBoundingClientRect();
      try {
        localStorage.setItem(getFabPosKey(), JSON.stringify({ left: rect.left, top: rect.top }));
      } catch {}
      setTimeout(() => { suppressFabClick = false; }, 0);
    }
    dragState = null;
  };

  fabBtn.addEventListener('pointerup', finishFabDrag);
  fabBtn.addEventListener('pointercancel', finishFabDrag);

  window.addEventListener('resize', () => {
    if (!fabWrap.style.left || !fabWrap.style.top) return;
    const rect = fabBtn.getBoundingClientRect();
    applyFabPosition(rect.left, rect.top);
  });

  fabBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (suppressFabClick) {
      suppressFabClick = false;
      return;
    }
    toggleFab();
  });
  document.addEventListener('mousedown', (e) => {
    if (!fabMenu.classList.contains('open')) return;
    if (!e.target.closest('#fabWrap')) toggleFab(false);
  });

  // ──── Hızlı Randevu ────
  document.getElementById('fabQuickAppt')?.addEventListener('click', () => {
    toggleFab(false);
    openFabModal('quickApptOverlay');
    populateFabSelects(true);
    validateQuickApptForm();
  });
  document.getElementById('qaClose')?.addEventListener('click',  () => closeFabModal('quickApptOverlay'));
  document.getElementById('qaCancel')?.addEventListener('click', () => closeFabModal('quickApptOverlay'));
  document.getElementById('quickApptOverlay')?.addEventListener('mousedown', (e) => {
    if (e.target === e.currentTarget) closeFabModal('quickApptOverlay');
  });

  document.getElementById('qaSave')?.addEventListener('click', async () => {
    const staffSel  = document.getElementById('qaStaff');
    const svcSel    = document.getElementById('qaService');
    const dateInp   = document.getElementById('qaDate');
    const timeInp   = document.getElementById('qaTime');
    const nameInp   = document.getElementById('qaName');
    const phoneInp  = document.getElementById('qaPhone');
    const emailInp  = document.getElementById('qaEmail');
    const priceInp  = document.getElementById('qaPrice');
    const phoneDigits = String(phoneInp?.value || '').replace(/\D/g, '');

    if (!dateInp.value || !timeInp.value || !staffSel.value || !svcSel.value) {
      alert('Lütfen personel, hizmet, tarih ve saati doldurun.');
      return;
    }

    if (phoneDigits && phoneDigits.length !== 10) {
      alert('Telefon numarası girilecekse 10 hane olmalıdır.');
      phoneInp?.focus();
      return;
    }

    if (!validateQuickApptForm()) return;

    const svcObj      = SERVICE_MAP.get(svcSel.value);
    const durationMin = svcObj?.durationMin || svcObj?.duration_min || 30;
    const [hh, mm]    = timeInp.value.split(':').map(Number);
    const startMin    = hh * 60 + mm;
    const startAt     = `${dateInp.value}T${timeInp.value}:00`;

    const btn = document.getElementById('qaSave');
    btn.disabled = true; btn.textContent = 'Kaydediliyor…';
    try {
      const res = await apiPost('/api/appointments/book.php', {
        businessId:  BUSINESS_ID,
        staffId:     staffSel.value,
        serviceId:   svcSel.value,
        dayStr:      dateInp.value,
        startMin,
        durationMin,
        startAt,
        customer: {
          name:  nameInp.value.trim(),
          phone: phoneDigits,
          email: emailInp?.value.trim() || '',
        },
        price:  priceInp.value ? Number(priceInp.value) : undefined,
        source: 'admin',
        status: 'approved',
      });
      if (!res || !res.ok) {
        const msg = res?.error || 'Randevu oluşturulamadı';
        alert(msg);
        return;
      }
      closeFabModal('quickApptOverlay');
      // Formu temizle
      [nameInp, phoneInp, emailInp].forEach(el => { if(el) el.value = ''; });
      priceInp.value = '';
      loadAppointmentsForCurrent();
    } catch (err) {
      alert('Randevu oluşturulamadı: ' + (err.message || 'Hata'));
    } finally {
      btn.disabled = false; btn.textContent = 'Randevu Oluştur';
    }
  });

  // ──── Dolu Göster ────
  document.getElementById('fabBlockTime')?.addEventListener('click', () => {
    toggleFab(false);
    openFabModal('blockTimeOverlay');
    populateFabSelects(true);
    validateBlockTimeForm();
  });
  document.getElementById('btClose')?.addEventListener('click',  () => closeFabModal('blockTimeOverlay'));
  document.getElementById('btCancel')?.addEventListener('click', () => closeFabModal('blockTimeOverlay'));
  document.getElementById('blockTimeOverlay')?.addEventListener('mousedown', (e) => {
    if (e.target === e.currentTarget) closeFabModal('blockTimeOverlay');
  });

  document.getElementById('btSave')?.addEventListener('click', async () => {
    const staffSel = document.getElementById('btStaff');
    const dateInp  = document.getElementById('btDate');
    const startInp = document.getElementById('btStart');
    const endInp   = document.getElementById('btEnd');
    const noteInp  = document.getElementById('btNote');

    if (!staffSel.value || !dateInp.value || !startInp.value || !endInp.value) {
      alert('Lütfen personel, tarih, başlangıç ve bitiş saatini doldurun.');
      return;
    }
    if (startInp.value >= endInp.value) {
      alert('Bitiş saati başlangıç saatinden sonra olmalıdır.');
      return;
    }

    if (!validateBlockTimeForm()) return;

    const btn = document.getElementById('btSave');
    btn.disabled = true; btn.textContent = 'Kaydediliyor…';
    try {
      const res = await apiPost('/api/calendar/block-time.php', {
        staffId:   staffSel.value,
        date:      dateInp.value,
        startTime: startInp.value,
        endTime:   endInp.value,
        note:      noteInp.value.trim() || 'Dolu',
      });
      if (!res?.ok) {
        throw new Error(res?.error || 'Zaman bloke edilemedi');
      }
      closeFabModal('blockTimeOverlay');
      loadAppointmentsForCurrent();
    } catch (err) {
      alert('İşaretlenemedi: ' + (err.message || 'Hata'));
    } finally {
      btn.disabled = false; btn.textContent = 'Dolu Olarak İşaretle';
    }
  });
}

function openFabModal(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.add('open');
  el.setAttribute('aria-hidden','false');
  document.body.classList.add('fab-modal-open');
}
function closeFabModal(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.remove('open');
  el.setAttribute('aria-hidden','true');
  if (!document.querySelector('.fab-overlay.open')) {
    document.body.classList.remove('fab-modal-open');
  }
}

function populateFabSelects(forceDefaults = false) {
  syncFabDefaultValues(forceDefaults);

  // Personel dropdown'larını doldur
  ['qaStaff','btStaff'].forEach(selId => {
    const sel = document.getElementById(selId);
    if (!sel) return;
    const selected = sel.value;
    sel.innerHTML = '';
    STAFF_DOCS.forEach(s => {
      const name = s.data?.name || '';
      const opt = document.createElement('option');
      opt.value = s.id;
      opt.textContent = name;
      sel.appendChild(opt);
    });
    // OWNER için doküman yoksa ekle
    if (!STAFF_DOCS.length) {
      const opt = document.createElement('option');
      opt.value = '';
      opt.textContent = OWNER;
      sel.appendChild(opt);
    }
    if (selected && [...sel.options].some(opt => opt.value === selected)) {
      sel.value = selected;
    }
  });

  // Hizmet dropdown'u
  const qaService = document.getElementById('qaService');
  if (qaService) {
    const selectedService = qaService.value;
    qaService.innerHTML = '';
    SERVICE_MAP.forEach((svc, id) => {
      const opt = document.createElement('option');
      opt.value = id;
      const duration = svc.durationMin || svc.duration_min || 0;
      const price = svc.price != null && svc.price !== '' ? ` • ${Number(svc.price).toLocaleString('tr-TR')} TL` : '';
      opt.textContent = `${svc.name}${duration ? ' (' + duration + ' dk)' : ''}${price}`;
      qaService.appendChild(opt);
    });
    if (!SERVICE_MAP.size) {
      const opt = document.createElement('option');
      opt.value = '';
      opt.textContent = 'Hizmet yok';
      qaService.appendChild(opt);
    }
    if (selectedService && [...qaService.options].some(opt => opt.value === selectedService)) {
      qaService.value = selectedService;
    }
  }

  const qaPrice = document.getElementById('qaPrice');
  if (qaPrice && !qaPrice.dataset.touched) {
    const svc = SERVICE_MAP.get(qaService?.value || '');
    const svcPrice = svc?.price ?? svc?.amount ?? '';
    qaPrice.value = svcPrice !== '' && svcPrice != null ? String(svcPrice) : '';
  }
}

/* =================== BOOT =================== */

function boot(){
  current = new Date();

  // bildirimler.html'den gelen ?date=YYYY-MM-DD&time=HH:MM parametrelerini oku
  try {
    const sp = new URLSearchParams(window.location.search);
    const dateParam = sp.get('date');
    const timeParam = sp.get('time');
    if (dateParam && /^\d{4}-\d{2}-\d{2}$/.test(dateParam)) {
      const parts = dateParam.split('-');
      const d = new Date(+parts[0], +parts[1]-1, +parts[2]);
      if (!isNaN(d)) {
        current = d;
        // Gün görünümüne geç
        view = 'day';
        // Render sonrası o saate scroll et
        if (timeParam && /^\d{2}:\d{2}$/.test(timeParam)) {
          const [hh, mm] = timeParam.split(':').map(Number);
          window._calScrollToTime = hh + mm / 60;
        }
      }
    }
  } catch(e) {}

  setView(view);
  drawMini(new Date(current.getFullYear(), current.getMonth(), 1));

  // Belirtilen saate scroll et
  if (window._calScrollToTime != null) {
    const targetTime = window._calScrollToTime;
    window._calScrollToTime = null;
    setTimeout(() => {
      const VSTART = 8;
      const ch = cellH();
      const scrollPx = Math.max(0, (targetTime - VSTART) * ch - 80);
      // .calendar = #dayView, overflow-y:auto ile scroll eder
      const calEl = document.querySelector('.calendar');
      if (calEl) {
        calEl.scrollTop = scrollPx;
      } else {
        // fallback: .main de overflow:auto
        const mainEl = document.querySelector('.main');
        if (mainEl) mainEl.scrollTop = scrollPx;
      }
    }, 600);
  }
}

/* Hücre yüksekliği değişince yeniden çiz */
window.addEventListener("resize", ()=>{
  (view==="day") ? renderDay() : renderWeek();
}, { passive:true });

/* =================== INIT =================== */

onReady(()=>{
  bindViewSelect();
  bindDateNav();
  bindMiniCalendar();
  bindProfile();
  bindFabLiveValidation();
  initFAB();

  bootstrapCalendar().catch(err=>{
    console.warn('[calendar] bootstrap ilk deneme başarısız, 1.5sn sonra tekrar:', err);
    setTimeout(() => {
      bootstrapCalendar().catch(err2=>{
        console.error('[calendar] bootstrap ikinci deneme de başarısız:', err2);
        alert('Takvim yüklenirken bir hata oluştu. Lütfen sayfayı yenileyin.');
      });
    }, 1500);
  });
});
