import { loadDirectoryBusinesses } from "./public-businesses-store.js";

// searchbar.js — Navbar arama (popover & 2-adımlı zaman modalları)

/* Firebase kaldırıldı — PHP API kullanılıyor */

/* ------------------ DOM refs ------------------ */
const INP_Q    = document.querySelector('.navbar .search-section input[aria-label="Hizmet veya işletme ara"]');
const INP_LOC  = document.querySelector('.navbar .search-section input[aria-label="Konum"]');
const INP_WHEN = document.querySelector('.navbar .search-section input[aria-label="Zaman"]');

/* ------------------ Utils ------------------ */
const mapTR = { "İ":"i", "I":"ı", "Ş":"ş", "Ğ":"ğ", "Ü":"ü", "Ö":"ö", "Ç":"ç" };
const fold  = (s="") => s.replace(/[İIŞĞÜÖÇ]/g, m=>mapTR[m]||m).toLowerCase();
const cmpTR = (a,b)=> a.localeCompare(b,'tr',{sensitivity:'base'});
const slug  = (s="") => fold(s).replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"");
const subseq = (txt, pat) => { txt = fold(txt); pat = fold(pat); let i=0; for (const ch of pat){ i = txt.indexOf(ch, i)+1; if(i===0) return false; } return true; };
const $ = (s, r=document)=> r.querySelector(s);

/* TR ay adları */
const MONTHS_TR = ["Ocak","Şubat","Mart","Nisan","Mayıs","Haziran","Temmuz","Ağustos","Eylül","Ekim","Kasım","Aralık"];

/* Pazarı 7 kabul ederek Pzt=1 … Paz=7 hizalaması (grid başı Pzt) */
const dowMonFirst = (jsDow)=> (jsDow+6)%7; // JS: 0=Sun → 6; 1=Mon → 0 ...

/* ------------------ Global state ------------------ */
const state = {
  services: [],
  salons: [],
  locs: null,
  // zaman akışı
  viewYear: 0,
  viewMonth: 0, // 0-11
  pickedDateStr: null, // YYYY-MM-DD
  pickedTimeStr: null, // HH:MM
  _lastFocus: null,     // modal odak dönüşü için
};

/* ------------------ Tek popover yöneticisi ------------------ */
let openedFor = null; // 'q' | 'loc'
function ensurePopover(hostInput){
  let box = hostInput.parentElement.querySelector('.sb-popover');
  if (!box){
    box = document.createElement('div');
    box.className = 'sb-popover';
    // mümkünse sınıfla yönetmek idealdir; ama burada minimum müdahale:
    if (getComputedStyle(hostInput.parentElement).position === 'static') {
      hostInput.parentElement.style.position = 'relative';
    }
    hostInput.parentElement.appendChild(box);
  }
  return box;
}
function closeAllPopovers(){
  document.querySelectorAll('.sb-popover').forEach(p=> p.classList.remove('open'));
  openedFor = null;
}
document.addEventListener('click', (e)=>{
  const inside = e.target.closest('.sb-popover') || e.target.closest('.search-section');
  if (!inside) closeAllPopovers();
});
window.addEventListener('scroll', closeAllPopovers, { passive:true });

/* ------------------ Services & salons preload ------------------ */
async function preloadQ(){
  try{
    const items = await loadDirectoryBusinesses();
    const setServ = new Set();
    const services = [], salons = [];
    items.forEach(x=>{
      const id = x.id || x.businessId;
      const name = x.name || "İşletme";
      salons.push({ id, name });
      if (Array.isArray(x.services)){
        x.services.forEach(s=>{
          const n = String(s?.name||"").trim(); if(!n) return;
          const key = fold(n);
          if(!setServ.has(key)){ setServ.add(key); services.push(n); }
        });
      }
    });
    state.services = services.sort(cmpTR);
    state.salons   = salons.sort((a,b)=>cmpTR(a.name,b.name));
  }catch{
    // sessiz
  }
}
preloadQ();

/* ------------------ İstanbul lokasyon verisi ------------------ */
async function ensureLocations(){
  if (state.locs) return state.locs;
  try{
    const res = await fetch("./js/locations-tr.json", { cache:"force-cache" });
    state.locs = await res.json();
  }catch{
    state.locs = { province:"İstanbul", districts:[] };
  }
  return state.locs;
}

