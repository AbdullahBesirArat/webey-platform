/* ============================================================
   staff.js — Modern v60
   Kuaför Randevu Sistemi • Personel Yönetimi
   ============================================================ */

const API_STAFF    = '/api/staff/';
const API_CALENDAR = '/api/calendar/';

const DAY_KEYS = ['mon','tue','wed','thu','fri','sat','sun'];
const DAY_TR   = { mon:'Pazartesi', tue:'Salı', wed:'Çarşamba', thu:'Perşembe', fri:'Cuma', sat:'Cumartesi', sun:'Pazar' };

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

/* ── Renk paleti için sabit renkler ── */
const AVATAR_COLORS = [
  '#4f46e5','#7c3aed','#db2777','#dc2626','#d97706',
  '#16a34a','#0891b2','#0284c7','#9333ea','#059669'
];
function avatarColor(name) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff;
  return AVATAR_COLORS[Math.abs(h) % AVATAR_COLORS.length];
}
function initials(name) {
  return (name || '?').split(' ').map(w => w[0]).slice(0,2).join('').toUpperCase();
}

/* ──────────────────────────────────────────
   TOAST
────────────────────────────────────────── */
function showToast(msg, type = 'info') {
  const el = $('#toastEl');
  if (!el) { console.log(`[${type}]`, msg); return; }
  el.textContent = msg;
  el.className = 'toast show';
  if (type === 'success') el.classList.add('success');
  if (type === 'error')   el.classList.add('error');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show', 'success', 'error'), 4000);
}

/* ──────────────────────────────────────────
   API
────────────────────────────────────────── */

// ── API yardımcıları: wb-api-shim.js üzerinden ───────────────────────
// wb-api-shim.js staff.html'de bu dosyadan ÖNCE yüklenir.

async function apiGet(path, params)  { return window.WbApi.get(path, params); }
async function apiPost(path, body)   { return window.WbApi.post(path, body); }


/* ──────────────────────────────────────────
   GLOBAL STATE
────────────────────────────────────────── */
let staffList    = [];
let currentStaff = null;
let catalog      = [];   // işletme hizmet kataloğu
let bizHours     = {};   // işletme çalışma saatleri (kısıt için)
let staffServices = {};  // { staffId: Set<serviceId> }

function setBodyModalLock(locked) {
  document.body.classList.toggle('modal-open', !!locked);
}

/* ──────────────────────────────────────────
   BOOTSTRAP
────────────────────────────────────────── */
async function bootstrap() {
  try {
    const res = await apiGet('/api/calendar/bootstrap.php');
    if (!res.ok) { showToast('Oturum bilgisi alınamadı', 'error'); return false; }
    const d = res.data;
    bizHours = d.business?.defaultHours || {};
    const brandEl = $('#brandName');
    if (brandEl) brandEl.textContent = d.business?.name || '';
    catalog = d.catalog || [];
    return true;
  } catch (err) {
    showToast('Bağlantı hatası', 'error');
    return false;
  }
}

/* ──────────────────────────────────────────
   YARDIMCI: saat kısıt kontrolü
   Dükkan kapalıysa o gün personel açık olamaz.
   Personel saati dükkan saatleri dışına çıkamaz.
────────────────────────────────────────── */
function clampToBusinessHours(day, staffStart, staffEnd) {
  const bh = bizHours[day];
  if (!bh || !isBusinessOpen(day)) return null; // dükkan kapalı → personel de kapalı

  // Settings formatını destekle: {open:'10:00', close:'19:00'} VE {start:'09:00', end:'18:00'}
  const bizStart = bh.start || bh.from || (typeof bh.open  === 'string' ? bh.open  : '00:00');
  const bizEnd   = bh.end   || bh.to   || (typeof bh.close === 'string' ? bh.close : '23:59');

  // Basit string karşılaştırma (HH:MM formatı)
  const clamped = {
    start: staffStart < bizStart ? bizStart : staffStart,
    end:   staffEnd   > bizEnd   ? bizEnd   : staffEnd
  };
  // Eğer saat aralığı geçersizse dükkan saatine eşitle
  if (clamped.start >= clamped.end) {
    clamped.start = bizStart;
    clamped.end   = bizEnd;
  }
  return clamped;
}

function isBusinessOpen(day) {
  const bh = bizHours[day];
  if (!bh) return false;
  // Settings formatı: { closed: false, open: '10:00', close: '19:00' }
  if (bh.closed === true) return false;
  if (bh.open === false) return false;
  if (bh.open === true) return true;
  // open, '10:00' gibi saat string'i ise işletme açıktır
  if (typeof bh.open === 'string' && bh.open) return true;
  return false;
}

