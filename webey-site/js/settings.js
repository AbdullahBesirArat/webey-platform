/**
 * settings.js — v24.0
 * Session tabanlı PHP backend. Firebase yok.
 * /api/settings/load.php · save.php · upload-image.php · delete-image.php
 */

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

/* ══════════════════════════════════════════════
   TOAST
══════════════════════════════════════════════ */
const toastEl = $('#toast');
function showToast(msg = 'İşlem tamam', type = 'default') {
  if (!toastEl) return console.log('[toast]', msg);
  toastEl.textContent = msg;
  toastEl.className   = 'toast show';
  if (type === 'success') toastEl.classList.add('success');
  if (type === 'error')   toastEl.classList.add('error');
  clearTimeout(toastEl._t);
  toastEl._t = setTimeout(() => toastEl.classList.remove('show', 'success', 'error'), 3000);
}

/* ══════════════════════════════════════════════
   API YARDIMCILARI
══════════════════════════════════════════════ */

// ── API yardımcıları: wb-api-shim.js üzerinden ───────────────────────
// Bu dosya settings.html'de wb-api-shim.js'den SONRA yüklenir.
// window.apiGet / window.apiPost shim tarafından sağlanır.
// Burada sadece upload için ek wrapper var (multipart/form-data).

async function apiGet(path, params)  { return window.WbApi.get(path, params); }
async function apiPost(path, body)   { return window.WbApi.post(path, body); }

async function apiUpload(path, formData) {
  // Multipart upload: CSRF token'ı header olarak ekle
  const csrf = window.__csrfToken || null;
  const headers = csrf ? { 'X-CSRF-Token': csrf } : {};
  const res = await fetch(path, {
    method: 'POST',
    credentials: 'include',
    headers,
    body: formData,
  });
  if (res.status === 401 || res.status === 403) {
    location.replace('admin-register-login.html#login');
    throw new Error('UNAUTHORIZED');
  }
  return res.json();
}

function isHeicLikeFile(file) {
  const type = String(file?.type || '').toLowerCase();
  const name = String(file?.name || '').toLowerCase();
  return type.includes('heic') || type.includes('heif') || /\.(heic|heif)$/i.test(name);
}

function fileToObjectUrlImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Telefon fotografi formati tarayici tarafinda acilamadi'));
    };
    img.src = url;
  });
}

async function loadDrawableFromFile(file) {
  let width = 0;
  let height = 0;
  let drawSource = null;

  if ('createImageBitmap' in window) {
    try {
      const bitmap = await createImageBitmap(file);
      width = bitmap.width;
      height = bitmap.height;
      drawSource = bitmap;
    } catch (_) {
      drawSource = null;
    }
  }

  if (!drawSource) {
    const img = await fileToObjectUrlImage(file);
    width = img.naturalWidth || img.width;
    height = img.naturalHeight || img.height;
    drawSource = img;
  }

  return { width, height, drawSource };
}

function computeScaledSize(width, height, maxEdge) {
  if (!width || !height) return { width: 1, height: 1 };
  const longestEdge = Math.max(width, height);
  if (longestEdge <= maxEdge) return { width, height };
  const ratio = maxEdge / longestEdge;
  return {
    width: Math.max(1, Math.round(width * ratio)),
    height: Math.max(1, Math.round(height * ratio)),
  };
}

async function renderFileToJpeg(file, options = {}) {
  const { maxEdge = 2400, quality = 0.86 } = options;
  const { width, height, drawSource } = await loadDrawableFromFile(file);
  const scaled = computeScaledSize(width, height, maxEdge);

  const canvas = document.createElement('canvas');
  canvas.width = scaled.width;
  canvas.height = scaled.height;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Gorsel donusumu baslatilamadi');
  ctx.drawImage(drawSource, 0, 0, canvas.width, canvas.height);

  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob(result => {
      if (result) resolve(result);
      else reject(new Error('Telefon fotografi JPEG formatina cevrilemedi'));
    }, 'image/jpeg', quality);
  });

  if (drawSource && typeof drawSource.close === 'function') {
    drawSource.close();
  }

  return blob;
}

