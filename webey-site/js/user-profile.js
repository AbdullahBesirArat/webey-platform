/* user-profile.js — v35
 *
 * Yenilikler:
 *  - Yaklaşan randevular: sabit alan, boş durumda "Henüz randevunuz yok"
 *  - Tüm Randevular: durum filtresi (Geçmiş/Gelecek/Onaylanan/Bekleyen/İptal)
 *  - Salon adı arama, tarih seçici
 *  - Sayfalama (10/sayfa)
 *  - Ayarlar: daha profesyonel düzenleme deneyimi
 */

/* ─── Utils ─── */
const $  = (s, r=document) => r.querySelector(s);
const $$ = (s, r=document) => Array.from(r.querySelectorAll(s));
const pad = n => String(n).padStart(2,'0');
const MON = ['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
const DOW = ['Paz','Pts','Sal','Çar','Per','Cum','Cts'];
const escapeHtml = s => String(s||'').replace(/[&<>"']/g, m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const digits = s => String(s||'').replace(/\D/g,'');
const normPhone = s => { const d=digits(s); if(d.startsWith('90')&&d.length===12) return d.slice(2); if(d.startsWith('0')) return d.slice(1); return d.slice(-10); };
const humanPhone = s => { const d=digits(normPhone(s)); if(d.length!==10) return s||''; return `+90 ${d.slice(0,3)} ${d.slice(3,6)} ${d.slice(6,8)} ${d.slice(8)}`; };

/* ─── Toast ─── */
const toastEl = $('#toast');
function showToast(msg, ok=true){
  if(!toastEl){ console.log('[toast]',msg); return; }
  toastEl.textContent = msg;
  toastEl.style.background = ok ? 'var(--brand,#0ea5b3)' : 'var(--danger,#ef4444)';
  toastEl.classList.add('show');
  clearTimeout(toastEl._t);
  toastEl._t = setTimeout(()=>toastEl.classList.remove('show'), 2400);
}

/* ─── Session state ─── */
let _me = null;

/* ─── API helpers ─── */

// ── CSRF Token (api-client.js ile paylaşılan cache) ──────────────────
// ── API Wrapper — window.WbApi (wb-api-shim.js) üzerinden ──────────
async function apiGet(path, params)  { return window.WbApi.get(path, params); }
async function apiPost(path, body)   { return window.WbApi.post(path, body); }
// ─────────────────────────────────────────────────────────────────────

/* ─── Date helpers ─── */
function uiToIso(v){ const m=/^(\d{2})\.(\d{2})\.(\d{4})$/.exec(String(v||'').trim()); return m?`${m[3]}-${m[2]}-${m[1]}`:''; }
function isoToUi(v){
  if(!v) return '';
  // MySQL DATE veya DATETIME formatını handle et: "YYYY-MM-DD" veya "YYYY-MM-DD HH:MM:SS"
  const s = String(v).trim().split(' ')[0]; // "2000-01-15 00:00:00" → "2000-01-15"
  const m=/^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s);
  return m ? `${pad(+m[3])}.${pad(+m[2])}.${m[1]}` : '';
}
function isoDate(d){ return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`; }

/* ─── DOM refs ─── */
const meName = $('#meName'), meHint = $('#meEmail');
const firstName=$('#firstName'), lastName=$('#lastName'), birthday=$('#birthday');
const phone=$('#phone');
const addrCity=$('#addrCity'), addrDistrict=$('#addrDistrict'), addrNeighborhood=$('#addrNeighborhood');
const cardPersonal=$('#cardPersonal'), btnPersonalEdit=$('#btnPersonalEdit');
const btnPersonalSave=$('#btnPersonalSave'), btnPersonalCancel=$('#btnPersonalCancel');
const cardAddress=$('#cardAddress'), btnAddrEdit=$('#btnAddrEdit');
const btnAddrSave=$('#btnAddrSave'), btnAddrCancel=$('#btnAddrCancel');
const emailInput=$('#emailInput'), emailStatus=$('#emailStatus'), emailHelpText=$('#emailHelpText');
const emailViewRow=$('#emailViewRow'), emailEditRow=$('#emailEditRow');
const btnEmailStart=$('#btnEmailStart'), btnEmailCancel=$('#btnEmailCancel');
const newEmailInput=$('#newEmail'), btnEmailSendVerify=$('#btnEmailSendVerify');

/* ─── Sidebar tab ─── */
const goto = key => {
  $$('.mitem').forEach(i=>{
    const a=i.dataset.goto===key;
    i.classList.toggle('active',a);
    a ? i.setAttribute('aria-current','page') : i.removeAttribute('aria-current');
  });
  $$('.panel').forEach(p=>p.classList.toggle('show', p.id===`page-${key}`));
  history.replaceState(null,'',`#${key}`);
  window.scrollTo({top:0,behavior:'smooth'});
};
$$('.mitem[data-goto]').forEach(btn=>btn.addEventListener('click',()=>{
  goto(btn.dataset.goto);
  if(btn.dataset.goto==='notifications') {
    // Bildirim panelini yükle
    setTimeout(() => window.wbUserNotif?.loadPanelData(), 50);
  }
}));
window.addEventListener('hashchange',()=>{
  const k=(location.hash||'#appointments').slice(1);
  if(k) goto(k === 'favorites' ? 'appointments' : k);
});

/* ─── Logout ─── */
$('#menuLogout')?.addEventListener('click', async ()=>{
  try { await apiPost('/api/user/logout.php',{}); } catch {}
  location.href = 'index.html';
});

/* ─── Section modes ─── */
const UI_STATE = { personalEditing:false, addrEditing:false };
function setSectionMode(section, mode){
  const editing = mode==='edit';
  if(section==='personal'){
    UI_STATE.personalEditing=editing;
    cardPersonal?.classList.toggle('is-editing',editing);
    [firstName,lastName,birthday].forEach(i=>{ if(i) i.disabled=!editing; });
    // Birthday: editing modda tıklanabilir görünüm
    if(birthday){
      birthday.style.cursor = editing ? 'pointer' : '';
      birthday.placeholder = editing ? '🗓 Tıklayın → tarih seçin' : 'gg.aa.yyyy';
    }
    if(btnPersonalEdit) btnPersonalEdit.style.display=editing?'none':'';
    if(btnPersonalSave) btnPersonalSave.style.display=editing?'':'none';
    if(btnPersonalCancel) btnPersonalCancel.style.display=editing?'':'none';
  } else if(section==='addr'){
    UI_STATE.addrEditing=editing;
    cardAddress?.classList.toggle('is-editing',editing);
    [addrCity,addrDistrict,addrNeighborhood].forEach(i=>{ if(i) i.disabled=!editing; });
    if(btnAddrEdit) btnAddrEdit.style.display=editing?'none':'';
    if(btnAddrSave) btnAddrSave.style.display=editing?'':'none';
    if(btnAddrCancel) btnAddrCancel.style.display=editing?'':'none';
  }
}

/* ─── DOB Picker ─── */
function openDOBModal(anchor, fromClick=false){
  const nowY=new Date().getFullYear();
  const ov=document.createElement('div');
  ov.className='modal-ov show'; ov.setAttribute('aria-hidden','false');
  const modal=document.createElement('div');
  modal.className='modal sm'; modal.setAttribute('role','dialog'); modal.setAttribute('aria-modal','true');
  modal.innerHTML=`
    <div class="hd"><div class="ttl">🎂 Doğum Tarihi Seç</div><button class="x" aria-label="Kapat">✕</button></div>
    <div class="ct"><div style="display:grid;gap:10px">
      <label class="label" for="dobRaw">Tarih seç</label>
      <input id="dobRaw" type="date" class="input" min="${nowY-100}-01-01" max="${nowY}-12-31" />
      <div style="display:flex;gap:10px;justify-content:flex-end">
        <button id="dobCancel" class="btn outline">Vazgeç</button>
        <button id="dobOk" class="btn">Kaydet</button>
      </div>
    </div></div>`;
  ov.appendChild(modal); document.body.appendChild(ov);
  const raw=modal.querySelector('#dobRaw');
  // Mevcut değeri dönüştürerek raw date input'a yaz
  const cur=/^(\d{2})\.(\d{2})\.(\d{4})$/.exec(String(anchor?.value||'').trim());
  if(cur) raw.value=`${cur[3]}-${cur[2]}-${cur[1]}`;
  // Bugünün tarihi default olarak göster (değer yoksa)
  else raw.value = new Date().toISOString().split('T')[0];
  const close=()=>{ try{document.activeElement?.blur();}catch{} ov.remove(); };
  modal.querySelector('.x')?.addEventListener('click',close);
  modal.querySelector('#dobCancel')?.addEventListener('click',close);
  ov.addEventListener('click',e=>{ if(e.target===ov) close(); });
  document.addEventListener('keydown',function esc(e){ if(e.key==='Escape'&&document.body.contains(ov)){ close(); document.removeEventListener('keydown',esc); } });
  modal.querySelector('#dobOk')?.addEventListener('click',()=>{
    const v=String(raw.value||'').trim();
    if(!v){ showToast('Geçerli bir tarih seçin',false); return; }
    const [yy,mm,dd]=v.split('-');
    anchor.value=`${pad(+dd)}.${pad(+mm)}.${yy}`;
    close();
  });
  raw.focus();
}
function attachDobPicker(){
  const inp=$('#birthday'); if(!inp) return;
  let _dobOpen = false;
  const open=e=>{
    if(inp.disabled) return;
    if(_dobOpen) return;
    e.preventDefault();
    _dobOpen = true;
    inp.blur();
    openDOBModal(inp, e.type==='click');
    // Modal kapandığında flag sıfırla
    setTimeout(()=>{ _dobOpen = false; }, 300);
  };
  inp.addEventListener('click',open);
  inp.setAttribute('aria-haspopup','dialog');
  inp.style.cursor = 'pointer';
}

/* ─── Türkiye combo ─── */
let trComboAttached=false;
async function ensureTRCombo(){
  if(trComboAttached) return;
  try{
    const { attachTRLocationCombo } = await import('./components/select-combo.js');
    await attachTRLocationCombo({ citySelect:addrCity, districtSelect:addrDistrict, neighborhoodSelect:addrNeighborhood });
    trComboAttached=true;
  }catch(e){ console.warn('select-combo yüklenemedi:',e); }
}
async function setSelectValue(el,val){
  if(!el||!val) return;
  for(let i=0;i<40;i++){
    if(Array.from(el.options).some(o=>String(o.value)===String(val))){ el.value=val; return; }
    await new Promise(r=>setTimeout(r,60));
  }
}

/* ─── Google bağlantısı ─── */
const gStatus=$('#googleStatus'), gConnect=$('#googleConnect'), gDisconnect=$('#googleDisconnect');
const GOOGLE_CLIENT_ID =
  document.querySelector('meta[name="google-signin-client_id"]')?.content?.trim()
  || window.GOOGLE_CLIENT_ID
  || '279602177241-o5qmpgshp4g13jlrunnkav6vdu4hiejv.apps.googleusercontent.com';
let _gsiProfilePromise = null;
let _googleLinkBusy = false;

function setGoogleUiState(){
  if(!gStatus || !gConnect) return;
  const hasEmail = !!String(_me?.email || '').trim();
  const isConnected = !!_me?.googleConnected;

  if(gDisconnect) gDisconnect.style.display='none';
  gConnect.style.display = '';

  if(isConnected){
    gStatus.textContent = 'Bağlı ve doğrulandı';
    gConnect.disabled = true;
    gConnect.textContent = 'Google hesabı bağlı';
    return;
  }

  if(!hasEmail){
    gStatus.textContent = 'Önce e-posta ekleyin';
    gConnect.disabled = true;
    gConnect.textContent = 'E-posta ekleyin';
    return;
  }

  gStatus.textContent = 'Bağlı değil';
  gConnect.disabled = _googleLinkBusy;
  gConnect.textContent = _googleLinkBusy ? 'Bağlanıyor…' : 'Google hesabını bağla';
}

function ensureGoogleScript(){
  if(window.google?.accounts?.id) return Promise.resolve(window.google);
  if(_gsiProfilePromise) return _gsiProfilePromise;

  _gsiProfilePromise = new Promise((resolve, reject) => {
    const existing = document.querySelector('script[data-google-gsi="1"]');
    if(existing){
      existing.addEventListener('load', () => resolve(window.google), { once:true });
      existing.addEventListener('error', () => reject(new Error('gsi_load_failed')), { once:true });
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
    _gsiProfilePromise = null;
    throw err;
  });

  return _gsiProfilePromise;
}

async function requestGoogleCredential(){
  const googleApi = await ensureGoogleScript();
  if(!googleApi?.accounts?.id) throw new Error('gsi_unavailable');

  return new Promise((resolve, reject) => {
    let settled = false;
    const overlay = document.createElement('div');
    overlay.className = 'modal-ov show';
    overlay.setAttribute('aria-hidden', 'false');
    overlay.innerHTML = `
      <div class="modal sm" role="dialog" aria-modal="true" aria-labelledby="googleLinkTitle">
        <div class="hd">
          <div class="ttl" id="googleLinkTitle">Google Hesabını Bağla</div>
          <button class="x" type="button" aria-label="Kapat">✕</button>
        </div>
        <div class="ct">
          <p class="muted" style="margin:0 0 14px">Devam etmek için Google hesabını seç.</p>
          <div id="googleLinkBtnHost" style="display:flex;justify-content:center;min-height:44px"></div>
          <div id="googleLinkMsg" class="form-msg" style="margin-top:12px;text-align:center"></div>
        </div>
      </div>`;

    const host = overlay.querySelector('#googleLinkBtnHost');
    const msg = overlay.querySelector('#googleLinkMsg');
    const close = (err) => {
      if(settled) return;
      settled = true;
      clearTimeout(timeout);
      overlay.remove();
      if(err) reject(err);
    };
    const succeed = (credential) => {
      if(settled) return;
      settled = true;
      clearTimeout(timeout);
      overlay.remove();
      resolve(credential);
    };
    const timeout = setTimeout(() => {
      close(new Error('gsi_timeout'));
    }, 120000);

    overlay.addEventListener('click', (e) => {
      if(e.target === overlay) close(new Error('gsi_cancelled'));
    });
    overlay.querySelector('.x')?.addEventListener('click', () => close(new Error('gsi_cancelled')));
    document.body.appendChild(overlay);

    googleApi.accounts.id.initialize({
      client_id: GOOGLE_CLIENT_ID,
      callback: (response) => {
        const credential = String(response?.credential || '').trim();
        if(!credential){
          close(new Error('missing_google_credential'));
          return;
        }
        succeed(credential);
      },
      auto_select: false,
      cancel_on_tap_outside: true,
    });

    try {
      googleApi.accounts.id.renderButton(host, {
        theme: 'outline',
        size: 'large',
        shape: 'pill',
        text: 'continue_with',
        width: 280,
        logo_alignment: 'left',
      });
    } catch (err) {
      msg.textContent = 'Google butonu yüklenemedi.';
      close(err instanceof Error ? err : new Error('gsi_render_failed'));
    }
  });
}

async function handleGoogleConnect(){
  if(_googleLinkBusy || _me?.googleConnected) return;
  if(!String(_me?.email || '').trim()){
    showToast('Önce hesabına e-posta eklemelisin.', false);
    return;
  }

  _googleLinkBusy = true;
  setGoogleUiState();

  try{
    const credential = await requestGoogleCredential();
    const res = await apiPost('/api/user/google-link.php', { credential });
    if(!res?.ok) throw new Error(res?.error || 'Google hesabı bağlanamadı');
    _me = { ...(_me || {}), googleConnected:true, emailVerified:true, emailOk:true };
    setBadge('ok', 'E-posta doğrulandı');
    showToast('Google hesabın bağlandı. Artık Google ile giriş yapabilirsin.');
  }catch(e){
    const msg = e?.message === 'gsi_timeout'
      ? 'Google seçimi zaman aşımına uğradı. Tekrar deneyin.'
      : e?.message === 'gsi_cancelled'
        ? 'Google hesabı seçimi iptal edildi.'
        : (e?.message || 'Google hesabı bağlanamadı');
    showToast(msg, false);
  }finally{
    _googleLinkBusy = false;
    setGoogleUiState();
  }
}

gConnect?.addEventListener('click', handleGoogleConnect);
if(gDisconnect) gDisconnect.style.display='none';

/* ─── Map helpers ─── */
function buildMapsLinks(loc={}, bizName='', addrText=''){
  const direct=loc.googleMapsUrl||loc.mapUrl||'';
  const hasLL=Number.isFinite(loc.lat)&&Number.isFinite(loc.lng);
  const full=addrText||[loc.street,loc.neighborhood,loc.district,loc.province||loc.city].filter(Boolean).join(', ');
  const q=hasLL?`${loc.lat},${loc.lng}`:((bizName?`${bizName}, `:'')+full);
  return {
    openHref: direct||`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`,
    embedSrc: `https://www.google.com/maps?hl=tr&q=${encodeURIComponent(q)}&z=15&output=embed`,
    directionsHref: `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(q)}`
  };
}

/* ─── Business cache ─── */
const BIZ_CACHE = new Map();
async function getBusinessData(bizId){
  if(!bizId) return null;
  if(BIZ_CACHE.has(bizId)) return BIZ_CACHE.get(bizId);
  try{
    const r=await apiGet(`/api/public/business.php?id=${encodeURIComponent(bizId)}`);
    const info=r.ok?r.data:null;
    BIZ_CACHE.set(bizId,info);
    return info;
  }catch{ BIZ_CACHE.set(bizId,null); return null; }
}

/* ─── Profil doldur ─── */
function setBadge(state='muted', text='—'){
  if(!emailStatus) return;
  emailStatus.className=`badge ${state}`;
  emailStatus.textContent=text;
}

async function hydrateProfileForm(u){
  _me=u||{};
  const fn=u?.firstName||'';
  const ln=u?.lastName||'';
  const display=(fn||ln)?`${fn} ${ln}`.trim():'Kullanıcı';
  if(meName) meName.textContent=display;
  if(meHint) meHint.textContent=humanPhone(u?.phone||'')||'—';
  if(firstName) firstName.value=fn;
  if(lastName)  lastName.value=ln;
  if(birthday)  birthday.value=u?.birthday?isoToUi(u.birthday):'';
  if(phone)     phone.value=u?.phone?humanPhone(u.phone):'';

  const email=u?.email||'';
  if(emailInput){ emailInput.value=email; emailInput.disabled=false; emailInput.readOnly=true; }
  if (email) {
    const emailVerified = !!(u?.emailOk ?? u?.emailVerified);
    setBadge(emailVerified ? 'ok' : 'warn', emailVerified ? 'E-posta doğrulandı' : 'E-posta doğrulanmadı');
  } else {
    setBadge('muted','—');
  }
  if(btnEmailStart) btnEmailStart.textContent=email?'E-posta değiştir':'E-posta ekle';
  emailEditRow?.classList.add('hidden');
  emailViewRow?.classList.remove('hidden');
  setGoogleUiState();

  await ensureTRCombo();
  if(u?.city){
    if(addrCity){ await setSelectValue(addrCity,u.city); addrCity.dispatchEvent(new Event('change')); }
    if(u.district && addrDistrict){ await new Promise(r=>setTimeout(r,80)); await setSelectValue(addrDistrict,u.district); addrDistrict.dispatchEvent(new Event('change')); }
    if(u.neighborhood && addrNeighborhood){ await new Promise(r=>setTimeout(r,80)); await setSelectValue(addrNeighborhood,u.neighborhood); }
  }
  setSectionMode('personal','view');
  setSectionMode('addr','view');
  try{ attachDobPicker(); }catch{}
}

/* ─── Kişisel bilgiler ─── */
btnPersonalEdit?.addEventListener('click',()=>setSectionMode('personal','edit'));
btnPersonalCancel?.addEventListener('click',()=>{
  if(firstName) firstName.value=_me?.firstName||'';
  if(lastName)  lastName.value=_me?.lastName||'';
  if(birthday)  birthday.value=_me?.birthday?isoToUi(_me.birthday):'';
  setSectionMode('personal','view');
});
btnPersonalSave?.addEventListener('click', async ()=>{
  const f=(firstName?.value||'').trim();
  const l=(lastName?.value||'').trim();
  const dobRaw=(birthday?.value||'').trim();
  if(!f&&!l){ showToast('Ad veya soyad girin',false); return; }
  if(dobRaw&&!/^\d{2}\.\d{2}\.\d{4}$/.test(dobRaw)){ showToast('Doğum tarihi gg.aa.yyyy formatında olmalı',false); return; }
  const dobIso=dobRaw?uiToIso(dobRaw):'';
  if(btnPersonalSave){ btnPersonalSave.disabled=true; btnPersonalSave.textContent='Kaydediliyor…'; }
  try{
    await apiPost('/api/user/profile/update.php',{ action:'update_name', firstName:f, lastName:l, birthday:dobIso||null });
    Object.assign(_me,{ firstName:f, lastName:l, birthday:dobIso||null });
    if(meName) meName.textContent=`${f} ${l}`.trim()||'Kullanıcı';
    setSectionMode('personal','view');
    showToast('Kişisel bilgiler kaydedildi ✓');
  }catch(e){ showToast(e.message||'Kaydedilemedi',false); }
  finally{ if(btnPersonalSave){ btnPersonalSave.disabled=false; btnPersonalSave.textContent='Kaydet'; } }
});

/* ─── Adres ─── */
btnAddrEdit?.addEventListener('click', async ()=>{ await ensureTRCombo(); setSectionMode('addr','edit'); });
btnAddrCancel?.addEventListener('click', async ()=>{
  await ensureTRCombo();
  if(addrCity){ await setSelectValue(addrCity,_me?.city||''); addrCity.dispatchEvent(new Event('change')); }
  if(_me?.district&&addrDistrict){ await new Promise(r=>setTimeout(r,80)); await setSelectValue(addrDistrict,_me.district); addrDistrict.dispatchEvent(new Event('change')); }
  if(_me?.neighborhood&&addrNeighborhood){ await new Promise(r=>setTimeout(r,80)); await setSelectValue(addrNeighborhood,_me.neighborhood); }
  setSectionMode('addr','view');
});
btnAddrSave?.addEventListener('click', async ()=>{
  const city=(addrCity?.value||'').trim();
  const district=(addrDistrict?.value||'').trim();
  const neighborhood=(addrNeighborhood?.value||'').trim();
  if(!city||!district){ showToast('İl ve ilçe seçin',false); return; }
  if(btnAddrSave){ btnAddrSave.disabled=true; btnAddrSave.textContent='Kaydediliyor…'; }
  try{
    await apiPost('/api/user/profile/update.php',{ action:'update_address', city, district, neighborhood });
    Object.assign(_me,{ city, district, neighborhood });
    setSectionMode('addr','view');
    showToast('Adres bilgileri kaydedildi ✓');
  }catch(e){ showToast(e.message||'Kaydedilemedi',false); }
  finally{ if(btnAddrSave){ btnAddrSave.disabled=false; btnAddrSave.textContent='Kaydet'; } }
});

/* ─── E-posta / Telefon / Şifre ─── */
function openProfileActionPage(path){
  const win = window.open(path, '_blank', 'noopener');
  if(!win) showToast('Tarayıcı yeni sekmeyi engelledi', false);
}

btnEmailStart?.addEventListener('click', ()=>openProfileActionPage('kullanici-email-guncelle.html'));
$('#btnPhoneChange')?.addEventListener('click', ()=>openProfileActionPage('kullanici-telefon-guncelle.html'));
$('#btnPwByPhone')?.addEventListener('click', ()=>openProfileActionPage('kullanici-sifre-degistir.html'));

// Eski inline alanlar artık kullanılmıyor
btnEmailCancel?.addEventListener('click', ()=>{});
btnEmailSendVerify?.addEventListener('click', ()=>{});

/* ════════════════════════════════════════════════
   RANDEVU SİSTEMİ
   ════════════════════════════════════════════════ */

/* ─── Randevu durumu yardımcıları ─── */
function trStatus(raw=''){
  const s=(raw||'').toLowerCase();
  if(s.includes('cancellation_requested')||s==='cancellation_requested') return { cls:'pending', txt:'İptal bekleniyor' };
  if(s.includes('cancel')) return { cls:'cancel', txt:'İptal edildi' };
  if(s.includes('reject')||s.includes('declin')||s.includes('deny')) return { cls:'err', txt:'Reddedildi' };
  if(s.includes('complete')||s.includes('done')||s.includes('finish')) return { cls:'ok', txt:'Tamamlandı' };
  if(s.includes('approve')||s.includes('confirm')||s.includes('accept')) return { cls:'ok', txt:'Onaylandı' };
  return { cls:'pending', txt:'Onay bekliyor' };
}
function normalizeStatusForUi(rec){
  const raw=String(rec.status||'').toLowerCase();
  const endMs=rec?.end?.getTime?.()||rec?.start?.getTime?.()||0;
  if(/pend|scheduled|created/.test(raw)&&endMs<Date.now()) return 'rejected';
  return raw||'pending';
}
function canCancel(rec){
  const ui=normalizeStatusForUi(rec);
  const now=Date.now(), startMs=rec?.start?.getTime?.()||0;
  if(!startMs||now>=startMs) return false;
  if(/reject|declin|deny|cancel|complete|done|finish|cancellation_requested/i.test(ui)) return false;
  return true;
}
function fmtWhen(dStart,dEnd){
  const dow=DOW[dStart.getDay()];
  const str=`${dow} • ${pad(dStart.getDate())} ${MON[dStart.getMonth()]} ${dStart.getFullYear()} — ${pad(dStart.getHours())}:${pad(dStart.getMinutes())}`;
  const end=dEnd?` – ${pad(dEnd.getHours())}:${pad(dEnd.getMinutes())}`:'' ;
  return str+end;
}

function apptCard(a, uiStatus){
  const d=a.start instanceof Date?a.start:new Date(a.start);
  const st=trStatus(uiStatus??a.status);
  return `
    <article class="appt clickable" role="button" tabindex="0"
             data-id="${escapeHtml(a.id)}" data-biz="${escapeHtml(a.businessId||'')}"
             aria-label="Randevu detayı için aç">
      <div class="left">
        <span class="tag ${st.cls}">${st.txt}</span>
        <div class="title">${escapeHtml(a.serviceTitle||'Hizmet')}</div>
        <div class="biz">
          ${a.logo?`<img src="${escapeHtml(a.logo)}" alt="">`:'<i class="fa-regular fa-building"></i>'}
          <span>${escapeHtml(a.businessName||'İşletme')}</span>
        </div>
        <div class="appt-actions">
          <button class="book-again" type="button"
                  data-repeat="${escapeHtml(a.businessId||'')}"
                  data-bname="${escapeHtml(a.businessName||'')}">Tekrar randevu al</button>
          ${a.canReview?`<button class="btn-review-appt" type="button"
                  data-appt-id="${escapeHtml(a.id||'')}"
                  data-biz-id="${escapeHtml(a.businessId||'')}"
                  data-biz-name="${escapeHtml(a.businessName||'İşletme')}"
                  data-service="${escapeHtml(a.serviceTitle||'')}"
                  data-date="${escapeHtml(a.startAt||'')}">
            <i class="fas fa-star" aria-hidden="true"></i> Değerlendir
          </button>`:''}
        </div>
      </div>
      <div class="datebox">
        <div class="day">${d.getDate()}</div>
        <div class="mon">${MON[d.getMonth()]}</div>
        <div class="time">${pad(d.getHours())}:${pad(d.getMinutes())}</div>
      </div>
    </article>`;
}

/* ─── Randevu detay modal ─── */
const apptOv=$('#apptOv'), apptClose=$('#apptClose');
const apptMap=$('#apptMap'), apptGmFrame=$('#apptGmFrame'), apptMapOpen=$('#apptMapOpen'), apptDirectionsOpen=$('#apptDirectionsOpen');
const apptMapLogo=$('#apptMapLogo'), apptBizName=$('#apptBizName'), apptAddrSub=$('#apptAddrSub');
const apptWhen=$('#apptWhen'), apptServicesWrap=$('#apptServicesWrap'), apptStatusBadge=$('#apptStatusBadge');
const apptBizBtn=$('#apptBizBtn'), apptBookAgain=$('#apptBookAgain'), apptCancel=$('#apptCancel');
let currentAppt=null;

function openApptModal(){ apptOv?.classList.add('show'); apptOv?.setAttribute('aria-hidden','false'); }
function closeApptModal(){ try{document.activeElement?.blur();}catch{} apptOv?.classList.remove('show'); apptOv?.setAttribute('aria-hidden','true'); }
apptClose?.addEventListener('click',closeApptModal);
apptOv?.addEventListener('click',e=>{ if(e.target===apptOv) closeApptModal(); });
document.addEventListener('keydown',e=>{ if(e.key==='Escape'&&apptOv?.classList.contains('show')) closeApptModal(); });

function setStatusBadge(raw='pending'){
  if(!apptStatusBadge) return;
  const st=trStatus(raw);
  apptStatusBadge.textContent=st.txt;
  apptStatusBadge.className=`status-badge ${st.cls}`;
}
function renderServicesChips(rec){
  if(!apptServicesWrap) return;
  const list=Array.isArray(rec.services)&&rec.services.length?rec.services:[{name:rec.serviceTitle||'Hizmet'}];
  apptServicesWrap.innerHTML=list.map(s=>{
    const dur=s.duration||s.durationMin;
    const price=Number.isFinite(Number(s.price))?` • ₺${Number(s.price).toLocaleString('tr-TR')}`:'' ;
    return `<span class="chip">${escapeHtml(s.name||'Hizmet')}${dur?` • ${dur}dk`:''}${price}</span>`;
  }).join('');
}

function normalizeBizVisual(rec={}, biz=null){
  return (
    rec.logo ||
    rec.coverUrl ||
    biz?.coverUrl ||
    biz?.logoUrl ||
    biz?.images?.cover_opt?.[0] ||
    biz?.images?.cover?.[0] ||
    biz?.images?.salon_opt?.[0] ||
    biz?.images?.salon?.[0] ||
    'img/icon-192.png'
  );
}

function normalizeBizLocation(rec={}, biz=null){
  if(rec.address && typeof rec.address === 'object') return rec.address;
  if(biz?.loc && typeof biz.loc === 'object'){
    return {
      city: biz.loc.city || biz.loc.province || '',
      district: biz.loc.district || '',
      neighborhood: biz.loc.neighborhood || '',
      street: biz.loc.addressLine || biz.loc.street || '',
      province: biz.loc.province || biz.loc.city || '',
      googleMapsUrl: biz.loc.mapUrl || '',
      mapUrl: biz.loc.mapUrl || ''
    };
  }
  return biz && typeof biz === 'object' ? biz : {};
}

async function openApptDetail(rec){
  currentAppt=rec;
  const biz=await getBusinessData(rec.businessId);
  if(biz){
    rec.businessName=rec.businessName||biz.name;
    rec.logo=normalizeBizVisual(rec,biz);
    rec.address=normalizeBizLocation(rec,biz);
  }
  if(apptBizName) apptBizName.textContent=rec.businessName||'İşletme';
  if(apptWhen) apptWhen.textContent=fmtWhen(rec.start,rec.end);
  setStatusBadge(normalizeStatusForUi(rec));
  renderServicesChips(rec);
  if(apptMapLogo){ apptMapLogo.src=normalizeBizVisual(rec,biz); apptMapLogo.alt=rec.businessName||''; }
  const loc=rec.address||{};
  const addrText=[loc.street,loc.neighborhood,loc.district,loc.province||loc.city].filter(Boolean).join(', ');
  if(apptAddrSub) apptAddrSub.textContent=addrText||'—';
  const { openHref, embedSrc, directionsHref }=buildMapsLinks(loc,rec.businessName,addrText);
  if(apptGmFrame){ apptGmFrame.src=embedSrc; apptGmFrame.style.pointerEvents='none'; }
  if(apptMapOpen) apptMapOpen.href=openHref;
  if(apptDirectionsOpen) apptDirectionsOpen.href=directionsHref || openHref;
  if(apptMap){
    apptMap.setAttribute('role','button'); apptMap.setAttribute('tabindex','0');
    apptMap.onclick=(e)=>{
      if(e.target?.closest?.('a,button')) return;
      window.open(openHref,'_blank','noopener');
    };
    apptMap.onkeydown=e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); window.open(openHref,'_blank','noopener'); } };
  }
  const profHref=rec.businessId?`profile.html?id=${encodeURIComponent(rec.businessId)}`:`profile.html?n=${encodeURIComponent(rec.businessName||'İşletme')}`;
  if(apptBizBtn) apptBizBtn.href=profHref;
  if(apptBookAgain) apptBookAgain.onclick=()=>{ location.href=profHref+'#book'; };
  if(apptCancel){
    apptCancel.dataset.rid=rec.id;
    const visible=canCancel(rec);
    apptCancel.style.display=visible?'':'none';
    apptCancel.disabled=!visible;
  }
  openApptModal();
}