/* ──────────────────────────────────────────
   PERSONEL LİSTESİ
────────────────────────────────────────── */
async function loadStaff() {
  try {
    const res = await apiGet('/api/staff/list.php');
    if (!res.ok) { showToast(res.error || 'Personel listesi alınamadı', 'error'); return; }
    staffList = res.data.staff || [];

    // ─────────────────────────────────────────────────────────
    // OTOMATİK HİZMET ATAMA:
    // Hiç hizmeti olmayan personele (admin dahil) katalogdaki
    // tüm hizmetler otomatik atanır. Yönetici daha sonra
    // staff sayfasından dilediği gibi değiştirebilir.
    // ─────────────────────────────────────────────────────────
    if (catalog.length > 0) {
      const allServiceIds = catalog.map(s => String(s.id));
      const toAutoAssign  = staffList.filter(s => !s.serviceIds || s.serviceIds.length === 0);

      if (toAutoAssign.length > 0) {
        await Promise.all(
          toAutoAssign.map(async (s) => {
            try {
              const r = await apiPost('/api/staff/save-services.php', {
                staffId: s.id,
                serviceIds: allServiceIds
              });
              if (r.ok) {
                s.serviceIds = allServiceIds; // local state güncelle
              }
            } catch (e) {
              // sessizce devam et — UI bozulmasın
              console.warn('[autoAssign] Hizmet atanamadı:', s.name, e);
            }
          })
        );
      }
    }

    renderStaffList();
    if (staffList.length > 0) openStaff(staffList[0]);
    else { currentStaff = null; renderPanelEmpty(); }
  } catch (err) {
    showToast('Personel listesi yüklenemedi', 'error');
  }
}

function renderStaffList() {
  const body = $('#staffCardBody');
  const track = $('#staffCardTrack') || body;
  if (!body || !track) return;
  track.innerHTML = '';
  track.classList.remove('staff-card__track--empty');
  body.scrollLeft = 0;

  if (!staffList.length) {
    const empty = document.createElement('div');
    empty.className = 'staff-empty';
    empty.innerHTML = `<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".4"><circle cx="12" cy="7" r="4"/><path d="M5.5 20a6.5 6.5 0 0 1 13 0"/></svg><div>Henüz personel eklenmemiş.</div>`;
    track.classList.add('staff-card__track--empty');
    track.appendChild(empty);
    return;
  }

  // İlk kişiyi yönetici say
  staffList.forEach((s, idx) => {
    const isOwner = idx === 0;
    if (idx === 0) {
      const ownerLabel = document.createElement('div');
      ownerLabel.className = 'staff-section-label';
      ownerLabel.textContent = 'Yönetici';
      track.appendChild(ownerLabel);
    }
    if (idx === 1) {
      const staffLabel = document.createElement('div');
      staffLabel.className = 'staff-section-label';
      staffLabel.textContent = 'Personel';
      track.appendChild(staffLabel);
    }

    const color = s.color || avatarColor(s.name || '?');
    const btn = document.createElement('button');
    btn.className = 'staff-item';
    btn.dataset.id = s.id;
    btn.setAttribute('type', 'button');
    btn.innerHTML = `
      <div class="staff-avatar" style="background:${color};">
        ${initials(s.name)}
      </div>
      <div class="staff-item__info">
        <div class="staff-item__name">${s.name}</div>
        <div class="staff-item__role">${isOwner ? 'Yönetici' : 'Personel'}</div>
      </div>
      ${isOwner ? `<span class="staff-badge">Admin</span>` : ''}`;
    btn.addEventListener('click', () => openStaff(s));
    track.appendChild(btn);
  });

  if (window.matchMedia('(max-width: 1024px)').matches) {
    requestAnimationFrame(() => {
      body.scrollLeft = 0;
    });
  }
}

function setActiveStaffItem(staffId) {
  $$('.staff-item').forEach(btn => {
    btn.classList.toggle('is-active', btn.dataset.id == staffId);
  });
}