/* ------------------ Klavye navigasyonu yardımcıları ------------------ */
function makeListItemsFocusable(listRoot){
  const items = listRoot.querySelectorAll('li');
  items.forEach(li => { li.tabIndex = -1; });
}
function focusFirstListItem(pop){
  const li = pop.querySelector('li');
  if (li){ li.focus(); }
}
function listKeyNavHandler(e){
  const li = e.currentTarget;
  if (!li) return;
  const all = Array.from(li.parentElement.querySelectorAll('li'));
  const idx = all.indexOf(li);
  if (e.key === 'ArrowDown'){
    e.preventDefault();
    const next = all[idx+1] || all[0];
    next?.focus();
  } else if (e.key === 'ArrowUp'){
    e.preventDefault();
    const prev = all[idx-1] || all[all.length-1];
    prev?.focus();
  } else if (e.key === 'Enter'){
    e.preventDefault();
    li.click();
  }
}

/* ------------------ Q (Hizmet/İşletme) popover ------------------ */
function renderQPopover(input){
  closeAllPopovers(); // tek popover kuralı
  const q = (input.value||"").trim();
  const box = ensurePopover(input);
  if (!q){
    box.classList.remove('open'); box.innerHTML=""; return;
  }
  const serv = state.services.filter(n=>subseq(n,q)).slice(0,8);
  const biz  = state.salons.filter(o=>subseq(o.name,q)).slice(0,8);

  // iskelet
  box.innerHTML = `
    <div class="sb-group">
      <div class="sb-head">HİZMETLER</div>
      <ul class="sb-list sb-list-svc"></ul>
    </div>
    <div class="sb-group">
      <div class="sb-head">İŞLETMELER</div>
      <ul class="sb-list sb-list-biz"></ul>
    </div>`;

  const ulS = box.querySelector('.sb-list-svc');
  const ulB = box.querySelector('.sb-list-biz');

  // güvenli: öğeleri programatik ekle
  const fragS = document.createDocumentFragment();
  serv.forEach(name=>{
    const li = document.createElement('li');
    li.dataset.kind = 'svc';
    li.dataset.name = name;
    const i = document.createElement('i'); i.className = 'fa-solid fa-scissors';
    const sp = document.createElement('span'); sp.textContent = name;
    li.append(i, sp);
    li.addEventListener('click', ()=>{
      const p = new URLSearchParams({ q:name, service:name, serviceSlug: slug(name) });
      window.location.href = `kuafor.html?${p.toString()}`;
    });
    li.addEventListener('keydown', listKeyNavHandler);
    fragS.appendChild(li);
  });
  ulS.appendChild(fragS);

  const fragB = document.createDocumentFragment();
  biz.forEach(b=>{
    const li = document.createElement('li');
    li.dataset.kind = 'biz';
    li.dataset.id = b.id;
    const i = document.createElement('i'); i.className = 'fa-solid fa-store';
    const sp = document.createElement('span'); sp.textContent = b.name;
    li.append(i, sp);
    li.addEventListener('click', ()=>{
      window.location.href = `profile.html?id=${encodeURIComponent(b.id)}`;
    });
    li.addEventListener('keydown', listKeyNavHandler);
    fragB.appendChild(li);
  });
  ulB.appendChild(fragB);

  makeListItemsFocusable(box);
  box.classList.add('open');
  openedFor = "q";
}