/* ─── İptal ─── */
async function cancelCurrentAppt(){
  if(!currentAppt||!canCancel(currentAppt)){ showToast('Bu randevu iptal edilemez.',false); return; }
  if(!confirm('Randevuyu iptal etmek istiyor musunuz?')) return;
  const rid=apptCancel?.dataset.rid||currentAppt?.id;
  if(!rid){ showToast('Randevu bilgisi bulunamadı',false); return; }
  if(apptCancel){ apptCancel.disabled=true; apptCancel.textContent='Gönderiliyor…'; }
  try{
    const res = await apiPost('/api/user/appointments/cancel.php',{ id: String(rid) });
    if(!res?.ok){
      showToast(res?.error||'İptal talebi gönderilemedi.', false);
      if(apptCancel){ apptCancel.disabled=false; apptCancel.textContent='Randevuyu iptal et'; }
      return;
    }
    const newStatus = res?.data?.status||res?.status||'cancellation_requested';
    showToast(res?.message||res?.data?.message||'İptal talebiniz iletildi.');
    setStatusBadge(newStatus);
    if(apptCancel){ apptCancel.style.display='none'; apptCancel.disabled=true; }
    if(currentAppt) currentAppt.status = newStatus;
    const card=document.querySelector(`.appt.clickable[data-id="${rid}"]`);
    if(card){ const tag=card.querySelector('.tag'); if(tag){ tag.textContent='İptal bekleniyor'; tag.className='tag pending'; } }
    let pollCount=0;
    const statusPoller=setInterval(async ()=>{
      pollCount++;
      try{
        const statusRes = await apiGet(`/api/appointments/cancellation-status.php?id=${rid}`);
        if(statusRes?.status==='cancelled'){
          clearInterval(statusPoller);
          showToast('Randevunuz başarıyla iptal edilmiştir.');
          setStatusBadge('cancelled');
          if(currentAppt) currentAppt.status='cancelled';
          const c=document.querySelector(`.appt.clickable[data-id="${rid}"]`);
          if(c){ const t=c.querySelector('.tag'); if(t){ t.textContent='İptal edildi'; t.className='tag cancel'; } }
        }
      }catch{}
      if(pollCount>=6) clearInterval(statusPoller);
    }, 5000);
  }catch(e){
    showToast(e.message||'Randevu iptal edilemedi',false);
    if(apptCancel){ apptCancel.disabled=false; apptCancel.textContent='Randevuyu iptal et'; }
  }
}
apptCancel?.addEventListener('click', cancelCurrentAppt);

