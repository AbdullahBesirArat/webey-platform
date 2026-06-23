/**
 * auth.js â€” MÃ¼ÅŸteri (end-user) auth flow
 * â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
 * Email + ÅŸifre tabanlÄ± giriÅŸ, email doÄŸrulamalÄ± kayÄ±t.
 *
 * REFACTOR:
 *  - Yerel apiPost() kaldÄ±rÄ±ldÄ± â†’ merkezi api-client.js kullanÄ±lÄ±yor
 *  - initGoogleAuth() / handleGoogleResponse() kaldÄ±rÄ±ldÄ± â†’
 *    index.html inline script zaten aynÄ± iÅŸi yapÄ±yordu (Ã§akÄ±ÅŸma kaldÄ±rÄ±ldÄ±)
 *  - GOOGLE_CLIENT_ID sabiti kaldÄ±rÄ±ldÄ± (index.html'den yÃ¶netiliyor)
 *  - normPhone() export edildi â†’ user-profile.js artÄ±k bunu import edebilir
 *  - TÃ¼rkÃ§e karakter sorunlarÄ± dÃ¼zeltildi
 */

import { api } from './api-client.js';

if (typeof window !== 'undefined') {
    window.__authLoaded = true;
}

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

const PASS_MIN = window.AUTH_PASS_MIN || 8;
const API_USER = '/api/user';
const GOOGLE_CLIENT_ID =
    document.querySelector('meta[name="google-signin-client_id"]')?.content?.trim()
    || window.GOOGLE_CLIENT_ID
    || '279602177241-o5qmpgshp4g13jlrunnkav6vdu4hiejv.apps.googleusercontent.com';

let _googleResizeTimer = null;

const GOOGLE_BTN_HTML = {
    login: `
        <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true">
            <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
            <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
            <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
            <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
        </svg>
        Google ile Giriş Yap
    `,
    signup: `
        <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true">
            <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
            <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
            <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
            <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
        </svg>
        Google ile Devam Et
    `,
};

let _gsiReadyPromise = null;
let _googleTrigger = null;
let _googleSignupCredential = null;
const GOOGLE_SIGNUP_CRED_KEY = 'wb_google_signup_credential';

function rememberGoogleTrigger(btn) {
    if (!btn) return;
    const mode = btn.id === 'btnGoogleSignup' ? 'signup' : 'login';
    _googleTrigger = { id: btn.id, mode };
}

function setGoogleSignupCredential(value) {
    _googleSignupCredential = value || null;
    try {
        if (_googleSignupCredential) sessionStorage.setItem(GOOGLE_SIGNUP_CRED_KEY, _googleSignupCredential);
        else sessionStorage.removeItem(GOOGLE_SIGNUP_CRED_KEY);
    } catch {}
}

function getGoogleSignupCredential() {
    if (_googleSignupCredential) return _googleSignupCredential;
    try {
        _googleSignupCredential = sessionStorage.getItem(GOOGLE_SIGNUP_CRED_KEY) || null;
    } catch {}
    return _googleSignupCredential;
}

function setGoogleButtonsLoading(on, mode = 'login') {
    ['btnGoogleLogin', 'btnGoogleSignup'].forEach(id => {
        const btn = document.getElementById(id);
        if (!btn) return;
        btn.dataset.loading = on ? '1' : '0';
        btn.setAttribute('aria-busy', on ? 'true' : 'false');
        btn.style.pointerEvents = on ? 'none' : '';
        btn.style.opacity = on ? '.72' : '';
    });
    if (!on) _googleTrigger = { mode };
}

function ensureGoogleScript() {
    if (window.google?.accounts?.id) return Promise.resolve(window.google);
    if (_gsiReadyPromise) return _gsiReadyPromise;

    _gsiReadyPromise = new Promise((resolve, reject) => {
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
        _gsiReadyPromise = null;
        throw err;
    });

    return _gsiReadyPromise;
}

function renderGoogleButtonHost(host, mode) {
    if (!host || !window.google?.accounts?.id) return;
    const width = Math.max(250, Math.floor(host.getBoundingClientRect().width || host.parentElement?.getBoundingClientRect().width || 320));
    host.innerHTML = '';
    window.google.accounts.id.renderButton(host, {
        theme: 'outline',
        size: 'large',
        shape: 'pill',
        width,
        text: mode === 'signup' ? 'continue_with' : 'signin_with',
        logo_alignment: 'left',
        click_listener: () => {
            _googleTrigger = { id: host.id, mode };
            if (mode === 'signup') clrErr('#signupError');
            else clrErr('#loginError');
        },
    });
}