async function convertHeicToJpeg(file) {
  const blob = await renderFileToJpeg(file, { maxEdge: 2600, quality: 0.9 });
  const baseName = String(file?.name || 'image').replace(/\.(heic|heif)$/i, '') || 'image';
  return new File([blob], `${baseName}.jpg`, {
    type: 'image/jpeg',
    lastModified: file?.lastModified || Date.now(),
  });
}

async function compressImageFile(file, kind) {
  const isLikelyPhoto = /^image\/(jpe?g|webp|heic|heif)$/i.test(String(file?.type || '')) || /\.(jpe?g|webp|heic|heif)$/i.test(String(file?.name || ''));
  if (!isLikelyPhoto) return file;

  const maxEdge = kind === 'cover' ? 2200 : 2000;
  const quality = kind === 'cover' ? 0.88 : 0.86;
  const blob = await renderFileToJpeg(file, { maxEdge, quality });

  if (!blob || blob.size >= file.size * 0.92) {
    return file;
  }

  const baseName = String(file?.name || 'image').replace(/\.[^.]+$/, '') || 'image';
  return new File([blob], `${baseName}.jpg`, {
    type: 'image/jpeg',
    lastModified: file?.lastModified || Date.now(),
  });
}

async function prepareUploadFile(file, kind) {
  const normalized = isHeicLikeFile(file) ? await convertHeicToJpeg(file) : file;
  return compressImageFile(normalized, kind);
}

/* ══════════════════════════════════════════════
   DIRTY STATE — kaydet butonunu yönetir
══════════════════════════════════════════════ */
let DIRTY = false;
let INIT_PHASE = true;
let SAVE_IN_FLIGHT = false;
let AUTO_SAVE_TIMER = null;
let AUTO_SAVE_REASON = 'change';

function setDirty(v = true) {
  DIRTY = v;
}

function autoSaveMessage(reason = 'change') {
  return reason === 'add' ? 'Yeni öğe eklendi ✓' : 'Değişiklikler güncellendi ✓';
}

function scheduleAutoSave(reason = 'change', delay = 900) {
  if (INIT_PHASE) return;
  AUTO_SAVE_REASON = reason;
  setDirty(true);
  clearTimeout(AUTO_SAVE_TIMER);
  AUTO_SAVE_TIMER = setTimeout(() => {
    saveAll({ silent: false, reason: AUTO_SAVE_REASON }).catch(() => {});
  }, delay);
}

function attachDirtyWatchers() {
  ['#bizName', '#mapUrl', '#buildingNo', '#aboutText', '#contactPhone'].forEach(sel => {
    $(sel)?.addEventListener('input', () => { if (!INIT_PHASE) scheduleAutoSave('change'); });
  });
  ['#city', '#district', '#hood'].forEach(sel => {
    $(sel)?.addEventListener('change', () => { if (!INIT_PHASE) scheduleAutoSave('change', 250); });
  });
}

/* ══════════════════════════════════════════════
   TELEFON MASKE
══════════════════════════════════════════════ */
function bindPhoneMask() {
  const inp = $('#contactPhone');
  if (!inp) return;
  inp.addEventListener('input', () => {
    inp.value = inp.value.replace(/\D/g, '').slice(0, 10);
  });
  inp.addEventListener('blur', () => {
    const val = inp.value.replace(/\D/g, '');
    if (val && val.length !== 10) showToast('Telefon 10 haneli olmalı (5XXXXXXXXX)', 'error');
  });
}

/* ══════════════════════════════════════════════
   ÇALIŞMA SAATLERİ
══════════════════════════════════════════════ */
const DAYS = [
  { k: 'mon', label: 'Pazartesi' }, { k: 'tue', label: 'Salı' },
  { k: 'wed', label: 'Çarşamba'  }, { k: 'thu', label: 'Perşembe' },
  { k: 'fri', label: 'Cuma'      }, { k: 'sat', label: 'Cumartesi' },
  { k: 'sun', label: 'Pazar'     },
];

let bizHours = {};

function defaultHours() {
  return {
    mon: { closed: false, open: '10:00', close: '19:00' },
    tue: { closed: false, open: '10:00', close: '19:00' },
    wed: { closed: false, open: '10:00', close: '19:00' },
    thu: { closed: false, open: '10:00', close: '19:00' },
    fri: { closed: false, open: '10:00', close: '19:00' },
    sat: { closed: true,  open: '10:00', close: '19:00' },
    sun: { closed: true,  open: '10:00', close: '18:00' },
  };
}