/* ──────────────────────────────────────────
   PANEL AÇ / BOSALT
────────────────────────────────────────── */
function openStaff(s) {
  currentStaff = s;
  setActiveStaffItem(s.id);

  // Header güncelle
  const color = s.color || avatarColor(s.name || '?');
  const pAvatar = $('#panelAvatar');
  if (pAvatar) {
    pAvatar.style.background = color;
    pAvatar.textContent = initials(s.name);
  }
  const pTitle = $('#panelTitle');
  if (pTitle) pTitle.textContent = s.name;
  const pSub = $('#panelSubtitle');
  if (pSub) pSub.textContent = currentStaff && String(currentStaff.id) === String(staffList[0]?.id) ? 'Yönetici' : 'Personel';

  // Calendar linki
  const calBtn = $('#showCalendarBtn');
  if (calBtn) calBtn.href = `calendar.html?staff=${s.id}`;

  // Srvbar adı
  const srvName = $('#srvStaffName');
  if (srvName) srvName.textContent = s.name;

  renderServicesTab();
  renderHoursTab();
}

function renderPanelEmpty() {
  const pTitle = $('#panelTitle');
  if (pTitle) pTitle.textContent = 'Personel seçin';
  const pSub = $('#panelSubtitle');
  if (pSub) pSub.textContent = 'Soldan bir personel seçin';
  const pAvatar = $('#panelAvatar');
  if (pAvatar) { pAvatar.style.background = '#e5e7eb'; pAvatar.textContent = ''; }
}

/* ──────────────────────────────────────────
   HİZMETLER SEKMESİ
────────────────────────────────────────── */
function getStaffServices() {
  if (!currentStaff) return new Set();
  return staffServices[currentStaff.id] || new Set((currentStaff.serviceIds || []));
}
function setStaffServices(svcSet) {
  if (!currentStaff) return;
  staffServices[currentStaff.id] = svcSet;
}

function renderServicesTab() {
  const srvList = $('#srvList');
  const emptyEl = $('#srvEmpty');
  const noResult = $('#srvNoResult');
  if (!srvList) return;

  srvList.innerHTML = '';

  if (!catalog.length) {
    if (emptyEl) emptyEl.style.display = '';
    const cnt = $('#srvAssignedCount');
    if (cnt) cnt.textContent = '0';
    return;
  }
  if (emptyEl) emptyEl.style.display = 'none';
  if (noResult) noResult.style.display = 'none';

  const assigned = getStaffServices();
  let assignedCount = 0;

  catalog.forEach(svc => {
    const isOn = assigned.has(String(svc.id));
    if (isOn) assignedCount++;
    const li = document.createElement('li');
    li.className = `svc-item${isOn ? ' is-assigned' : ''}`;
    li.dataset.id = svc.id;
    li.dataset.name = (svc.name || '').toLowerCase();
    li.innerHTML = `
      <div class="svc-item__dot"></div>
      <div class="svc-item__info">
        <div class="svc-item__name">${svc.name}</div>
        <div class="svc-item__meta">${svc.durationMin ?? 0} dk • ₺${svc.price ?? 0}</div>
      </div>
      <button type="button" class="svc-toggle ${isOn ? 'is-on' : 'is-off'}" data-id="${svc.id}" aria-pressed="${isOn}">
        ${isOn ? 'Atandı' : 'Ata'}
      </button>`;
    li.querySelector('.svc-toggle').addEventListener('click', () => toggleService(svc.id, li));
    srvList.appendChild(li);
  });

  const cnt = $('#srvAssignedCount');
  if (cnt) cnt.textContent = String(assignedCount);
  syncSelectAllState();
}

function toggleService(svcId, liEl) {
  const assigned = getStaffServices();
  const id = String(svcId);
  const isOn = assigned.has(id);
  if (isOn) assigned.delete(id);
  else assigned.add(id);
  setStaffServices(assigned);

  // UI güncelle
  const btn = liEl.querySelector('.svc-toggle');
  liEl.classList.toggle('is-assigned', !isOn);
  if (btn) {
    btn.classList.toggle('is-on', !isOn);
    btn.classList.toggle('is-off', isOn);
    btn.setAttribute('aria-pressed', String(!isOn));
    btn.textContent = !isOn ? 'Atandı' : 'Ata';
  }

  // Sayaç
  const cnt = $('#srvAssignedCount');
  if (cnt) cnt.textContent = String(getStaffServices().size);
  syncSelectAllState();
}

async function saveServices() {
  if (!currentStaff) return;
  try {
    const serviceIds = [...getStaffServices()];
    const res = await apiPost('/api/staff/save-services.php', { staffId: currentStaff.id, serviceIds });
    if (!res.ok) throw new Error(res.error || 'Kayıt başarısız');
    // Personel listesinde de güncelle
    const s = staffList.find(x => x.id == currentStaff.id);
    if (s) s.serviceIds = serviceIds;
    showToast('Hizmet atamaları kaydedildi', 'success');
  } catch (err) {
    showToast(err.message, 'error');
  }
}