function mountGoogleButton(elementId, mode) {
    const node = document.getElementById(elementId);
    if (!node) return;

    let host = node;
    if (node.dataset.googleMounted !== '1') {
        host = document.createElement('div');
        host.id = elementId;
        host.className = node.className + ' auth-google-slot';
        host.style.width = '100%';
        host.style.display = 'block';
        host.dataset.googleMounted = '1';
        host.dataset.googleMode = mode;
        node.replaceWith(host);
    }

    renderGoogleButtonHost(host, mode);
}

function scheduleGoogleButtonsResize() {
    clearTimeout(_googleResizeTimer);
    _googleResizeTimer = setTimeout(() => {
        ['btnGoogleLogin', 'btnGoogleSignup'].forEach(id => {
            const host = document.getElementById(id);
            const mode = host?.dataset.googleMode;
            if (!host || host.dataset.googleMounted !== '1' || !mode) return;
            renderGoogleButtonHost(host, mode);
        });
    }, 120);
}

async function initGoogleAuth() {
    const hasGoogleBtns = document.getElementById('btnGoogleLogin') || document.getElementById('btnGoogleSignup');
    if (!hasGoogleBtns || initGoogleAuth._done) return;

    const googleApi = await ensureGoogleScript();
    if (!googleApi?.accounts?.id) throw new Error('gsi_unavailable');

    googleApi.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: handleGoogleResponse,
        auto_select: false,
        cancel_on_tap_outside: true,
    });
    mountGoogleButton('btnGoogleLogin', 'login');
    mountGoogleButton('btnGoogleSignup', 'signup');
    window.addEventListener('resize', scheduleGoogleButtonsResize, { passive: true });
    initGoogleAuth._done = true;
}

async function handleGoogleResponse(response) {
    const mode = _googleTrigger?.mode === 'signup' ? 'signup' : 'login';
    setGoogleButtonsLoading(true, mode);

    try {
        const credential = String(response?.credential || '').trim();
        if (!credential) throw new Error('Google dogrulamasi alinamadi');

        if (mode === 'signup') {
            await beginGoogleSignupFlow(credential);
        } else {
            const res = await api.post('/api/auth/google-login.php', { credential, role: 'user' });
            if (!res?.ok) {
                if ((res?.code || '') === 'signup_required') {
                    await beginGoogleSignupFlow(credential);
                    return;
                }
                throw new Error(res?.error || 'Google ile giris basarisiz');
            }

            setGoogleSignupCredential(null);
            closeM('authModal');
            showToast('Google hesabinla giris yapildi.');
            document.dispatchEvent(new Event('user:loggedin'));
            document.dispatchEvent(new Event('auth:userChanged'));
        }
    } catch (err) {
        const msg = err?.message || 'Google ile giris basarisiz';
        if (mode === 'signup') setErr('#signupError', msg);
        else setErr('#loginError', msg);
        showToast(msg, false);
    } finally {
        setGoogleButtonsLoading(false, mode);
    }
}

async function beginGoogleSignupFlow(credential) {
    const verify = await api.post('/api/auth/google-verify.php', { credential });
    const verifiedEmail = (verify?.data?.email || '').trim().toLowerCase();
    if (!verify?.ok || !verifiedEmail) throw new Error(verify?.error || 'Google hesabi dogrulanamadi');

    const chk = await api.post('/api/auth/check-email.php', { email: verifiedEmail });
    if (chk?.ok && chk?.data?.available === false) {
        const loginEmail = document.querySelector('#loginForm [name="email"]');
        if (loginEmail) loginEmail.value = verifiedEmail;
        switchTab('login');
        throw new Error('Bu e-posta zaten kayitli. Giris yapabilir veya Google ile giris kullanabilirsiniz.');
    }

    setGoogleSignupCredential(credential);
    _savedEmail = verifiedEmail;
    _emailVerified = true;
    saveDraft('pass');
    closeM('authModal');
    openM('passModal');
    document.querySelector('#passModal [name="password"]')?.focus();
    showToast('Google hesabin dogrulandi. Sifreni belirleyerek devam et.');
}