function t2m(t) { const [h=0,m=0] = (t||'').split(':').map(n=>+n||0); return h*60+m; }
function m2t(x) { const h=Math.floor(x/60),m=x%60; return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`; }
function validateDay(d) { if (d.closed) return true; return d.open && d.close && t2m(d.open) < t2m(d.close); }

function buildTimeOptions(step=15, from=6*60, to=23*60+45) {
  const opts = [];
  for (let m = from; m <= to; m += step) opts.push(m2t(m));
  return opts;
}
const TIME_OPTS = buildTimeOptions(15);

function selectHTML(k, which, val, disabled) {
  const label = which === 'open' ? 'Açılış' : 'Kapanış';
  const attr   = which === 'open' ? `data-open="${k}"` : `data-close="${k}"`;
  const dis    = disabled ? 'disabled' : '';
  const opts   = TIME_OPTS.map(t => `<option value="${t}" ${t===val?'selected':''}>${t}</option>`).join('');
  return `<label class="field"><span>${label}</span><select class="input" ${attr} ${dis}>${opts}</select></label>`;
}

function bhRowTemplate(k, d) {
  const sum     = d.closed ? 'Kapalı' : `${d.open} – ${d.close}`;
  const checked = d.closed ? '' : 'checked';
  return `
  <div class="bh-item ${d.closed ? 'is-closed' : ''}" data-day="${k}">
    <div class="toggle">
      <input type="checkbox" ${checked} data-toggle="${k}" title="Aç / Kapa">
    </div>
    <div class="name">${DAYS.find(x=>x.k===k)?.label || k}</div>
    <div data-summary>${sum}</div>
    <button class="chev" data-exp="${k}" aria-expanded="false" title="Genişlet" type="button">
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="m9 18 6-6-6-6"/></svg>
    </button>
    <div class="bh-detail" hidden>
      <div class="bh-form">
        ${selectHTML(k, 'open',  d.open  || '10:00', d.closed)}
        ${selectHTML(k, 'close', d.close || '19:00', d.closed)}
      </div>
    </div>
  </div>`;
}

function renderHoursInline() {
  const el = $('#bhList');
  if (!el) return;
  el.innerHTML = DAYS.map(({ k }) => bhRowTemplate(k, bizHours[k] || { closed: true, open: '10:00', close: '19:00' })).join('');
}

$('#bhList')?.addEventListener('click', e => {
  // Checkbox toggle
  const tgl = e.target.closest('[data-toggle]');
  if (tgl) {
    const k   = tgl.dataset.toggle;
    const chk = e.target.closest('input');
    if (!chk) return;
    bizHours[k].closed = !chk.checked;
    const row = e.target.closest('.bh-item');
    row?.classList.toggle('is-closed', bizHours[k].closed);
    row?.querySelector('[data-summary]')
       ?.replaceChildren(document.createTextNode(bizHours[k].closed ? 'Kapalı' : `${bizHours[k].open} – ${bizHours[k].close}`));
    const detail = row?.querySelector('.bh-detail');
    if (detail) {
      detail.hidden = bizHours[k].closed;
      row.querySelector('[data-exp]')?.setAttribute('aria-expanded', String(!detail.hidden));
    }
    row?.querySelectorAll('select').forEach(s => s.disabled = bizHours[k].closed);
    if (!INIT_PHASE) scheduleAutoSave('change', 250);
    return;
  }

  // Expand/collapse
  const exp = e.target.closest('[data-exp]');
  if (exp) {
    const k      = exp.dataset.exp;
    const detail = $(`#bhList .bh-item[data-day="${k}"] .bh-detail`);
    if (!detail) return;
    detail.hidden = !detail.hidden;
    exp.setAttribute('aria-expanded', String(!detail.hidden));
  }
});