/* ════════════════════════════════════════════════
   YENİ: RANDEVU YÜKLEYİCİ + FİLTRE + SAYFALAMA
   ════════════════════════════════════════════════ */

let _allRows = [];          // Tüm randevular (filtrelenmemiş)
let _filteredRows = [];     // Filtre uygulanmış
let _currentFilter = 'all';
let _currentSearch = '';
let _currentDate = '';
const PAGE_SIZE = 10;
let _currentPage = 1;

// DOM refs (yeni)
const listUpcoming    = $('#listUpcoming');
const upcomingLoading = $('#upcomingLoading');
const upcomingEmpty   = $('#upcomingEmpty');
const listAll         = $('#listAll');
const allApptsEmpty   = $('#allApptsEmpty');
const allApptCount    = $('#allApptCount');
const apptSearch      = $('#apptSearch');
const apptDateFilter  = $('#apptDateFilter');
const apptPagination  = $('#apptPagination');
const btnSeeAllAppts  = $('#btnSeeAllAppts');

/* "Tümünü Gör" → sayfayı allApptsCard'a scroll */
btnSeeAllAppts?.addEventListener('click', ()=>{
  const card = $('#allApptsCard');
  if(card) card.scrollIntoView({ behavior:'smooth', block:'start' });
});

/* Filtre chips */
$$('.fchip').forEach(chip=>{
  chip.addEventListener('click', ()=>{
    $$('.fchip').forEach(c=>c.classList.remove('active'));
    chip.classList.add('active');
    _currentFilter = chip.dataset.filter || 'all';
    _currentPage = 1;
    applyFilters();
  });
});