/* ------------------ Neresi? popover ------------------ */
async function renderLocPopover(input){
  closeAllPopovers(); // tek popover kuralı
  const box = ensurePopover(input);
  const q = fold((input.value||"").trim());
  const data = await ensureLocations();

  const rows = [];
  for (const d of data.districts){
    const dn = d.name;
    if (!q || subseq(dn, q)) rows.push({ prov: data.province, dist: dn, hood: null });
    (d.neighborhoods||[]).forEach(nh=>{
      if (!q || subseq(nh, q) || subseq(`${dn} ${nh}`, q)){
        rows.push({ prov: data.province, dist: dn, hood: nh });
      }
    });
    if (rows.length >= 60) break;
  }

  // iskelet
  box.innerHTML = `
    <div class="sb-group">
      <div class="sb-head">KONUM</div>
      <ul class="sb-list sb-list-loc"></ul>
    </div>`;
  const ul = box.querySelector('.sb-list-loc');

  const frag = document.createDocumentFragment();
  rows.forEach(r=>{
    const li = document.createElement('li');
    li.dataset.prov = r.prov || "İstanbul";
    if (r.dist) li.dataset.dist = r.dist;
    if (r.hood) li.dataset.hood = r.hood;

    const i = document.createElement('i'); i.className = 'fa-solid fa-location-dot';
    const sp = document.createElement('span');
    sp.textContent = r.hood ? `${r.prov} • ${r.dist} • ${r.hood}` : `${r.prov} • ${r.dist}`;
    li.append(i, sp);

    li.addEventListener('click', ()=>{
      // mevcut parametreleri koru
      const cur = new URLSearchParams(location.search);
      cur.set("il", li.dataset.prov || "İstanbul");
      if (li.dataset.dist) cur.set("ilce", li.dataset.dist); else cur.delete("ilce");
      if (li.dataset.hood) cur.set("mahalle", li.dataset.hood); else cur.delete("mahalle");

      const curQ = (INP_Q?.value||"").trim();
      if (curQ) cur.set("q", curQ);

      window.location.href = `kuafor.html?${cur.toString()}`;
    });
    li.addEventListener('keydown', listKeyNavHandler);
    frag.appendChild(li);
  });
  ul.appendChild(frag);

  makeListItemsFocusable(box);
  box.classList.add('open');
  openedFor = "loc";
}

/* ======================================================================= */
/* =======================   ZAMAN SEÇİMİ (2 ADIM)   ===================== */
/* ======================================================================= */

/* --- Odak tuzağı yardımcıları --- */
function trapFocus(modal){
  const selectors = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';
  const getFocusables = ()=> Array.from(modal.querySelectorAll(selectors)).filter(el=>!el.hasAttribute('disabled') && el.offsetParent!==null);
  function onKey(e){
    if (e.key !== 'Tab') return;
    const f = getFocusables();
    if (!f.length) return;
    const first = f[0], last = f[f.length-1];
    if (e.shiftKey){
      if (document.activeElement === first){ e.preventDefault(); last.focus(); }
    } else {
      if (document.activeElement === last){ e.preventDefault(); first.focus(); }
    }
  }
  modal._trapHandler = onKey;
  modal.addEventListener('keydown', onKey);
}
function untrapFocus(modal){
  if (modal && modal._trapHandler){
    modal.removeEventListener('keydown', modal._trapHandler);
    delete modal._trapHandler;
  }
}

/* --- 1) Tarih modalı (#sb-date-overlay) --- */
let dateOv = null;
function ensureDateOverlay(){
  dateOv = document.getElementById("sb-date-overlay");
  if (dateOv) return dateOv;

  // Yoksa üret
  dateOv = document.createElement("div");
  dateOv.id = "sb-date-overlay";
  dateOv.setAttribute("aria-hidden","true");
  dateOv.innerHTML = `
    <div class="sb-date-box" role="dialog" aria-modal="true" aria-label="Tarih Seç">
      <button class="sb-date-close" aria-label="Kapat">×</button>
      <div class="sb-date-head" style="display:flex;align-items:center;justify-content:space-between;gap:10px;margin:6px 6px 10px">
        <button class="nav prev" aria-label="Önceki Ay" style="border:1px solid #e5e7eb;border-radius:10px;padding:6px 10px;background:#fff;cursor:pointer">‹</button>
        <div class="month" style="font-weight:800;font-size:18px">—</div>
        <button class="nav next" aria-label="Sonraki Ay" style="border:1px solid #e5e7eb;border-radius:10px;padding:6px 10px;background:#fff;cursor:pointer">›</button>
      </div>
      <div class="wd" style="display:grid;grid-template-columns:repeat(7,1fr);gap:8px;padding:0 6px 4px;font-weight:700;color:#6b7280">
        <div>Pzt</div><div>Salı</div><div>Çar</div><div>Per</div><div>Cuma</div><div>Cmt</div><div>Paz</div>
      </div>
      <div class="grid" style="display:grid;grid-template-columns:repeat(7,1fr);gap:8px;padding:0 6px 6px"></div>
      <div class="actions" style="display:flex;justify-content:space-between;gap:10px;margin:8px 6px 4px">
        <button class="clear" type="button">Temizle</button>
        <button class="ok" type="button">Seç</button>
      </div>
    </div>`;
  // overlay arka plana tıklayınca kapat
  dateOv.addEventListener('click', (e)=>{ if (e.target === dateOv) closeDateModal(); });
  document.body.appendChild(dateOv);
  return dateOv;
}