$('#bhList')?.addEventListener('change', e => {
  const t = e.target;
  if (t.matches('select[data-open], select[data-close]')) {
    const k = t.dataset.open || t.dataset.close;
    const d = bizHours[k];
    if (!d) return;
    if (t.dataset.open)  d.open  = t.value;
    if (t.dataset.close) d.close = t.value;
    if (!validateDay(d)) showToast('Kapanış açılıştan büyük olmalı', 'error');
    $(`#bhList .bh-item[data-day="${k}"] [data-summary]`)
      ?.replaceChildren(document.createTextNode(d.closed ? 'Kapalı' : `${d.open} – ${d.close}`));
    if (!INIT_PHASE) scheduleAutoSave('change', 250);
  }
});

/* ══════════════════════════════════════════════
   HİZMETLER
══════════════════════════════════════════════ */
let services = [];
const serviceListEl = $('#serviceList');

function svcRowTemplate(s, idx) {
  const name  = s.name ?? '';
  const min   = Number.isFinite(Number(s.min))   ? Number(s.min)   : '';
  const price = s.price === '' ? '' : (Number.isFinite(Number(s.price)) ? Number(s.price) : '');
  return `
  <div class="tr" data-row="${idx}">
    <div class="td"><div class="grip" title="Sürükle"></div></div>
    <div class="td">
      <input class="input" value="${name}" data-k="name" data-i="${idx}" placeholder="Hizmet adı" />
    </div>
    <div class="td">
      <input class="input" type="number" min="1" step="1" value="${min}" data-k="min" data-i="${idx}" placeholder="dk" />
    </div>
    <div class="td">
      <input class="input" type="number" min="0" step="1" value="${price}" data-k="price" data-i="${idx}" placeholder="₺" />
    </div>
    <div class="td">
      <div class="ops">
        <button class="ico-btn" data-up="${idx}" title="Yukarı" type="button">
          <svg class="ico" viewBox="0 0 24 24"><path d="m5 12 7-7 7 7"/><path d="M12 19V5"/></svg>
        </button>
        <button class="ico-btn" data-down="${idx}" title="Aşağı" type="button">
          <svg class="ico" viewBox="0 0 24 24"><path d="m19 12-7 7-7-7"/><path d="M12 5v14"/></svg>
        </button>
        <button class="ico-btn" data-del="${idx}" title="Sil" type="button" style="color:var(--danger);">
          <svg class="ico" viewBox="0 0 24 24"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
        </button>
      </div>
    </div>
  </div>`;
}

function renderServices() {
  if (!serviceListEl) return;
  serviceListEl.innerHTML = services.length
    ? services.map(svcRowTemplate).join('')
    : `<div style="padding:24px;text-align:center;color:var(--muted);font-size:13px;">
         Henüz hizmet eklenmemiş. Aşağıdan ekleyin veya "Hızlı Ekle" butonunu kullanın.
       </div>`;
}

serviceListEl?.addEventListener('input', e => {
  const t = e.target, k = t.dataset.k, i = +t.dataset.i;
  if (!k || isNaN(i) || !services[i]) return;
  if (k === 'min') {
    const v = Math.floor(Number(t.value));
    services[i][k] = t.value.trim() === '' ? '' : v;
  } else if (k === 'price') {
    const v = Number(t.value);
    services[i][k] = t.value.trim() === '' ? '' : (Number.isFinite(v) ? v : 0);
  } else {
    services[i][k] = t.value;
  }
  if (!INIT_PHASE) scheduleAutoSave('change');
});

serviceListEl?.addEventListener('click', e => {
  const up   = e.target.closest('[data-up]');
  const down = e.target.closest('[data-down]');
  const del  = e.target.closest('[data-del]');
  if (up)   { const i = +up.dataset.up;   if (i > 0) { [services[i-1],services[i]] = [services[i],services[i-1]]; renderServices(); scheduleAutoSave('change', 250); } }
  if (down) { const i = +down.dataset.down; if (i < services.length-1) { [services[i+1],services[i]] = [services[i],services[i+1]]; renderServices(); scheduleAutoSave('change', 250); } }
  if (del)  { const i = +del.dataset.del;  services.splice(i,1); renderServices(); scheduleAutoSave('change', 250); }
});

$('#addQuick')?.addEventListener('click', () => {
  services.push({ name: '', min: 30, price: '' });
  renderServices();
  showToast('Yeni hizmet satırı eklendi', 'success');
});