/* Arama */
let _searchDebounce;
apptSearch?.addEventListener('input', ()=>{
  clearTimeout(_searchDebounce);
  _searchDebounce = setTimeout(()=>{
    _currentSearch = (apptSearch.value||'').trim().toLowerCase();
    _currentPage = 1;
    applyFilters();
  }, 280);
});

/* Tarih filtresi */
apptDateFilter?.addEventListener('change', ()=>{
  _currentDate = apptDateFilter.value || '';
  _currentPage = 1;
  applyFilters();
});

function matchesFilter(r){
  const uiStatus = normalizeStatusForUi(r);
  const nowMs = Date.now();
  const startMs = r.start?.getTime() || 0;
  const endMs = r.end?.getTime() || startMs;

  // Durum filtresi
  if(_currentFilter === 'upcoming')  return startMs > nowMs && !/cancel|reject|declin|deny|complete|done|finish/i.test(uiStatus);
  if(_currentFilter === 'past')      return endMs < nowMs || /cancel|reject|declin|deny|complete|done|finish/i.test(uiStatus);
  if(_currentFilter === 'approved')  return /approve|confirm|accept|ok/.test(uiStatus);
  if(_currentFilter === 'pending')   return /pend|scheduled|created|cancellation_requested/.test(uiStatus) && startMs > nowMs;
  if(_currentFilter === 'cancelled') return /cancel|reject|declin|deny/.test(uiStatus);
  return true; // all
}