function openDateModal(){
  closeAllPopovers();
  state._lastFocus = document.activeElement;
  const ov = ensureDateOverlay();
  document.body.style.overflow = "hidden";

  const today = new Date();
  // ilk açılışta seçili tarih varsa onun ayına git
  if (!state.viewYear){
    if (state.pickedDateStr){
      const [y,m] = state.pickedDateStr.split('-').map(Number);
      state.viewYear = y; state.viewMonth = (m-1);
    } else {
      state.viewYear = today.getFullYear();
      state.viewMonth = today.getMonth();
    }
  }
  renderCalendar();
  ov.classList.add("open");
  ov.setAttribute("aria-hidden","false");

  // odak tuzağı + ilk odak
  trapFocus(ov);
  setTimeout(()=>{
    const firstEnabled = ov.querySelector('.grid .day:not([disabled])') || ov.querySelector('.sb-date-close');
    firstEnabled?.focus();
  }, 0);
}

function closeDateModal(){
  if (!dateOv) return;
  untrapFocus(dateOv);
  dateOv.classList.remove("open");
  dateOv.setAttribute("aria-hidden","true");
  document.body.style.overflow = "";
  // odayı açan elemana (INP_WHEN) geri odak
  (INP_WHEN || state._lastFocus)?.focus?.();
}

function renderCalendar(){
  const monthLbl = dateOv.querySelector(".sb-date-head .month");
  const grid     = dateOv.querySelector(".grid");
  const prevBtn  = dateOv.querySelector(".sb-date-head .nav.prev");
  const nextBtn  = dateOv.querySelector(".sb-date-head .nav.next");
  const clearBtn = dateOv.querySelector(".actions .clear");
  const okBtn    = dateOv.querySelector(".actions .ok");

  monthLbl.textContent = `${MONTHS_TR[state.viewMonth]} ${state.viewYear}`;

  const first = new Date(state.viewYear, state.viewMonth, 1);
  const last  = new Date(state.viewYear, state.viewMonth+1, 0);
  const padStart = dowMonFirst(first.getDay());
  const totalDays = last.getDate();

  const now = new Date();
  const todayMid = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const cells = [];
  for (let i=0;i<padStart;i++) cells.push(`<span aria-hidden="true"></span>`);
  for (let d=1; d<=totalDays; d++){
    const yyyy = state.viewYear;
    const mm   = String(state.viewMonth+1).padStart(2,'0');
    const dd   = String(d).padStart(2,'0');
    const iso  = `${yyyy}-${mm}-${dd}`;

    const dayDate = new Date(yyyy, state.viewMonth, d);
    const isPast = dayDate < todayMid;

    const isActive = state.pickedDateStr===iso;
    const styleActive = isActive ? 'background:#111;color:#fff;border-color:#111;font-weight:800' : '';
    const disabledAttr = isPast ? ' disabled aria-disabled="true"' : '';
    const styleDis = isPast ? 'opacity:.5;cursor:not-allowed' : 'cursor:pointer';

    cells.push(
      `<button class="day" data-date="${iso}" ${disabledAttr} ${isActive?'aria-current="date"':''}
         style="padding:10px;border:1px solid #e5e7eb;border-radius:10px;background:#fff;${styleActive||styleDis}">
         ${d}
       </button>`
    );
  }
  grid.innerHTML = cells.join("");

  prevBtn.onclick = ()=>{ const d = new Date(state.viewYear, state.viewMonth-1, 1); state.viewYear=d.getFullYear(); state.viewMonth=d.getMonth(); renderCalendar(); };
  nextBtn.onclick = ()=>{ const d = new Date(state.viewYear, state.viewMonth+1, 1); state.viewYear=d.getFullYear(); state.viewMonth=d.getMonth(); renderCalendar(); };

  grid.querySelectorAll(".day").forEach(btn=>{
    if (!btn.disabled){
      btn.addEventListener("click", ()=>{
        state.pickedDateStr = btn.dataset.date;
        renderCalendar();
      });
    }
  });

  clearBtn.onclick = ()=>{ state.pickedDateStr = null; closeDateModal(); };

  // BUG FIX: profile.js'in bindDateOverlayFailsafe() fonksiyonu #sb-date-overlay'e
  // zaten .sb-time-row ekler ve kendi okBtn addEventListener'ını kurar.
  // Eğer overlay'in içinde .sb-time-row varsa, profile.js yönlendirmeyi handle ediyor
  // demektir — onun üzerine yazmayalım (çift modal açılıyor, yönlendirme çalışmıyor).
  const alreadyOwnedByProfile = !!dateOv.querySelector('.sb-time-row');
  if (!alreadyOwnedByProfile) {
    okBtn.onclick = ()=>{ if (!state.pickedDateStr) return; closeDateModal(); openTimeModal(); };
  }
  // alreadyOwnedByProfile = true ise profile.js'in addEventListener'ı devrede kalır
  // ve Seç butonuna tıklandığında kuafor.html'e yönlendirir.
}