async function triggerGoogleLogin(btn) {
    rememberGoogleTrigger(btn);
    if (_googleTrigger?.mode === 'signup') clrErr('#signupError');
    else clrErr('#loginError');

    try {
        await initGoogleAuth();
        window.google.accounts.id.prompt();
    } catch {
        const msg = 'Google servisi yuklenemedi. Lutfen tekrar deneyin.';
        if (_googleTrigger?.mode === 'signup') setErr('#signupError', msg);
        else setErr('#loginError', msg);
        showToast(msg, false);
    }
}

/* â”€â”€ YardÄ±mcÄ±lar â”€â”€ */

export function normPhone(raw) {
    let p = (raw || '').replace(/\D/g, '');
    if (p.startsWith('90') && p.length === 12) p = p.slice(2);
    if (p.startsWith('0')) p = p.slice(1);
    return p;
}

function showToast(msg, ok = true) {
    const el = document.getElementById('toast');
    if (el) {
        el.textContent = msg;
        el.className = 'toast show ' + (ok ? 'success' : 'error');
        clearTimeout(el._wbt);
        el._wbt = setTimeout(() => el.className = 'toast', 2800);
        return;
    }
    const d = document.createElement('div');
    d.style.cssText = 'position:fixed;bottom:28px;left:50%;transform:translateX(-50%);'
        + 'padding:12px 22px;border-radius:12px;color:#fff;font-size:14px;z-index:99999;'
        + 'background:' + (ok ? '#111827' : '#dc2626') + ';font-family:Sora,sans-serif';
    d.textContent = msg;
    document.body.appendChild(d);
    setTimeout(() => d.remove(), 2800);
}

function setLoading(btn, on, lbl) {
    if (!btn) return;
    if (on) { btn._orig = btn.textContent; btn.disabled = true; btn.dataset.loading = '1'; if (lbl) btn.textContent = lbl; }
    else    { btn.disabled = false; btn.dataset.loading = ''; if (btn._orig !== undefined) btn.textContent = btn._orig; }
}

function setErr(sel, msg) { const el = $(sel); if (el) el.textContent = msg; }
function clrErr(sel)       { setErr(sel, ''); }

/* â”€â”€ Modal â”€â”€ */
function openM(id) {
    try { window.AppModals.openModal(id); return; } catch {}
    const m = document.getElementById(id);
    if (!m) return;
    m.removeAttribute('hidden');
    m.classList.add('active');
    m.setAttribute('aria-hidden', 'false');
    document.body.classList.add('no-scroll');
    setTimeout(() => m.querySelector('input:not([disabled]):not([tabindex="-1"])')?.focus(), 60);
}
function closeM(id) {
    try { window.AppModals.closeModal(id); return; } catch {}
    const m = document.getElementById(id);
    if (!m) return;
    m.classList.remove('active');
    m.setAttribute('aria-hidden', 'true');
    if (!$$('.modal-overlay.active').length) document.body.classList.remove('no-scroll');
}
function switchTab(key) {
    $$('.auth-tab').forEach(b => {
        const isThis = b.dataset.tab === key;
        b.classList.toggle('active', isThis);
        b.setAttribute('aria-selected', String(isThis));
    });
    document.getElementById('loginForm')?.classList.toggle('active',  key === 'login');
    document.getElementById('signupForm')?.classList.toggle('active', key === 'signup');
}