/* ══════════════════════════════════════════════
   HİZMET ÖNERI PİCKER
══════════════════════════════════════════════ */
const SERVICE_PRESETS = [
  { name: 'Erkek Saç Kesimi',    min: 30, price: 300,  color: 'blue'   },
  { name: 'Sakal Kesimi',        min: 20, price: 150,  color: 'green'  },
  { name: 'Saç + Sakal',         min: 45, price: 400,  color: 'violet' },
  { name: 'Makas Kesim',         min: 40, price: 350,  color: 'orange' },
  { name: 'Çocuk Kesimi',        min: 25, price: 200,  color: 'rose'   },
  { name: 'Saç Boyama',          min: 60, price: 600,  color: 'violet' },
  { name: 'Fön & Şekillendirme', min: 30, price: 250,  color: 'blue'   },
  { name: 'Bıyık Düzeltme',      min: 15, price: 100,  color: 'green'  },
  { name: 'Cilt Bakımı',         min: 45, price: 450,  color: 'rose'   },
  { name: 'Tıraş',               min: 20, price: 150,  color: 'orange' },
  { name: 'Keratin Bakımı',      min: 90, price: 800,  color: 'violet' },
  { name: 'Saç Yıkama',          min: 15, price: 80,   color: 'blue'   },
];

function renderServiceSuggestions() {
  const el = $('#svcSuggest');
  if (!el) return;
  el.innerHTML = '';
  SERVICE_PRESETS.forEach(preset => {
    const already = services.some(s => (s.name||'').toLowerCase() === preset.name.toLowerCase());
    if (already) return;
    const chip = document.createElement('button');
    chip.type      = 'button';
    chip.className = `svc-chip svc-chip--${preset.color}`;
    chip.innerHTML = `<span>${preset.name}</span><span class="hint">${preset.min}dk · ${preset.price > 0 ? preset.price + '₺' : 'Ücretsiz'}</span>`;
    chip.addEventListener('click', () => {
      services.push({ name: preset.name, min: preset.min, price: preset.price });
      renderServices();
      renderServiceSuggestions();
      scheduleAutoSave('add', 250);
    });
    el.appendChild(chip);
  });
}

$('#openPicker')?.addEventListener('click', () => {
  const el  = $('#svcSuggest');
  const btn = $('#openPicker');
  if (!el) return;
  const hidden = el.style.display === 'none' || el.style.display === '';
  if (hidden) {
    renderServiceSuggestions();
    el.style.display = 'flex';
    if (btn) btn.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg> Kapat`;
  } else {
    el.style.display = 'none';
    el.innerHTML = '';
    if (btn) btn.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> Hızlı Ekle`;
  }
});

/* ══════════════════════════════════════════════
   GÖRSEL YÜKLEYİCİ
══════════════════════════════════════════════ */
function normalizeImgUrl(url) {
  if (!url) return url;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return url; // relative URL doğrudan kullanılır
}

function createThumb(url, kind) {
  const src = normalizeImgUrl(url);
  const div = document.createElement('div');
  div.className    = 'thumb';
  div.dataset.url  = url;
  div.dataset.kind = kind;
  div.innerHTML = `
    <img src="${src}" alt="" loading="lazy"
      onerror="this.style.background='var(--surface-2)';this.removeAttribute('src')">
    <button class="thumb__del" data-kind="${kind}" data-url="${url}" title="Görseli sil" type="button">✕</button>`;
  div.querySelector('.thumb__del').addEventListener('click', async (e) => {
    e.stopPropagation();
    if (!confirm('Bu görseli silmek istiyor musunuz?')) return;
    try {
      const res = await apiPost('/api/settings/delete-image.php', { url, kind });
      if (!res.ok) throw new Error(res.error || 'Silinemedi');
      div.remove();
      showToast('Görsel silindi', 'success');
    } catch (err) { showToast(err.message, 'error'); }
  });
  return div;
}

function renderThumbs(containerId, urls = [], kind) {
  const el = $(containerId);
  if (!el) return;
  el.innerHTML = '';
  (Array.isArray(urls) ? urls : [urls]).filter(Boolean).forEach(url => el.appendChild(createThumb(url, kind)));
}