// Kapatma tuşu
document.addEventListener("click", (e)=>{
  if (e.target?.closest?.("#sb-date-overlay .sb-date-close")) closeDateModal();
});
// ESC
document.addEventListener("keydown", (e)=>{ if (e.key==="Escape"){ closeDateModal(); closeTimeModal(); }});

/* --- 2) Saat modalı (#sb-time-overlay) --- */
let timeOv = null;
const TIME_SLOTS = ["09:00","10:00","11:00","12:00","13:00","14:00","16:00","17:00","18:00","19:00","20:00","21:00"];

function ensureTimeOverlay(){
  if (timeOv) return timeOv;
  timeOv = document.createElement("div");
  timeOv.id = "sb-time-overlay";
  timeOv.setAttribute("aria-hidden","true");
  timeOv.innerHTML = `
    <div class="sb-date-box" role="dialog" aria-modal="true" aria-label="Saat Seç">
      <button class="sb-date-close" aria-label="Kapat"><i class="fas fa-times"></i></button>
      <div style="text-align:center; font-weight:800; font-size:18px; margin:4px 0 12px">Saat Seç</div>
      <div class="time-grid" style="display:flex;flex-wrap:wrap;gap:10px;justify-content:center;padding:0 12px 6px"></div>
      <div class="actions" style="display:flex;justify-content:space-between;gap:10px;margin-top:8px">
        <button class="clear" type="button">Temizle</button>
        <button class="ok" type="button" disabled>Seç</button>
      </div>
    </div>`;
  // overlay arka plana tıklayınca kapat
  timeOv.addEventListener('click', (e)=>{ if (e.target === timeOv) closeTimeModal(); });
  document.body.appendChild(timeOv);
  return timeOv;
}

function openTimeModal(){
  state._lastFocus = document.activeElement;
  const ov = ensureTimeOverlay();
  const grid = ov.querySelector(".time-grid");
  const okBtn = ov.querySelector(".ok");
  const clrBtn = ov.querySelector(".clear");

  grid.innerHTML = TIME_SLOTS.map(t=>{
    const active = (t===state.pickedTimeStr);
    return `<button class="chip" data-time="${t}" style="padding:10px 14px;border:1px solid #e5e7eb;border-radius:999px;background:#fff;font-weight:700;cursor:pointer${active?';background:#0ea5a5;color:#fff;border-color:#0ea5a5':''}">${t}</button>`;
  }).join("");

  grid.querySelectorAll(".chip").forEach(b=>{
    b.onclick = ()=>{
      state.pickedTimeStr = b.dataset.time;
      grid.querySelectorAll(".chip").forEach(x=>{ x.style.background="#fff"; x.style.color="inherit"; x.style.borderColor="#e5e7eb"; });
      b.style.background="#0ea5a5"; b.style.color="#fff"; b.style.borderColor="#0ea5a5";
      okBtn.disabled = false;
    };
    b.addEventListener('keydown', (e)=>{
      if (e.key === 'Enter'){ e.preventDefault(); b.click(); }
    });
  });

  clrBtn.onclick = ()=>{ state.pickedTimeStr=null; okBtn.disabled=true; closeTimeModal(); };
  okBtn.onclick  = ()=>{ if(state.pickedDateStr && state.pickedTimeStr){ 
    // kullanıcıya görsel geri bildirim
    try{
      const [y,m,d] = state.pickedDateStr.split('-').map(Number);
      INP_WHEN && (INP_WHEN.value = `${d} ${MONTHS_TR[m-1]} ${state.pickedTimeStr}`);
    }catch{}
    goToKuaforWithParams(); 
  } };

  document.body.style.overflow = "hidden";
  ov.classList.add("open");
  ov.setAttribute("aria-hidden","false");

  // odak tuzağı + ilk odak
  trapFocus(ov);
  setTimeout(()=>{
    const firstChip = ov.querySelector('.chip') || ov.querySelector('.sb-date-close');
    firstChip?.focus();
  }, 0);
}