/* Şifre gücü */
function getStrength(p) {
    if (!p || p.length < 4) return 0;
    let s = 0;
    if (p.length >= 8)          s++;
    if (p.length >= 12)         s++;
    if (/[A-Z]/.test(p))        s++;
    if (/[0-9]/.test(p))        s++;
    if (/[^A-Za-z0-9]/.test(p)) s++;
    return s <= 1 ? 1 : s <= 3 ? 2 : 3;
}
function updateStrengthBar(val) {
    const bar   = document.getElementById('passStrBar');
    const label = document.getElementById('passStrLabel');
    const tips  = document.getElementById('passStrTips');
    const level = getStrength(val);
    if (bar) bar.className = 'pass-strength-bar ' + (['','weak','medium','strong'][level] || '');

    const LABELS = ['', 'Zayıf', 'Orta', 'Güçlü'];
    const TIPS = [
        '',
        // weak
        'Büyük harf veya rakam ekle',
        // medium
        'Özel karakter ekle (!@#) veya uzat',
        // strong
        'Güvenli şifre',
    ];
    if (label) { label.textContent = val.length >= 4 ? LABELS[level] : ''; label.className = 'pass-strength-label ' + (LABELS[level] ? ['','weak','medium','strong'][level] : ''); }
    if (tips)  { tips.textContent  = val.length >= 4 ? TIPS[level]  : ''; }
}
function initEyes(container) {
    $$(container + ' .toggle-eye').forEach(btn => {
        if (btn.dataset.wbEyeBound) return; // çift bağlamayı önle
        btn.dataset.wbEyeBound = '1';
        btn.addEventListener('click', (e) => {
            e.stopPropagation(); // index.js delegated handler'ı tetikleme
            const inp = btn.closest('.password-wrap')?.querySelector('input');
            if (!inp) return;
            const show = inp.type === 'password';
            inp.type = show ? 'text' : 'password';
            btn.innerHTML = show ? '<i class="fa-regular fa-eye-slash"></i>' : '<i class="fa-regular fa-eye"></i>';
        });
    });
}

let _phone = '', _pass = '', _savedEmail = '', _emailVerified = false;

function getBirthdayValue(nameForm = document.getElementById('nameForm')) {
    return (document.getElementById('birthdayInput')?.value || nameForm?.querySelector('[name="birthday"]')?.value || '').trim();
}

function collectSignupProfile(nameForm = document.getElementById('nameForm')) {
    const firstName = (nameForm?.querySelector('[name="firstName"]')?.value || '').trim();
    const lastName = (nameForm?.querySelector('[name="lastName"]')?.value || '').trim();
    const birthday = getBirthdayValue(nameForm);
    const rawPhone = (nameForm?.querySelector('[name="phone"]')?.value || '').trim();
    const phone = normPhone(rawPhone);
    return { firstName, lastName, birthday, rawPhone, phone };
}

function collectSignupAddress() {
    return {
        city: (document.getElementById('citySelect')?.value || '').trim(),
        district: (document.getElementById('districtSelect')?.value || '').trim(),
        neighborhood: (document.getElementById('neighborhoodSelect')?.value || '').trim(),
    };
}

function validateSignupCompletion() {
    const { firstName, lastName, birthday, phone } = collectSignupProfile();
    const { city, district, neighborhood } = collectSignupAddress();

    if (!_savedEmail || !_emailVerified) return 'E-posta doğrulaması tamamlanmalıdır';
    if (!_pass || _pass.length < PASS_MIN) return `Şifre en az ${PASS_MIN} karakter olmalıdır`;
    if (firstName.length < 2 || lastName.length < 2) return 'Ad ve soyad en az 2 karakter olmalidir';
    if (!toISOBirthday(birthday)) return 'Gecerli bir dogum tarihi secin';
    if (!city || !district || !neighborhood) return 'Konum bilgilerini eksiksiz secin';
    if (phone && (phone.length !== 10 || !phone.startsWith('5'))) return 'Telefon girilecekse 5xxxxxxxxx formatinda olmalidir';
    return '';
}

/* â”€â”€ KayÄ±t taslaÄŸÄ± (sessionStorage) â”€â”€ */
const DRAFT_KEY = 'wb_signup_draft';

function saveDraft(step) {
    try {
        sessionStorage.setItem(DRAFT_KEY, JSON.stringify({
            step,
            phone: _phone,
            email: _savedEmail,
            emailVerified: _emailVerified,
            ts: Date.now(),
        }));
    } catch {}
}
function loadDraft() {
    try {
        const d = JSON.parse(sessionStorage.getItem(DRAFT_KEY) || 'null');
        if (!d) return null;
        // 30 dakikadan eski taslaklarÄ± sil
        if (Date.now() - d.ts > 30 * 60 * 1000) { clearDraft(); return null; }
        return d;
    } catch { return null; }
}
function clearDraft() {
    try { sessionStorage.removeItem(DRAFT_KEY); } catch {}
}