function matchesSearch(r){
  if(!_currentSearch) return true;
  const bname = (r.businessName||'').toLowerCase();
  return bname.includes(_currentSearch);
}

function matchesDate(r){
  if(!_currentDate) return true;
  const d = r.start;
  if(!d) return false;
  return isoDate(d) === _currentDate;
}

function applyFilters(){
  _filteredRows = _allRows.filter(r => matchesFilter(r) && matchesSearch(r) && matchesDate(r));
  renderAllPage(_currentPage);
  renderPagination();
  if(allApptCount){
    allApptCount.textContent = `${_filteredRows.length} randevu`;
    allApptCount.classList.toggle('hidden', _filteredRows.length === 0);
  }
}

function renderAllPage(page){
  if(!listAll) return;
  const start = (page-1)*PAGE_SIZE;
  const slice = _filteredRows.slice(start, start+PAGE_SIZE);

  if(slice.length === 0){
    listAll.innerHTML = '';
    allApptsEmpty?.classList.remove('hidden');
    return;
  }
  allApptsEmpty?.classList.add('hidden');
  listAll.innerHTML = slice.map(r => apptCard(r, normalizeStatusForUi(r))).join('');

  // Event binding
  listAll.querySelectorAll('.book-again').forEach(btn=>{
    btn.addEventListener('click',ev=>{
      ev.stopPropagation();
      const bid=btn.getAttribute('data-repeat')||'';
      const nm=btn.getAttribute('data-bname')||'İşletme';
      location.href=bid?`profile.html?id=${encodeURIComponent(bid)}#book`:`profile.html?n=${encodeURIComponent(nm)}#book`;
    });
  });
  listAll.querySelectorAll('.appt.clickable').forEach(card=>{
    card.addEventListener('click',()=>{
      const id=card.getAttribute('data-id');
      const rec=_allRows.find(x=>String(x.id)===String(id));
      if(rec) openApptDetail(rec);
    });
    card.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); card.click(); } });
  });
}