function closeTimeModal(){
  if (!timeOv) return;
  untrapFocus(timeOv);
  timeOv.classList.remove("open");
  timeOv.setAttribute("aria-hidden","true");
  document.body.style.overflow = "";
  (INP_WHEN || state._lastFocus)?.focus?.();
}

document.addEventListener("click", (e)=>{
  if (e.target?.closest?.("#sb-time-overlay .sb-date-close")) closeTimeModal();
});

/* --- Yönlendirme --- */
function goToKuaforWithParams(){
  const keepKeys = ["il","ilce","mahalle","q","service","serviceSlug"];
  const cur = new URLSearchParams(location.search);
  const p = new URLSearchParams();
  keepKeys.forEach(k=>{ if(cur.has(k)) p.set(k, cur.get(k)); });

  // BUG FIX: index.html ile aynı URL formatı: ?start=ISO&end=ISO
  // Eski format: ?date=YYYY-MM-DD&time=HH:MM → kuafor.html bu formatı tanımıyor
  const timeStr = state.pickedTimeStr || "09:00";
  const [hh, mm] = timeStr.split(":").map(Number);
  const startDate = new Date(`${state.pickedDateStr}T00:00:00`);
  startDate.setHours(hh, mm, 0, 0);
  const startISO = startDate.toISOString();
  const endISO   = new Date(startDate.getTime() + 60 * 60 * 1000).toISOString();
  p.set("start", startISO);
  p.set("end",   endISO);

  closeTimeModal();
  window.location.href = `kuafor.html?${p.toString()}`;
}

/* ------------------ Nav input bindings ------------------ */
if (INP_Q){
  INP_Q.setAttribute("autocomplete","off");
  INP_Q.addEventListener("input", ()=> { renderQPopover(INP_Q); });
  INP_Q.addEventListener("focus", ()=> { renderQPopover(INP_Q); });

  // Klavye: ok tuşları + Enter popover listesini yönetebilsin
  INP_Q.addEventListener("keydown", (e)=>{
    const openPop = INP_Q.parentElement.querySelector('.sb-popover.open');
    if (openPop && openedFor === 'q'){
      if (e.key === 'ArrowDown'){
        e.preventDefault(); focusFirstListItem(openPop);
        return;
      }
      if (e.key === 'Enter'){
        // Eğer bir öğe odakta ise onu seç; yoksa normal arama
        if (openPop.contains(document.activeElement) && document.activeElement.tagName === 'LI'){
          e.preventDefault();
          document.activeElement.click();
          return;
        }
      }
    }
    if (e.key==="Enter"){
      e.preventDefault();
      const q = (INP_Q.value||"").trim();
      if (!q) return;
      const p = new URLSearchParams(location.search);
      p.set("q", q);
      window.location.href = `kuafor.html?${p.toString()}`;
    }
  });
}

if (INP_LOC){
  INP_LOC.setAttribute("autocomplete","off");
  INP_LOC.addEventListener("input", ()=> { renderLocPopover(INP_LOC); });
  INP_LOC.addEventListener("focus", ()=> { renderLocPopover(INP_LOC); });
  INP_LOC.addEventListener("keydown", (e)=>{
    const openPop = INP_LOC.parentElement.querySelector('.sb-popover.open');
    if (openPop && openedFor === 'loc'){
      if (e.key === 'ArrowDown'){ e.preventDefault(); focusFirstListItem(openPop); }
      if (e.key === 'Enter'){
        if (openPop.contains(document.activeElement) && document.activeElement.tagName === 'LI'){
          e.preventDefault(); document.activeElement.click();
        }
      }
    }
  });
}

// BUG FIX: profile.html'de WB_DISABLE_NAV_SUGGEST=true set edilmiş.
// Bu sayfada INP_WHEN'i profile.js'in bindDateOverlayFailsafe() fonksiyonu yönetir.
// searchbar.js'in listener eklemesi çift açılma + close çalışmama sorununa yol açıyor.
if (INP_WHEN && !window.WB_DISABLE_NAV_SUGGEST){
  INP_WHEN.addEventListener("focus", openDateModal);
  INP_WHEN.addEventListener("click", openDateModal);
}

/* Logo → ana sayfa */
document.getElementById("logoBtn")?.addEventListener("click", (e)=>{
  e.preventDefault(); window.location.href = "index.html";
});