/* KayÄ±t adÄ±mÄ±nÄ± devam ettir â€” window.AuthFlow.resumeSignup() */
function resumeSignup() {
    const draft = loadDraft();
    if (!draft) { openM('authModal'); switchTab('signup'); return; }
    _phone = draft.phone || '';
    _savedEmail = draft.email || '';
    _emailVerified = !!draft.emailVerified;
    switch (draft.step) {
        case 'pass':
            openM('passModal');
            document.querySelector('#passModal [name="password"]')?.focus();
            break;
        case 'name':
            openM('nameModal');
            initDOBPicker();
            break;
        case 'address':
            openM('nameModal'); // adrese gitmek iÃ§in isim modalÄ±ndan geÃ§
            initDOBPicker();
            break;
        default:
            openM('authModal');
            switchTab('signup');
    }
}
window.AuthFlow = { resumeSignup };

/* â”€â”€ OTP State â”€â”€ */
/* â”€â”€ Ana init â”€â”€ */
export function initAuth() {
    if (initAuth._done) return;
    initAuth._done = true;

    initEyes('#loginForm');
    initEyes('#passForm');

    $$('.auth-tab').forEach(btn =>
        btn.addEventListener('click', () => switchTab(btn.dataset.tab === 'signup' ? 'signup' : 'login'))
    );
    $$('.modal-overlay .modal-close').forEach(btn => {
        const modal = btn.closest('.modal-overlay');
        if (modal) btn.addEventListener('click', () => closeM(modal.id));
    });
    $$('.modal-overlay').forEach(overlay =>
        overlay.addEventListener('click', e => { if (e.target === overlay) closeM(overlay.id); })
    );
    document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        const open = $$('.modal-overlay.active');
        if (open.length) closeM(open[open.length - 1].id);
    });

    /* ADIM 1: e-posta â†’ e-posta OTP */
    const signupForm = document.getElementById('signupForm');
    signupForm?.addEventListener('submit', async e => {
        e.preventDefault();
        setGoogleSignupCredential(null);
        const rawEmail = (signupForm.querySelector('[name="email"]')?.value || '').trim().toLowerCase();
        if (!rawEmail) {
            setErr('#signupError', 'E-posta adresi zorunludur'); return;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)) {
            setErr('#signupError', 'Gecerli bir e-posta adresi girin'); return;
        }
        clrErr('#signupError');
        const btn = signupForm.querySelector('button[type=submit]');
        setLoading(btn, true, 'Kod gonderiliyor...');
        try {
            // E-posta kayÄ±tlÄ± mÄ± kontrol et
            try {
                const chk = await api.post('/api/auth/check-email.php', { email: rawEmail });
                if (chk.ok && chk.data?.available === false) {
                    switchTab('login');
                    const loginEmail = document.querySelector('#loginForm [name="email"]');
                    if (loginEmail) loginEmail.value = rawEmail;
                    setTimeout(() => {
                        setErr('#loginError', 'Bu e-posta zaten kayitli, giris yapin.');
                    }, 50);
                    showToast('Bu e-posta zaten kayitli. Giris yapin.', false);
                    return;
                }
            } catch {}

            await api.post('/api/auth/email-send-otp.php', { email: rawEmail });
            _savedEmail = rawEmail;
            _emailVerified = false;
            await _showEmailOtpModal(rawEmail, () => {
                _emailVerified = true;
                clrErr('#signupError');
                saveDraft('pass');
                closeM('authModal');
                openM('passModal');
                document.querySelector('#passModal [name="password"]')?.focus();
            });
        } finally { setLoading(btn, false); }
    });

    /* ADIM 2: şifre */
    const passForm = document.getElementById('passForm');
    if (passForm) {
        const nextBtn = document.getElementById('btnPassNext');
        function validatePass() {
            const p = passForm.querySelector('[name="password"]')?.value || '';
            const c = passForm.querySelector('[name="confirm"]')?.value  || '';
            updateStrengthBar(p);
            if (nextBtn) nextBtn.disabled = !(p.length >= PASS_MIN && (!c || p === c));
        }
        passForm.addEventListener('input', validatePass);
        validatePass();
        passForm.addEventListener('submit', e => {
            e.preventDefault();
            const p = passForm.querySelector('[name="password"]')?.value || '';
            const c = passForm.querySelector('[name="confirm"]')?.value  || '';
            if (p.length < PASS_MIN) { setErr('#passError', `Şifre en az ${PASS_MIN} karakter olmalı`); return; }
            if (c && p !== c)        { setErr('#passError', 'Şifreler eşleşmiyor'); return; }
            clrErr('#passError');
            _pass = p;
            saveDraft('name');
            closeM('passModal');
            openM('nameModal');
            initDOBPicker();
        });
        document.getElementById('btnBackPass')?.addEventListener('click', () => {
            closeM('passModal'); openM('authModal'); switchTab('signup');
        });
    }

    /* ADIM 3: kimlik */
    const nameForm = document.getElementById('nameForm');
    if (nameForm) {
        const nextBtn = document.getElementById('btnNameNext');

        function validateName() {
            const { firstName, lastName, birthday, phone } = collectSignupProfile(nameForm);
            const phoneOk = !phone || (phone.length === 10 && phone.startsWith('5'));
            if (nextBtn) nextBtn.disabled = firstName.length < 2 || lastName.length < 2 || !birthday || !phoneOk;
        }
        nameForm.addEventListener('input', validateName);
        document.addEventListener('dob:selected', validateName);
        validateName();
        nameForm.addEventListener('submit', async e => {
            e.preventDefault();
            const { firstName, lastName, birthday, phone } = collectSignupProfile(nameForm);
            if (firstName.length < 2 || lastName.length < 2) { setErr('#nameError', 'Ad ve soyad en az 2 karakter olmalı'); return; }
            if (!birthday) { setErr('#nameError', 'Doğum tarihi seçiniz'); return; }
            if (phone && (phone.length !== 10 || !phone.startsWith('5'))) {
                setErr('#nameError', 'Telefon girilecekse 10 haneli TR numarasi olmali (5xxxxxxxxx)');
                return;
            }

            clrErr('#nameError');
            if (phone) {
                try {
                    const chk = await api.post(API_USER + '/check-phone.php', { phone });
                if (chk.ok && chk.data?.available === false) {
                    setErr('#nameError', 'Bu telefon numarasi zaten kayitli. Farkli bir numara girin.');
                    return;
                }
                } catch {}
            }

            _phone = phone || '';
            saveDraft('address');
            closeM('nameModal');
            prepareAddressModal().then(() => openM('addressModal'));
        });
        document.getElementById('btnBackName')?.addEventListener('click', () => {
            closeM('nameModal'); openM('passModal');
        });
    }

    /* ADIM 4: adres */
    const addressForm = document.getElementById('addressForm');
    if (addressForm) {
        addressForm.addEventListener('submit', async e => {
            e.preventDefault();
            const fn           = (nameForm?.querySelector('[name="firstName"]')?.value || '').trim();
            const ln           = (nameForm?.querySelector('[name="lastName"]')?.value  || '').trim();
            const emailVal     = _savedEmail.trim().toLowerCase();
            const bd           = getBirthdayValue(nameForm);
            const { city, district, neighborhood } = collectSignupAddress();
            const completionError = validateSignupCompletion();
            if (completionError) { setErr('#addressError', completionError); return; }
            const btn = document.getElementById('btnFinish');
            setLoading(btn, true, 'Kaydediliyor...');
            clrErr('#addressError');
            try {
                const res = await api.post(API_USER + '/register.php', {
                    phone: _phone || null, password: _pass,
                    firstName: fn, lastName: ln, birthday: toISOBirthday(bd),
                    email: emailVal,
                    city, district, neighborhood, smsOk: true, emailOk: _emailVerified,
                    googleCredential: getGoogleSignupCredential() || null,
                });
                if (!res.ok) throw new Error(res.error);
                closeM('addressModal');
                _phone = ''; _pass = '';
                setGoogleSignupCredential(null);
                clearDraft();
                showToast('Kayıt tamamlandı, hoş geldin!');
                document.dispatchEvent(new Event('user:loggedin'));
                document.dispatchEvent(new Event('auth:userChanged'));
            } catch (err) {
                setErr('#addressError', err.message || 'Kayıt başarısız');
            } finally { setLoading(btn, false); }
        });
        document.getElementById('btnBackAddress')?.addEventListener('click', () => {
            closeM('addressModal'); openM('nameModal'); initDOBPicker();
        });
    }

    /* GİRİŞ */
    const loginForm = document.getElementById('loginForm');
    loginForm?.addEventListener('submit', async e => {
        e.preventDefault();
        const email = (loginForm.querySelector('[name="email"]')?.value || '').trim().toLowerCase();
        const pass  = loginForm.querySelector('[name="password"]')?.value || '';
        if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { setErr('#loginError', 'Gecerli bir e-posta girin'); return; }
        if (!pass) { setErr('#loginError', 'Şifre girin'); return; }
        const btn = loginForm.querySelector('button[type=submit]');
        setLoading(btn, true, 'Giriş yapılıyor...');
        clrErr('#loginError');
        try {
            const res = await api.post(API_USER + '/login.php', { email, password: pass });
            if (!res.ok) throw new Error(res.error);
            closeM('authModal');
            showToast('Hoş geldin!');
            document.dispatchEvent(new Event('user:loggedin'));
            document.dispatchEvent(new Event('auth:userChanged'));
        } catch (err) {
            setErr('#loginError', err.message || 'Giriş başarısız');
        } finally { setLoading(btn, false); }
    });

    try { document.dispatchEvent(new Event('auth:ready')); } catch {}
    initGoogleAuth().catch(() => {});
}