function getCurrentImageCounts() {
  const coverCount = $('#coverThumbs')?.querySelectorAll('.thumb').length || 0;
  const salonCount = $('#salonThumbs')?.querySelectorAll('.thumb').length || 0;
  const modelCount = $('#modelThumbs')?.querySelectorAll('.thumb').length || 0;
  return {
    coverCount,
    salonCount,
    modelCount,
    nonCoverCount: salonCount + modelCount,
    totalCount: coverCount + salonCount + modelCount,
  };
}

function bindUploader(kind) {
  const btn   = $(`[data-upload="${kind}"]`);
  const input = $(`[data-input="${kind}"]`);
  if (!btn || !input) return;

  btn.addEventListener('click', () => input.click());

  input.addEventListener('change', async () => {
    const files = [...(input.files || [])];
    if (!files.length) return;
    input.value = '';
    for (const file of files) {
      const counts = getCurrentImageCounts();
      if (kind !== 'cover' && counts.nonCoverCount >= 9) {
        showToast('En fazla 10 gorsel yukleyebilirsiniz: 1 kapak + 9 diger gorsel.', 'error');
        break;
      }

      // Loading placeholder
      const placeholder = document.createElement('div');
      placeholder.className = 'thumb loading';
      $(`#${kind}Thumbs`)?.appendChild(placeholder);

      try {
        const uploadFile = await prepareUploadFile(file, kind);
        const fd = new FormData();
        fd.append('file', uploadFile);
        fd.append('kind', kind);
        const res = await apiUpload('/api/settings/upload-image.php', fd);
        placeholder.remove();
        if (!res.ok) { showToast(res.error || 'Yükleme başarısız', 'error'); continue; }
        const urls = res.data.images[kind] || [];
        renderThumbs(`#${kind}Thumbs`, urls, kind);
        showToast('Yeni görsel eklendi ✓', 'success');
      } catch (err) {
        placeholder.remove();
        showToast(err.message, 'error');
      }
    }
  });

  // Silme modu toggle
  const delBtn = $(`[data-toggle-delete="${kind}"]`);
  delBtn?.addEventListener('click', () => {
    const uploader = delBtn.closest('.uploader');
    const active   = uploader?.classList.toggle('uploader--delete-mode');
    delBtn.textContent = active ? 'Silmeyi Bitir' : 'Sil';
    if (active) delBtn.classList.add('btn-danger-soft', 'is-active');
    else        delBtn.classList.remove('is-active');
  });
}

/* ══════════════════════════════════════════════
   KONUM KOMBİSU (İl / İlçe / Mahalle)
══════════════════════════════════════════════ */
async function initLocationCombo() {
  const cityEl = $('#city'), distEl = $('#district'), hoodEl = $('#hood');
  if (!cityEl || !distEl || !hoodEl) return;

  try {
    const { attachTRLocationCombo } = await import('./components/select-combo.js');
    await attachTRLocationCombo({ citySelect: cityEl, districtSelect: distEl, neighborhoodSelect: hoodEl });
  } catch (err) {
    console.warn('[settings] select-combo yüklenemedi, fallback kullanılıyor:', err);
    const CITIES = ['Adana','Adıyaman','Afyonkarahisar','Ağrı','Aksaray','Amasya','Ankara','Antalya','Ardahan','Artvin','Aydın','Balıkesir','Bartın','Batman','Bayburt','Bilecik','Bingöl','Bitlis','Bolu','Burdur','Bursa','Çanakkale','Çankırı','Çorum','Denizli','Diyarbakır','Düzce','Edirne','Elazığ','Erzincan','Erzurum','Eskişehir','Gaziantep','Giresun','Gümüşhane','Hakkari','Hatay','Iğdır','Isparta','İstanbul','İzmir','Kahramanmaraş','Karabük','Karaman','Kars','Kastamonu','Kayseri','Kilis','Kırıkkale','Kırklareli','Kırşehir','Kocaeli','Konya','Kütahya','Malatya','Manisa','Mardin','Mersin','Muğla','Muş','Nevşehir','Niğde','Ordu','Osmaniye','Rize','Sakarya','Samsun','Şanlıurfa','Siirt','Sinop','Şırnak','Sivas','Tekirdağ','Tokat','Trabzon','Tunceli','Uşak','Van','Yalova','Yozgat','Zonguldak'];
    cityEl.innerHTML = '<option value="" disabled>Şehir seçin</option>' + CITIES.map(c => `<option value="${c}">${c}</option>`).join('');
    cityEl.disabled = false;
    cityEl.addEventListener('change', () => {
      distEl.innerHTML = '<option value="">İlçe girin</option>';
      distEl.disabled  = false;
      hoodEl.innerHTML = '<option value="">Mahalle girin</option>';
      hoodEl.disabled  = false;
    });
    distEl.addEventListener('change', () => {
      hoodEl.innerHTML = '<option value="">Mahalle girin</option>';
      hoodEl.disabled  = false;
    });
  }
}