function renderPagination(){
  if(!apptPagination) return;
  const total = Math.ceil(_filteredRows.length / PAGE_SIZE);
  if(total <= 1){ apptPagination.classList.add('hidden'); apptPagination.innerHTML=''; return; }
  apptPagination.classList.remove('hidden');
  let html = `<button class="pag-btn" data-page="${_currentPage-1}" ${_currentPage===1?'disabled':''}>‹</button>`;
  for(let i=1;i<=total;i++){
    if(total > 7 && i > 2 && i < total-1 && Math.abs(i-_currentPage) > 1){
      if(i===3||i===total-2) html += `<span class="pag-btn" style="border:none;cursor:default">…</span>`;
      continue;
    }
    html += `<button class="pag-btn ${i===_currentPage?'active':''}" data-page="${i}">${i}</button>`;
  }
  html += `<button class="pag-btn" data-page="${_currentPage+1}" ${_currentPage===total?'disabled':''}>›</button>`;
  apptPagination.innerHTML = html;
  apptPagination.querySelectorAll('.pag-btn[data-page]').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const p = +btn.dataset.page;
      if(!p||p===_currentPage) return;
      _currentPage = p;
      renderAllPage(_currentPage);
      renderPagination();
      $('#allApptsCard')?.scrollIntoView({ behavior:'smooth', block:'start' });
    });
  });
}