/* Arama */
function filterServices(query) {
  const q = query.toLowerCase().trim();
  let visible = 0;
  $$('.svc-item').forEach(li => {
    const match = !q || li.dataset.name.includes(q);
    li.style.display = match ? '' : 'none';
    if (match) visible++;
  });
  const noResult = $('#srvNoResult');
  if (noResult) noResult.style.display = visible ? 'none' : '';
}

function syncSelectAllState() {
  const toggle = $('#srvSelectAll');
  if (!toggle) return;

  const visibleItems = $$('.svc-item').filter(li => li.style.display !== 'none');
  if (!visibleItems.length) {
    toggle.checked = false;
    toggle.indeterminate = false;
    return;
  }

  const assigned = getStaffServices();
  const selectedCount = visibleItems.filter(li => assigned.has(String(li.dataset.id))).length;

  toggle.checked = selectedCount === visibleItems.length;
  toggle.indeterminate = selectedCount > 0 && selectedCount < visibleItems.length;
}

/* ──────────────────────────────────────────
   ÇALIŞMA SAATLERİ SEKMESİ
────────────────────────────────────────── */
function renderHoursTab() {
  const wrap = $('#tab-hours');
  if (!wrap || !currentStaff) return;

  const hours = currentStaff.hoursOverride || {};

  let rows = '';
  DAY_KEYS.forEach(day => {
    const h       = hours[day] || {};
    const bizOpen = isBusinessOpen(day);
    const isOpen  = bizOpen && (h.open === true);
    const from    = h.start || h.from || (bizHours[day]?.start || bizHours[day]?.from || '09:00');
    const to      = h.end   || h.to   || (bizHours[day]?.end   || bizHours[day]?.to   || '18:00');

    rows += `
    <div class="hours-row${isOpen ? ' is-open' : ' is-closed'}" data-day="${day}">
      <div class="hours-row__left">
        <input type="checkbox" class="day-toggle" data-day="${day}"
          ${isOpen ? 'checked' : ''} ${!bizOpen ? 'disabled title="İşletme bugün kapalı"' : ''}
          id="hh-${day}" aria-label="${DAY_TR[day]}">
        <label for="hh-${day}" class="hours-day-name">${DAY_TR[day]}</label>
        <span class="hours-status">${!bizOpen ? 'İşletme kapalı' : isOpen ? 'Açık' : 'Kapalı'}</span>
      </div>
      <div class="hours-times${isOpen ? '' : ' is-disabled'}">
        <label class="hours-time-field">
          <span class="hours-time-chip">
            <span class="material-symbols-rounded hours-time-icon" aria-hidden="true">schedule</span>
            <span class="hours-time-label">Başlangıç</span>
          </span>
          <input type="time" class="time-input" data-role="open" value="${from}" ${!isOpen ? 'disabled' : ''}>
        </label>
        <label class="hours-time-field">
          <span class="hours-time-chip">
            <span class="material-symbols-rounded hours-time-icon" aria-hidden="true">schedule</span>
            <span class="hours-time-label">Bitiş</span>
          </span>
          <input type="time" class="time-input" data-role="close" value="${to}" ${!isOpen ? 'disabled' : ''}>
        </label>
      </div>
    </div>`;
  });

  wrap.innerHTML = `
    <div class="hours-header">
      <div class="hours-header-text">
        <h3>${currentStaff.name} • Çalışma Saatleri</h3>
        <p>İşletme saatleri dışına çıkamazsınız.</p>
      </div>
      <button class="btn primary" id="saveHoursBtn" type="button">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
        Kaydet
      </button>
    </div>
    <div class="hours-grid">${rows}</div>
    <div class="hours-note">Bilgi: Gri görünen günler işletmenizin kapalı olduğu günlerdir.</div>`;

  // Toggle listener
  $$('.day-toggle', wrap).forEach(chk => {
    chk.addEventListener('change', () => {
      const row = chk.closest('.hours-row');
      const timesDiv = row.querySelector('.hours-times');
      const statusEl = row.querySelector('.hours-status');
      const timeInputs = row.querySelectorAll('.time-input');
      const enabled = chk.checked;
      timesDiv.classList.toggle('is-disabled', !enabled);
      timeInputs.forEach(inp => inp.disabled = !enabled);
      row.classList.toggle('is-open', enabled);
      row.classList.toggle('is-closed', !enabled);
      if (statusEl) statusEl.textContent = enabled ? 'Açık' : 'Kapalı';
    });
  });

  // Saat değiştiğinde kısıt uygula
  $$('.hours-row', wrap).forEach(row => {
    const day = row.dataset.day;
    const openInp  = row.querySelector('[data-role="open"]');
    const closeInp = row.querySelector('[data-role="close"]');
    if (!openInp || !closeInp) return;

    function applyClamp() {
      const clamped = clampToBusinessHours(day, openInp.value, closeInp.value);
      if (!clamped) return;
      if (openInp.value !== clamped.start) openInp.value = clamped.start;
      if (closeInp.value !== clamped.end) closeInp.value = clamped.end;
    }
    openInp.addEventListener('change', () => {
      // Başlangıç bitiş'ten büyük olamaz
      if (openInp.value >= closeInp.value) {
        closeInp.value = openInp.value;
        // 1 saat ekle
        const [h, m] = openInp.value.split(':').map(Number);
        const newH = Math.min(h + 1, 23);
        closeInp.value = `${String(newH).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
      }
      applyClamp();
    });
    closeInp.addEventListener('change', () => {
      if (closeInp.value <= openInp.value) {
        openInp.value = closeInp.value;
        const [h, m] = closeInp.value.split(':').map(Number);
        const newH = Math.max(h - 1, 0);
        openInp.value = `${String(newH).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
      }
      applyClamp();
    });
  });

  $('#saveHoursBtn', wrap)?.addEventListener('click', saveHours);
}

async function saveHours() {
  if (!currentStaff) return;
  const wrap = $('#tab-hours');
  const hours = {};
  let hasWarning = false;

  DAY_KEYS.forEach(day => {
    const row    = wrap.querySelector(`.hours-row[data-day="${day}"]`);
    if (!row) return;
    const isOpen = row.querySelector('.day-toggle')?.checked;
    const from   = row.querySelector('[data-role="open"]')?.value || '09:00';
    const to     = row.querySelector('[data-role="close"]')?.value || '18:00';

    if (isOpen) {
      // Son bir kez kısıt uygula
      const clamped = clampToBusinessHours(day, from, to);
      if (!clamped) {
        hours[day] = { open: false, start: from, end: to };
        hasWarning = true;
        return;
      }
      hours[day] = { open: true, start: clamped.start, end: clamped.end };
    } else {
      hours[day] = { open: false, start: from, end: to };
    }
  });

  if (hasWarning) {
    showToast('Bazı günler işletme kapalı olduğu için kapatıldı', 'info');
  }

  try {
    const res = await apiPost('/api/staff/save-hours.php', { staffId: currentStaff.id, hours });
    if (!res.ok) throw new Error(res.error || 'Kayıt başarısız');
    currentStaff.hoursOverride = hours;
    const s = staffList.find(x => x.id == currentStaff.id);
    if (s) s.hoursOverride = hours;
    showToast('Çalışma saatleri kaydedildi', 'success');
    renderHoursTab(); // Güncelle
  } catch (err) {
    showToast(err.message, 'error');
  }
}

/* ──────────────────────────────────────────
   YENİ PERSONEL EKLE MODALİ
────────────────────────────────────────── */
function openAddStaffModal() {
  const modal = $('#addStaffModal');
  if (!modal) return;
  modal.style.display = 'flex';
  modal.setAttribute('aria-hidden', 'false');
  setBodyModalLock(true);

  // Reset
  $('#asName').value  = '';
  $('#asPhone').value = '';
  const preview = $('#asAvatarPreview');
  if (preview) { preview.style.display = 'none'; preview.src = ''; }
  const hint = $('#asAvatarEmptyHint');
  if (hint) hint.style.display = '';

  renderAddStaffHours();
  setTimeout(() => $('#asName')?.focus(), 50);
}

function closeAddStaffModal() {
  const modal = $('#addStaffModal');
  if (!modal) return;
  modal.style.display = 'none';
  modal.setAttribute('aria-hidden', 'true');
  setBodyModalLock(false);
}

function renderAddStaffHours() {
  const grid = $('#asHoursGrid');
  if (!grid) return;
  grid.innerHTML = '';

  DAY_KEYS.forEach(day => {
    const bh     = bizHours[day] || {};
    const bizOpen = isBusinessOpen(day);
    const from   = bh.start || bh.from || '09:00';
    const to     = bh.end   || bh.to   || '18:00';

    const row = document.createElement('div');
    row.className = 'hours-row' + (bizOpen ? ' is-open' : ' is-closed');
    row.dataset.day = day;
    row.innerHTML = `
      <div class="hours-row__left">
        <input type="checkbox" class="day-toggle" id="as-${day}" data-day="${day}"
          ${bizOpen ? 'checked' : ''} ${!bizOpen ? 'disabled title="İşletme bugün kapalı"' : ''}
          aria-label="${DAY_TR[day]}">
        <label for="as-${day}" class="hours-day-name">${DAY_TR[day]}</label>
        <span class="hours-status">${!bizOpen ? 'Kapalı' : 'Açık'}</span>
      </div>
      <div class="hours-times${bizOpen ? '' : ' is-disabled'}">
        <label class="hours-time-field">
          <span class="hours-time-chip">
            <span class="material-symbols-rounded hours-time-icon" aria-hidden="true">schedule</span>
            <span class="hours-time-label">Başlangıç</span>
          </span>
          <input type="time" class="time-input" data-role="open" value="${from}" ${!bizOpen ? 'disabled' : ''}>
        </label>
        <label class="hours-time-field">
          <span class="hours-time-chip">
            <span class="material-symbols-rounded hours-time-icon" aria-hidden="true">schedule</span>
            <span class="hours-time-label">Bitiş</span>
          </span>
          <input type="time" class="time-input" data-role="close" value="${to}" ${!bizOpen ? 'disabled' : ''}>
        </label>
      </div>`;

    row.querySelector('.day-toggle').addEventListener('change', e => {
      const times = row.querySelector('.hours-times');
      const statusEl = row.querySelector('.hours-status');
      const timeInputs = row.querySelectorAll('.time-input');
      times.classList.toggle('is-disabled', !e.target.checked);
      timeInputs.forEach(inp => inp.disabled = !e.target.checked);
      row.classList.toggle('is-open', e.target.checked);
      row.classList.toggle('is-closed', !e.target.checked);
      if (statusEl) statusEl.textContent = e.target.checked ? 'Açık' : 'Kapalı';
    });

    grid.appendChild(row);
  });
}

async function saveNewStaff() {
  const name  = ($('#asName')?.value  || '').trim();
  const phone = ($('#asPhone')?.value || '').trim().replace(/\D/g, '');

  if (!name) { showToast('Ad Soyad zorunludur', 'error'); $('#asName')?.focus(); return; }

  const saveBtn = $('#addStaffSave');
  if (saveBtn) { saveBtn.disabled = true; saveBtn.textContent = 'Kaydediliyor…'; }

  try {
    const res = await apiPost('/api/staff/save.php', { name, phone: phone || null });
    if (!res.ok) throw new Error(res.error || 'Kayıt başarısız');

    const newId = res.data.id;

    // Saatleri kaydet
    const grid  = $('#asHoursGrid');
    const hours = {};
    if (grid) {
      DAY_KEYS.forEach(day => {
        const row    = grid.querySelector(`.hours-row[data-day="${day}"]`);
        if (!row) return;
        const isOpen = row.querySelector('.day-toggle')?.checked;
        const from   = row.querySelector('[data-role="open"]')?.value || '09:00';
        const to     = row.querySelector('[data-role="close"]')?.value || '18:00';

        if (isOpen) {
          const clamped = clampToBusinessHours(day, from, to);
          hours[day] = clamped ? { open: true, start: clamped.start, end: clamped.end } : { open: false, start: from, end: to };
        } else {
          hours[day] = { open: false, start: from, end: to };
        }
      });
      await apiPost('/api/staff/save-hours.php', { staffId: newId, hours });
    }

    showToast(`${name} eklendi`, 'success');
    closeAddStaffModal();
    await loadStaff();

  } catch (err) {
    showToast(err.message, 'error');
  } finally {
    if (saveBtn) { saveBtn.disabled = false; saveBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Personeli Kaydet'; }
  }
}

/* ──────────────────────────────────────────
   PERSONEL SİL MODALİ
────────────────────────────────────────── */
function openDelStaffModal() {
  const modal = $('#delStaffModal');
  if (!modal) return;

  const list = $('#delStaffList');
  if (list) {
    list.innerHTML = '';
    // İlk kişi (yönetici) silinemez — index 0'ı atlıyoruz
    const deletable = staffList.slice(1);
    if (!deletable.length) {
      list.innerHTML = '<li style="padding:12px;color:#6b7280;font-size:13px;">Silinebilecek personel yok.</li>';
    } else {
      deletable.forEach(s => {
        const color = s.color || avatarColor(s.name || '?');
        const li = document.createElement('li');
        li.className = 'del-item';
        li.innerHTML = `
          <div class="staff-avatar" style="background:${color};width:36px;height:36px;font-size:13px;">
            ${initials(s.name)}
          </div>
          <label>
            <div class="del-item__name">${s.name}</div>
            <div class="del-item__role">Personel</div>
          </label>
          <input type="checkbox" data-id="${s.id}" data-name="${s.name}" aria-label="${s.name} sil">`;
        li.querySelector('input').addEventListener('change', updateDelConfirmBtn);
        li.addEventListener('click', e => {
          if (e.target.tagName !== 'INPUT') {
            const chk = li.querySelector('input');
            chk.checked = !chk.checked;
            updateDelConfirmBtn();
          }
        });
        list.appendChild(li);
      });
    }
  }

  const selectAll = $('#delSelectAll');
  if (selectAll) { selectAll.checked = false; }
  updateDelConfirmBtn();

  modal.style.display = 'flex';
  modal.setAttribute('aria-hidden', 'false');
  setBodyModalLock(true);
}

function closeDelStaffModal() {
  const modal = $('#delStaffModal');
  if (!modal) return;
  modal.style.display = 'none';
  modal.setAttribute('aria-hidden', 'true');
  setBodyModalLock(false);
}

function updateDelConfirmBtn() {
  const checked = $$('#delStaffList input[type="checkbox"]:checked');
  const btn = $('#delStaffConfirm');
  if (btn) {
    btn.disabled = checked.length === 0;
    btn.textContent = checked.length > 0 ? `${checked.length} Personeli Sil` : 'Seçilenleri Sil';
  }
}

async function deleteSelectedStaff() {
  const checked = $$('#delStaffList input[type="checkbox"]:checked');
  if (!checked.length) return;

  const names = checked.map(c => c.dataset.name).join(', ');
  const ids   = checked.map(c => c.dataset.id);

  const confirmBtn = $('#delStaffConfirm');
  if (confirmBtn) { confirmBtn.disabled = true; confirmBtn.textContent = 'Siliniyor…'; }

  try {
    for (const id of ids) {
      const res = await apiPost('/api/staff/delete.php', { id });
      if (!res.ok) throw new Error(res.error || `${id} silinemedi`);
    }
    showToast(`${names} silindi`, 'success');
    closeDelStaffModal();
    await loadStaff();
  } catch (err) {
    showToast(err.message, 'error');
    if (confirmBtn) { confirmBtn.disabled = false; updateDelConfirmBtn(); }
  }
}

/* ──────────────────────────────────────────
   EVENT LISTENERS
────────────────────────────────────────── */
function initEvents() {
  // Personel ekle
  $('#btnAddSmall')?.addEventListener('click', openAddStaffModal);

  // Personel sil
  $('#btnRemoveSmall')?.addEventListener('click', openDelStaffModal);

  // Add modal
  $('#addStaffClose')?.addEventListener('click', closeAddStaffModal);
  $('#addStaffCancel')?.addEventListener('click', closeAddStaffModal);
  $('#addStaffSave')?.addEventListener('click', saveNewStaff);
  $('#addStaffModal')?.addEventListener('click', e => { if (e.target === e.currentTarget) closeAddStaffModal(); });
  $('#asName')?.addEventListener('keydown', e => { if (e.key === 'Enter') saveNewStaff(); });

  // Toplu saat ayarları (addStaff modal)
  $('#asAllStd')?.addEventListener('click', () => {
    $$('#asHoursGrid .day-toggle').forEach(chk => {
      if (!chk.disabled) { chk.checked = true; chk.dispatchEvent(new Event('change')); }
    });
    $$('#asHoursGrid [data-role="open"]').forEach(el => el.value = '09:00');
    $$('#asHoursGrid [data-role="close"]').forEach(el => el.value = '18:00');
    // Kısıt uygula
    DAY_KEYS.forEach(day => {
      const row = $('#asHoursGrid .hours-row[data-day="'+day+'"]');
      if (!row) return;
      const openInp = row.querySelector('[data-role="open"]');
      const closeInp = row.querySelector('[data-role="close"]');
      if (!openInp || !closeInp) return;
      const clamped = clampToBusinessHours(day, openInp.value, closeInp.value);
      if (clamped) { openInp.value = clamped.start; closeInp.value = clamped.end; }
    });
  });
  $('#asAllOff')?.addEventListener('click', () => {
    $$('#asHoursGrid .day-toggle').forEach(chk => { chk.checked = false; chk.dispatchEvent(new Event('change')); });
  });

  // Del modal
  $('#delStaffClose')?.addEventListener('click', closeDelStaffModal);
  $('#delStaffCancel')?.addEventListener('click', closeDelStaffModal);
  $('#delStaffModal')?.addEventListener('click', e => { if (e.target === e.currentTarget) closeDelStaffModal(); });
  $('#delStaffConfirm')?.addEventListener('click', deleteSelectedStaff);
  $('#delSelectAll')?.addEventListener('change', e => {
    $$('#delStaffList input[type="checkbox"]').forEach(chk => { chk.checked = e.target.checked; });
    updateDelConfirmBtn();
  });

  // Avatar preview (addStaff)
  $('#asAvatarPick')?.addEventListener('change', e => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = ev => {
      const preview = $('#asAvatarPreview');
      const hint = $('#asAvatarEmptyHint');
      if (preview) { preview.src = ev.target.result; preview.style.display = 'block'; }
      if (hint) hint.style.display = 'none';
    };
    reader.readAsDataURL(file);
  });
  $('#asAvatarRemove')?.addEventListener('click', () => {
    const preview = $('#asAvatarPreview');
    const hint = $('#asAvatarEmptyHint');
    if (preview) { preview.src = ''; preview.style.display = 'none'; }
    if (hint) hint.style.display = '';
    const pick = $('#asAvatarPick');
    if (pick) pick.value = '';
  });

  // Servis arama
  $('#srvSearch')?.addEventListener('input', e => filterServices(e.target.value));

  // Tümünü seç
  $('#srvSelectAll')?.addEventListener('change', e => {
    const assigned = getStaffServices();
    const allVisible = $$('.svc-item').filter(li => li.style.display !== 'none');
    if (e.target.checked) {
      allVisible.forEach(li => { assigned.add(li.dataset.id); li.classList.add('is-assigned'); updateSvcItem(li, true); });
    } else {
      allVisible.forEach(li => { assigned.delete(li.dataset.id); li.classList.remove('is-assigned'); updateSvcItem(li, false); });
    }
    setStaffServices(assigned);
    const cnt = $('#srvAssignedCount');
    if (cnt) cnt.textContent = String(assigned.size);
    syncSelectAllState();
  });

  // Servis kaydet/iptal
  $('#srvSaveBottom')?.addEventListener('click', saveServices);
  $('#srvCancel')?.addEventListener('click', () => { renderServicesTab(); });
  $('#srvClearBottom')?.addEventListener('click', () => {
    setStaffServices(new Set());
    renderServicesTab();
  });

  // Sekmeler
  const tabBtns   = $$('.tab');
  const tabPanels = $$('[role="tabpanel"]');
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => { b.classList.remove('is-active'); b.setAttribute('aria-selected', 'false'); b.setAttribute('tabindex', '-1'); });
      tabPanels.forEach(p => { p.hidden = p.id !== btn.getAttribute('aria-controls'); });
      btn.classList.add('is-active');
      btn.setAttribute('aria-selected', 'true');
      btn.setAttribute('tabindex', '0');
    });
  });

  // İlk tab aktif
  const firstTab = $('#tabBtnServices');
  if (firstTab) { firstTab.classList.add('is-active'); firstTab.setAttribute('aria-selected', 'true'); firstTab.setAttribute('tabindex', '0'); }
  tabPanels.forEach(p => { p.hidden = p.id !== 'tab-services'; });

  // Escape ile modal kapat
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    if ($('#addStaffModal[aria-hidden="false"]')) closeAddStaffModal();
    if ($('#delStaffModal[aria-hidden="false"]')) closeDelStaffModal();
  });
}

function updateSvcItem(li, isOn) {
  const btn = li.querySelector('.svc-toggle');
  const dot = li.querySelector('.svc-item__dot');
  if (btn) {
    btn.classList.toggle('is-on', isOn);
    btn.classList.toggle('is-off', !isOn);
    btn.setAttribute('aria-pressed', String(isOn));
    btn.textContent = isOn ? 'Atandı' : 'Ata';
  }
  if (dot) dot.style.background = isOn ? 'var(--green)' : 'var(--border)';
}

/* ──────────────────────────────────────────
   INIT
────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', async () => {
  initEvents();
  const ok = await bootstrap();
  if (!ok) return;
  await loadStaff();
});