/* ══════════════════════════════════════════════
   PREFILL
══════════════════════════════════════════════ */
function prefill(data) {
  const biz = data.business || {};

  // Temel alanlar
  const setVal = (id, v) => { const el = $(id); if (el) el.value = v || ''; };
  setVal('#bizName',      biz.name      || '');
  setVal('#aboutText',    biz.about     || '');
  setVal('#buildingNo',   biz.buildingNo|| '');
  setVal('#mapUrl',       biz.mapUrl    || '');
  setVal('#contactPhone', (biz.phone||'').replace(/\D/g,'').slice(0,10));

  // Brand name topbar
  const brand = $('#brandName');
  if (brand && biz.name) brand.querySelector('span').textContent = biz.name;

  // İl
  const cityEl = $('#city');
  if (cityEl && biz.city) {
    if (!$(`#city option[value="${CSS.escape(biz.city)}"]`)) {
      const opt = document.createElement('option');
      opt.value = opt.textContent = biz.city;
      cityEl.appendChild(opt);
    }
    cityEl.value = biz.city;
    cityEl.dispatchEvent(new Event('change'));
  }

  // İlçe + mahalle — combo async yükleme için yeterli bekleme süresi
  // INIT_PHASE bu blok bitene kadar true kalır; böylece dispatchEvent DIRTY'yi kirletmez
  if (biz.district || biz.neighborhood) {
    setTimeout(() => {
      const distEl = $('#district');
      if (distEl && biz.district) {
        if (!$(`#district option[value="${CSS.escape(biz.district)}"]`)) {
          const opt = document.createElement('option');
          opt.value = opt.textContent = biz.district;
          distEl.appendChild(opt);
        }
        distEl.value    = biz.district;
        distEl.disabled = false;
        // dispatchEvent yerine manuel tetikle — INIT_PHASE true olduğu için dirty olmaz
        distEl.dispatchEvent(new Event('change'));
      }
      // Combo'nun mahalle listesini yüklemesi için daha uzun bekle
      setTimeout(() => {
        const hoodEl = $('#hood');
        if (hoodEl && biz.neighborhood) {
          if (!$(`#hood option[value="${CSS.escape(biz.neighborhood)}"]`)) {
            const opt = document.createElement('option');
            opt.value = opt.textContent = biz.neighborhood;
            hoodEl.appendChild(opt);
          }
          hoodEl.value    = biz.neighborhood;
          hoodEl.disabled = false;
        }
        // Tüm adres alanları yüklendikten sonra INIT_PHASE kapat
        window._settingsAddrReady = true;
        if (window._settingsBaseReady) {
          INIT_PHASE = false;
          setDirty(false);
        }
      }, 700);
    }, 500);
  } else {
    // District/neighborhood yoksa hemen hazır
    window._settingsAddrReady = true;
    if (window._settingsBaseReady) {
      INIT_PHASE = false;
      setDirty(false);
    }
  }

  // Saatler
  bizHours = { ...defaultHours(), ...data.hours };
  renderHoursInline();

  // Hizmetler
  services = (data.services || []).length
    ? data.services
    : [{ name: 'Erkek Saç Kesimi', min: 30, price: 300 }, { name: 'Sakal Kesimi', min: 20, price: 150 }];
  renderServices();

  // Görseller
  const images   = data.images || {};
  const coverVal = images.cover;
  const coverArr = Array.isArray(coverVal) ? coverVal : (coverVal ? [coverVal] : []);
  renderThumbs('#coverThumbs', coverArr, 'cover');
  renderThumbs('#salonThumbs', Array.isArray(images.salon) ? images.salon : [], 'salon');
  renderThumbs('#modelThumbs', Array.isArray(images.model) ? images.model : [], 'model');
}