/* ─── Yaklaşan randevuları render ─── */
function renderUpcoming(){
  if(!listUpcoming) return;
  const nowMs = Date.now();
  const upcoming = _allRows
    .filter(r => {
      const st = normalizeStatusForUi(r);
      return (r.start?.getTime()||0) > nowMs && !/cancel|reject|declin|deny|complete|done|finish/i.test(st);
    })
    .sort((a,b)=>(a.start?.getTime()||0)-(b.start?.getTime()||0))
    .slice(0, 3); // İlk 3 yaklaşan

  // Loader gizle
  upcomingLoading?.classList.add('hidden');

  if(upcoming.length === 0){
    listUpcoming.classList.add('hidden');
    upcomingEmpty?.classList.remove('hidden');
    return;
  }

  upcomingEmpty?.classList.add('hidden');
  listUpcoming.innerHTML = upcoming.map(r => apptCard(r, normalizeStatusForUi(r))).join('');
  listUpcoming.classList.remove('hidden');

  // Remaining count hint
  const totalUpcoming = _allRows.filter(r => {
    const st = normalizeStatusForUi(r);
    return (r.start?.getTime()||0) > nowMs && !/cancel|reject|declin|deny|complete|done|finish/i.test(st);
  }).length;
  if(totalUpcoming > 3 && btnSeeAllAppts){
    btnSeeAllAppts.innerHTML = `Tümünü Gör <span style="background:var(--brand);color:#fff;border-radius:999px;padding:1px 7px;font-size:11px;margin-left:2px">${totalUpcoming}</span>`;
  }

  // Bind events
  listUpcoming.querySelectorAll('.book-again').forEach(btn=>{
    btn.addEventListener('click',ev=>{
      ev.stopPropagation();
      const bid=btn.getAttribute('data-repeat')||'';
      const nm=btn.getAttribute('data-bname')||'İşletme';
      location.href=bid?`profile.html?id=${encodeURIComponent(bid)}#book`:`profile.html?n=${encodeURIComponent(nm)}#book`;
    });
  });
  listUpcoming.querySelectorAll('.appt.clickable').forEach(card=>{
    card.addEventListener('click',()=>{
      const id=card.getAttribute('data-id');
      const rec=_allRows.find(x=>String(x.id)===String(id));
      if(rec) openApptDetail(rec);
    });
    card.addEventListener('keydown',e=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); card.click(); } });
  });
}

/* ─── Ana randevu yükleyici ─── */
async function loadAppointments(){
  // Loader göster
  if(upcomingLoading) upcomingLoading.classList.remove('hidden');
  if(listUpcoming) listUpcoming.classList.add('hidden');
  if(upcomingEmpty) upcomingEmpty.classList.add('hidden');
  if(listAll) listAll.innerHTML = '';
  if(allApptsEmpty) allApptsEmpty.classList.add('hidden');

  try{
    const res = await apiGet('/api/user/appointments.php');
    const rows = (res.ok && Array.isArray(res.data)) ? res.data.map(r=>({
      ...r,
      start: r.startAt ? new Date(r.startAt) : null,
      end:   r.endAt   ? new Date(r.endAt)   : null,
      serviceTitle: Array.isArray(r.services)&&r.services.length ? r.services.map(s=>s.name||s).join(', ') : (r.serviceTitle||'Hizmet')
    })).filter(r=>r.start) : [];

    rows.sort((a,b)=>(b.start?.getTime()||0)-(a.start?.getTime()||0));

    // Can-review kontrolü
    let _eligibleApptIds = new Set();
    try {
      const bizIds = [...new Set(rows.map(r => r.businessId).filter(Boolean))];
      for (const bid of bizIds) {
        const cr = await apiGet(`/api/reviews/can-review.php?business_id=${bid}`);
        if (cr.ok) (cr.data?.eligible || []).forEach(e => _eligibleApptIds.add(e.appointment_id));
      }
    } catch {}
    rows.forEach(r => { r.canReview = _eligibleApptIds.has(r.id) || _eligibleApptIds.has(String(r.id)); });

    _allRows = rows;
    renderUpcoming();
    applyFilters();

  }catch(e){
    console.warn('[loadAppointments]',e);
    if(upcomingLoading) upcomingLoading.classList.add('hidden');
    if(upcomingEmpty) upcomingEmpty.classList.remove('hidden');
  }
}

/* ─── Status Polling ─── */
let _pollTimer = null;
let _knownStatuses = {};

async function pollAppointmentStatuses() {
  try {
    const res = await apiGet('/api/user/appointments.php');
    if (!res.ok || !Array.isArray(res.data)) return;
    let changed = false;
    res.data.forEach(r => {
      const prev = _knownStatuses[r.id];
      if (prev !== undefined && prev !== r.status) changed = true;
      _knownStatuses[r.id] = r.status;
    });
    if (changed) { await loadAppointments(); showToast('Randevu durumunuz güncellendi.', true); }
  } catch {}
}

function startStatusPolling() {
  if (_pollTimer) clearInterval(_pollTimer);
  _pollTimer = setInterval(pollAppointmentStatuses, 10000);
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { clearInterval(_pollTimer); }
  else { pollAppointmentStatuses(); startStatusPolling(); }
});

/* ════════════════════════════════════════════════
   YORUM YAZMA
   ════════════════════════════════════════════════ */