/* â”€â”€ DOB Picker â”€â”€ */
let _dobInited = false;
async function initDOBPicker() {
    if (_dobInited) return;
    const hiddenInput = document.getElementById('birthdayInput');
    const triggerBtn  = document.getElementById('dobTriggerBtn');
    const display     = document.getElementById('dobDisplay');
    if (!hiddenInput) return;
    try {
        const { attachDOBPicker } = await import('./components/dob-picker.js');
        hiddenInput.style.cssText = 'pointer-events:auto;position:absolute;opacity:0;width:1px;height:1px';
        attachDOBPicker({ input: hiddenInput, years: { min: 1930, max: new Date().getFullYear() - 5 }, locale: 'tr', format: 'dd.MM.yyyy' });
        triggerBtn?.addEventListener('click', e => {
            e.preventDefault(); e.stopPropagation();
            hiddenInput.dispatchEvent(new MouseEvent('click', { bubbles: false, cancelable: true }));
        });
        function onDobChange() {
            const v = hiddenInput.value;
            if (v && display) { display.textContent = formatDobDisplay(v); triggerBtn?.classList.remove('placeholder'); }
            document.dispatchEvent(new Event('dob:selected'));
        }
        hiddenInput.addEventListener('change', onDobChange);
        hiddenInput.addEventListener('input',  onDobChange);
        _dobInited = true;
    } catch (err) {
        console.warn('DOB picker yuklenemedi', err);
        if (triggerBtn) triggerBtn.outerHTML = `<input type="date" name="birthday" id="birthdayInput" class="auth-input" style="margin-bottom:14px" max="${new Date().getFullYear() - 5}-12-31" />`;
    }
}