/* ══════════════════════════════════════════════
   KAYDET
══════════════════════════════════════════════ */
async function saveAll(options = {}) {
  const { silent = false, reason = 'change' } = options;
  if (SAVE_IN_FLIGHT) return;
  SAVE_IN_FLIGHT = true;
  clearTimeout(AUTO_SAVE_TIMER);
  // Saat validasyonu
  for (const { k, label } of DAYS) {
    if (!validateDay(bizHours[k])) {
      showToast(`${label}: Kapanış açılıştan büyük olmalı`, 'error');
      SAVE_IN_FLIGHT = false;
      return;
    }
  }

  const payload = {
    name:         ($('#bizName')?.value || '').trim(),
    about:        ($('#aboutText')?.value || '').trim(),
    phone:        ($('#contactPhone')?.value || '').replace(/\D/g,'').slice(0,10),
    city:         $('#city')?.value || '',
    district:     $('#district')?.value || '',
    neighborhood: $('#hood')?.value || '',
    buildingNo:   ($('#buildingNo')?.value || '').trim(),
    mapUrl:       ($('#mapUrl')?.value || '').trim(),
    hours:        bizHours,
    services:     services
      .map(s => ({ name: (s.name||'').trim(), min: Math.max(1, Math.floor(Number(s.min)||1)), price: Number(s.price)||0 }))
      .filter(s => s.name),
  };

  try {
    const res = await apiPost('/api/settings/save.php', payload);
    if (!res.ok) throw new Error(res.error || 'Kayıt başarısız');
    if (!silent) showToast(autoSaveMessage(reason), 'success');
    setDirty(false);
    const brand = $('#brandName');
    if (brand && payload.name) brand.querySelector('span').textContent = payload.name;
  } catch (err) {
    showToast('Kaydedilemedi: ' + err.message, 'error');
  } finally {
    SAVE_IN_FLIGHT = false;
  }
}

window.addEventListener('beforeunload', e => {
  if (DIRTY || SAVE_IN_FLIGHT) { e.preventDefault(); e.returnValue = ''; }
});

/* ══════════════════════════════════════════════
   INIT
══════════════════════════════════════════════ */
// Yükleme animasyonu için CSS (spin keyframe)
const spinCSS = document.createElement('style');
spinCSS.textContent = `@keyframes spin { to { transform: rotate(360deg); } }`;
document.head.appendChild(spinCSS);

document.addEventListener('DOMContentLoaded', async () => {
  bindPhoneMask();
  ['cover', 'salon', 'model'].forEach(bindUploader);

  await initLocationCombo();

  try {
    const res = await apiGet('/api/settings/load.php');
    if (!res.ok) { showToast('Veriler yüklenemedi: ' + (res.error || ''), 'error'); return; }

    // Combo async yükleme için kısa bekleme
    await new Promise(r => setTimeout(r, 400));

    prefill(res.data);

    // viewProfileBtn linki
    try {
      const meRes = await apiGet('/api/auth/me.php');
      const bizId = meRes?.data?.businessId;
      if (bizId) {
        const btn = $('#viewProfileBtn');
        if (btn) { btn.href = `profile.html?id=${bizId}`; btn.target = '_blank'; btn.rel = 'noopener'; }
      }
    } catch (_) { /* sessizce geç */ }

    attachDirtyWatchers();

    // INIT_PHASE'i adres combo yüklenmesi tamamlanana kadar açık bırak.
    // prefill() içindeki setTimeout'lar bitince window._settingsAddrReady = true yapılıp
    // buradaki flag ile birlikte INIT_PHASE kapatılır.
    window._settingsBaseReady = true;
    window._settingsAddrReady = window._settingsAddrReady || false;
    if (window._settingsAddrReady) {
      INIT_PHASE = false;
      setDirty(false);
    }
    // Güvenlik: en fazla 2.5sn içinde mutlaka kapat
    setTimeout(() => {
      if (INIT_PHASE) { INIT_PHASE = false; setDirty(false); }
    }, 2500);
  } catch (err) {
    if (err.message !== 'UNAUTHORIZED') showToast('Bağlantı hatası: ' + err.message, 'error');
  }
});