document.addEventListener('click', async e => {
  const btn = e.target.closest('.btn-review-appt');
  if (!btn) return;
  e.stopPropagation();
  const apptId  = btn.dataset.apptId;
  const bizId   = btn.dataset.bizId;
  const bizName = btn.dataset.bizName || 'İşletme';
  const service = btn.dataset.service || '';
  const date    = btn.dataset.date    || '';

  let modal = document.getElementById('upReviewModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'upReviewModal';
    modal.className = 'up-rev-overlay';
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-labelledby', 'upRevTitle');
    modal.innerHTML = `
      <div class="up-rev-modal">
        <div class="up-rev-hd">
          <h3 id="upRevTitle" class="up-rev-title">Yorum Yaz</h3>
          <button class="up-rev-close" id="upRevClose" type="button" aria-label="Kapat">✕</button>
        </div>
        <div class="up-rev-body">
          <div class="up-rev-biz" id="upRevBiz"></div>
          <div class="up-rev-svc" id="upRevSvc"></div>
          <div class="rw-stars-label">Puanınız</div>
          <div class="rw-stars-pick" id="upRevStars" role="group" aria-label="Puan seç">
            ${[1,2,3,4,5].map(v => `<button class="rw-star" data-val="${v}" type="button" aria-label="${v} yıldız"><i class="fa-regular fa-star"></i></button>`).join('')}
          </div>
          <div class="rw-star-label" id="upRevStarLabel">Puan seçin</div>
          <textarea id="upRevComment" class="rw-textarea" placeholder="Deneyiminizi paylaşın… (isteğe bağlı)" maxlength="1000" rows="4"></textarea>
          <div class="rw-char-count"><span id="upRevCharCount">0</span>/1000</div>
          <div class="rw-error" id="upRevError" style="display:none"></div>
        </div>
        <div class="up-rev-footer">
          <button class="up-rev-cancel" id="upRevCancel" type="button">Vazgeç</button>
          <button class="btn-brand" id="upRevSubmit" type="button" disabled>Gönder</button>
        </div>
      </div>`;
    document.body.appendChild(modal);

    modal.querySelector('#upRevClose').addEventListener('click',  () => modal.classList.remove('show'));
    modal.querySelector('#upRevCancel').addEventListener('click', () => modal.classList.remove('show'));
    modal.addEventListener('click', e => { if (e.target === modal) modal.classList.remove('show'); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') modal.classList.remove('show'); });

    let _upRating = 0;
    const paintUpStars = val => {
      modal.querySelectorAll('#upRevStars .rw-star').forEach(b => {
        const v = +b.dataset.val;
        b.querySelector('i').className = v <= val ? 'fas fa-star' : 'fa-regular fa-star';
        b.classList.toggle('rw-star--active', v <= val);
      });
      const labels = ['','Berbat','Kötü','İdare eder','İyi','Mükemmel!'];
      modal.querySelector('#upRevStarLabel').textContent = val ? labels[val] : 'Puan seçin';
      modal.querySelector('#upRevSubmit').disabled = val < 1;
    };
    modal.querySelectorAll('#upRevStars .rw-star').forEach(b => {
      b.addEventListener('mouseenter', () => paintUpStars(+b.dataset.val));
      b.addEventListener('mouseleave', () => paintUpStars(_upRating));
      b.addEventListener('click', () => { _upRating = +b.dataset.val; paintUpStars(_upRating); });
    });
    modal.querySelector('#upRevComment').addEventListener('input', function() {
      modal.querySelector('#upRevCharCount').textContent = this.value.length;
    });
    modal.querySelector('#upRevSubmit').addEventListener('click', async () => {
      if (_upRating < 1) return;
      const submitBtn = modal.querySelector('#upRevSubmit');
      const errorEl   = modal.querySelector('#upRevError');
      const comment   = modal.querySelector('#upRevComment').value.trim();
      const curApptId = +modal.dataset.apptId;
      submitBtn.disabled = true; submitBtn.textContent = 'Gönderiliyor…';
      errorEl.style.display = 'none';
      try {
        const res = await window.WbApi.post('/api/reviews/submit.php', { appointment_id: curApptId, rating: _upRating, comment });
        const json = res;
        if (!json?.ok) throw new Error(json?.message || json?.error || 'Hata oluştu');
        modal.classList.remove('show');
        showToast('Yorumunuz için teşekkürler! 🌟', true);
        document.querySelector(`.btn-review-appt[data-appt-id="${curApptId}"]`)?.remove();
      } catch (err) {
        errorEl.textContent = err.message; errorEl.style.display = 'block';
        submitBtn.disabled = false; submitBtn.textContent = 'Gönder';
      }
    });
    modal._paintStars = (val) => {
      modal._upRating = val;
      modal.querySelectorAll('#upRevStars .rw-star').forEach(b => {
        const v = +b.dataset.val;
        b.querySelector('i').className = v <= val ? 'fas fa-star' : 'fa-regular fa-star';
        b.classList.toggle('rw-star--active', v <= val);
      });
      const labels = ['','Berbat','Kötü','İdare eder','İyi','Mükemmel!'];
      modal.querySelector('#upRevStarLabel').textContent = val ? labels[val] : 'Puan seçin';
      modal.querySelector('#upRevSubmit').disabled = val < 1;
    };
  }

  modal.dataset.apptId = apptId;
  modal.querySelector('#upRevBiz').textContent = bizName;
  if (date) {
    const d = new Date(date);
    const label = isNaN(d) ? date : d.toLocaleDateString('tr-TR', { day:'2-digit', month:'long', year:'numeric' });
    modal.querySelector('#upRevSvc').textContent = `${service}${service && label ? ' • ' : ''}${label}`;
  } else {
    modal.querySelector('#upRevSvc').textContent = service;
  }
  modal.querySelector('#upRevComment').value = '';
  modal.querySelector('#upRevCharCount').textContent = '0';
  modal.querySelector('#upRevError').style.display = 'none';
  modal.querySelector('#upRevSubmit').textContent = 'Gönder';
  modal._paintStars?.(0);
  modal.classList.add('show');
});

/* ════════════════════════════════════════════════
   ANA INIT
   ════════════════════════════════════════════════ */
async function init(){
  try{
    const res=await apiGet('/api/user/me.php');
    if(!res.ok){ location.href='index.html'; return; }
    await hydrateProfileForm(res.data||{});
    await loadAppointments();
    try {
      const a = await apiGet('/api/user/appointments.php');
      if (a.ok && Array.isArray(a.data)) a.data.forEach(r => { _knownStatuses[r.id] = r.status; });
    } catch {}
    startStatusPolling();
    const initialTabRaw=(location.hash||'#appointments').slice(1);
    const initialTab = initialTabRaw === 'favorites' ? 'appointments' : initialTabRaw;
    goto(initialTab);
  }catch(e){
    console.error('[user-profile init]',e);
    location.href='index.html';
  }
}

init();

async function refreshProfileSnapshot(){
  try{
    const res = await apiGet('/api/user/me.php');
    if(res?.ok) await hydrateProfileForm(res.data || {});
  }catch{}
}

window.addEventListener('focus', ()=>{ refreshProfileSnapshot(); });
window.addEventListener('storage', (e)=>{
  if(e.key === 'wb_profile_refresh') refreshProfileSnapshot();
});