// dd.MM.yyyy veya yyyy-MM-dd â†’ API icin yyyy-MM-dd formatina cevir
function toISOBirthday(v) {
    if (!v) return null;
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v; // zaten ISO
    if (/^\d{2}\.\d{2}\.\d{4}$/.test(v)) {
        const [d, m, y] = v.split('.');
        return `${y}-${m}-${d}`;
    }
    return null;
}

function formatDobDisplay(v) {
    if (!v) return 'Dogum Tarihi';
    const months = ['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
    const parts  = v.includes('.') ? v.split('.').map(Number) : v.split('-').map(Number).reverse();
    const [d, m, y] = parts;
    return `${d} ${months[m - 1] || m} ${y}`;
}

async function prepareAddressModal() {
    const city = document.getElementById('citySelect');
    const dSel = document.getElementById('districtSelect');
    const nSel = document.getElementById('neighborhoodSelect');
    const reset = (el, lbl) => { if (el) { el.innerHTML = `<option value="" disabled selected>${lbl}</option>`; el.disabled = true; } };
    reset(city, 'Sehir secin'); reset(dSel, 'Ilce secin'); reset(nSel, 'Mahalle secin');
    try {
        const { attachTRLocationCombo } = await import('./components/select-combo.js');
        await attachTRLocationCombo({ citySelect: city, districtSelect: dSel, neighborhoodSelect: nSel });
    } catch {}
    function chkValid() { const btn = document.getElementById('btnFinish'); if (btn) btn.disabled = !(city?.value && dSel?.value && nSel?.value); }
    city?.addEventListener('change', chkValid);
    dSel?.addEventListener('change', chkValid);
    nSel?.addEventListener('change', chkValid);
    chkValid();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAuth);
} else {
    initAuth();
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Email OTP Modal
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
async function _showEmailOtpModal(email, onSuccess) {
    // Mevcut modal varsa kaldÄ±r
    document.getElementById('emailOtpOverlay')?.remove();

    const overlay = document.createElement('div');
    overlay.id = 'emailOtpOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:2147483646;padding:20px;';
    overlay.innerHTML = `
        <div style="background:#fff;border-radius:20px;padding:32px 28px;max-width:380px;width:100%;max-height:min(90vh,720px);overflow:auto;box-shadow:0 20px 60px rgba(0,0,0,.3);position:relative;">
            <h3 style="margin:0 0 8px;font-size:20px;color:#111827;text-align:center;">Email Dogrulama</h3>
            <p style="color:#6b7280;font-size:14px;text-align:center;margin:0 0 24px;"><strong>${email}</strong> adresine 6 haneli kod gonderdik.</p>
            <input id="emailOtpInput" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="6"
                placeholder="_ _ _ _ _ _"
                style="width:100%;padding:16px;font-size:28px;font-weight:700;letter-spacing:10px;text-align:center;border:2px solid #e5e7eb;border-radius:12px;outline:none;box-sizing:border-box;font-family:monospace;" />
            <div id="emailOtpErr" style="color:#ef4444;font-size:13px;text-align:center;margin:8px 0 0;min-height:18px;"></div>
            <button id="emailOtpVerifyBtn" style="width:100%;padding:14px;background:#19a0b6;color:#fff;border:none;border-radius:12px;font-size:15px;font-weight:700;cursor:pointer;margin-top:16px;">Dogrula</button>
            <div style="text-align:center;margin-top:14px;">
                <button id="emailOtpResendBtn" style="background:none;border:none;color:#19a0b6;font-size:13px;cursor:pointer;text-decoration:underline;">Kodu tekrar gonder</button>
            </div>
        </div>`;
    document.body.appendChild(overlay);

    const inp  = overlay.querySelector('#emailOtpInput');
    const err  = overlay.querySelector('#emailOtpErr');
    const btn  = overlay.querySelector('#emailOtpVerifyBtn');

    inp?.focus();

    // DoÄŸrula
    async function verify() {
        const code = (inp?.value || '').replace(/\s/g, '');
        if (code.length !== 6) { err.textContent = '6 haneli kodu girin'; return; }
        btn.disabled = true; btn.textContent = 'Dogrulaniyor...';
        err.textContent = '';
        try {
            let _csrf1 = window.__csrfToken || null;
            if (!_csrf1) { try { const _cr = await fetch('/api/csrf.php',{credentials:'include'}); const _cj = await _cr.json(); _csrf1 = _cj?.data?.token||null; window.__csrfToken=_csrf1; } catch {} }
            const res = await fetch('/api/auth/email-verify-otp.php', {
                method: 'POST', credentials: 'include',
                headers: { 'Content-Type': 'application/json', ...(_csrf1 ? {'X-CSRF-Token': _csrf1} : {}) },
                body: JSON.stringify({ email, code, purpose: 'email_verify' })
            });
            const data = await res.json();
            if (data?.ok) {
                overlay.remove();
                onSuccess();
            } else {
                err.textContent = data?.error || 'Yanlis kod';
                btn.disabled = false; btn.textContent = 'Dogrula';
            }
        } catch {
            err.textContent = 'Baglanti hatasi';
            btn.disabled = false; btn.textContent = 'Dogrula';
        }
    }

    btn?.addEventListener('click', verify);
    inp?.addEventListener('keydown', e => { if (e.key === 'Enter') verify(); });

    // Tekrar gÃ¶nder
    overlay.querySelector('#emailOtpResendBtn')?.addEventListener('click', async () => {
        err.textContent = 'Gonderiliyor...';
        try {
            let _csrf2 = window.__csrfToken || null;
        if (!_csrf2) { try { const _cr = await fetch('/api/csrf.php',{credentials:'include'}); const _cj = await _cr.json(); _csrf2 = _cj?.data?.token||null; window.__csrfToken=_csrf2; } catch {} }
        await fetch('/api/auth/email-send-otp.php', {
                method: 'POST', credentials: 'include',
                headers: { 'Content-Type': 'application/json', ...(_csrf2 ? {'X-CSRF-Token': _csrf2} : {}) },
                body: JSON.stringify({ email })
            });
            err.textContent = 'Yeni kod gonderildi!';
            inp.value = '';
        } catch { err.textContent = 'Gonderilemedi'; }
    });
}




