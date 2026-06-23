/**
 * js/api-client.js
 * Firebase'in YERİNİ ALAN merkezi API yardımcısı.
 * Tüm fetch çağrıları buradan geçer — session cookie otomatik gönderilir.
 *
 * Kullanım:
 *   import { api, getSession, onAuthChange } from './api-client.js';
 *
 *   // Kullanım: /api/session/me.php
 *   const res = await api.post('/api/auth/login.php', { email, password });  // admin
 *   const res = await api.post('/api/user/login.php',  { phone, password });  // müşteri
 */

/* ─── Temel Ayarlar ─── */
const BASE = '';                // Aynı origin'de çalışıyor, prefix gerekmez
const DEFAULT_TIMEOUT = 12000; // ms

/* ─────────────────────────────────────────────
   CSRF TOKEN YÖNETİMİ
   Sayfa yüklenince /api/csrf.php'den token alınır.
   Tüm POST/PUT/DELETE isteklerine X-CSRF-Token header'ı eklenir.
───────────────────────────────────────────── */
let _csrfToken = null;
let _csrfFetchPromise = null;

async function fetchCsrfToken() {
    // Zaten fetch ediliyorsa aynı promise'i döndür (paralel çağrıları önle)
    if (_csrfFetchPromise) return _csrfFetchPromise;

    _csrfFetchPromise = fetch('/api/csrf.php', {
        method: 'GET',
        credentials: 'include',
        headers: { 'Cache-Control': 'no-cache' },
    })
        .then(r => r.json())
        .then(data => {
            if (data?.ok && data?.data?.token) {
                _csrfToken = data.data.token;
            }
            _csrfFetchPromise = null;
            return _csrfToken;
        })
        .catch(() => {
            _csrfFetchPromise = null;
            return null;
        });

    return _csrfFetchPromise;
}

/** CSRF token'ını döndürür; yoksa önce fetch eder */
async function getCsrfToken() {
    if (_csrfToken) return _csrfToken;
    return fetchCsrfToken();
}

/** Login/logout sonrası token'ı sıfırla ve yeniden al */
export function resetCsrfToken() {
    _csrfToken = null;
    fetchCsrfToken();
}

/* ─── Yardımcılar ─── */
function timeout(ms) {
    return new Promise((_, reject) =>
        setTimeout(() => reject(new Error('İstek zaman aşımına uğradı')), ms)
    );
}

const CSRF_METHODS = new Set(['POST', 'PUT', 'DELETE', 'PATCH']);

async function request(method, url, body = null, opts = {}) {
    const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };

    // State değiştiren isteklere CSRF token ekle
    if (CSRF_METHODS.has(method.toUpperCase())) {
        const token = await getCsrfToken();
        if (token) {
            headers['X-CSRF-Token'] = token;
        }
    }

    const fetchOpts = {
        method,
        credentials: 'include',   // Session cookie her zaman gönderilsin
        headers,
    };

    if (body !== null) {
        fetchOpts.body = JSON.stringify(body);
    }

    const res = await Promise.race([
        fetch(BASE + url, fetchOpts),
        timeout(opts.timeout || DEFAULT_TIMEOUT)
    ]);

    const json = await res.json().catch(() => ({
        ok: false,
        error: `Sunucu yanıtı okunamadı (HTTP ${res.status})`
    }));

    // CSRF token süresi dolmuşsa → yenile ve isteği bir kez tekrar dene
    if (!json.ok && json.code === 'csrf_invalid') {
        _csrfToken = null;
        const newToken = await fetchCsrfToken();
        if (newToken) {
            headers['X-CSRF-Token'] = newToken;
            const retryRes = await fetch(BASE + url, { ...fetchOpts, headers });
            return retryRes.json().catch(() => ({
                ok: false,
                error: `Sunucu yanıtı okunamadı (yeniden deneme)`
            }));
        }
    }

    // HTTP hata ama body'de ok:true yoksa normalize et
    if (!res.ok && json.ok === undefined) {
        json.ok = false;
        json.error = json.error || `HTTP ${res.status}`;
    }

    return json;
}

/* ─── API Nesnesi ─── */
export const api = {
    get:    (url, opts)       => request('GET',    url, null, opts),
    post:   (url, body, opts) => request('POST',   url, body, opts),
    put:    (url, body, opts) => request('PUT',    url, body, opts),
    delete: (url, opts)       => request('DELETE', url, null, opts),
};

/* ─────────────────────────────────────────────
   SESSION / AUTH STATE
   Firebase'in onAuthStateChanged() yerine
   bu modül basit bir event sistemi kullanıyor.
───────────────────────────────────────────── */

let _session = null;         // { userId, role, ... } | null
let _ready   = false;
const _listeners = new Set();

/** Mevcut session nesnesini döner (null = giriş yapılmamış) */
export function getSession() { return _session; }

/** Auth değişimlerini dinle — ilk çağrıda da hemen tetiklenir */
export function onAuthChange(fn) {
    _listeners.add(fn);
    if (_ready) fn(_session);   // Eğer zaten hazırsa hemen çağır
    return () => _listeners.delete(fn); // unsubscribe fonksiyonu
}

function _notify() {
    _listeners.forEach(fn => { try { fn(_session); } catch {} });
}

/** Session'ı yenile — login/logout sonrası çağır */
export async function refreshSession() {
    try {
        // Tek istekle her iki rolü kontrol et (session/me.php admin ve user'ı birlikte işler)
        const res = await api.get('/api/session/me.php');

        if (res.ok && res.data) {
            const d = res.data;

            if (d.role === 'admin') {
                _session = {
                    type:                'admin',
                    userId:              d.adminId             || null,
                    email:               d.email               || null,
                    businessId:          d.businessId          || null,
                    onboardingCompleted: d.onboardingCompleted || false,
                    onboardingStep:      d.onboardingStep      || 0,
                    status:              d.status              || null,
                };
            } else if (d.role === 'user') {
                _session = {
                    type:      'user',
                    userId:    d.userId,
                    phone:     d.phone,
                    firstName: d.firstName,
                    lastName:  d.lastName,
                    city:      d.city,
                    district:  d.district,
                };
            } else {
                _session = null;
            }

            _ready = true;
            _notify();
            return _session;
        }
    } catch {}

    // Giriş yapılmamış veya hata
    _session = null;
    _ready   = true;
    _notify();
    return null;
}

/** Session'ı temizle (logout sonrası) */
export function clearSession() {
    _session = null;
    _notify();
}

/* ─── Sayfa yüklenince otomatik kontrol ─── */
if (typeof window !== 'undefined') {
    // DOMContentLoaded'ı bekle; çok erken çağrılırsa sorun olmaz
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            fetchCsrfToken(); // CSRF token'ı önceden al
            refreshSession();
        });
    } else {
        fetchCsrfToken(); // CSRF token'ı önceden al
        refreshSession();
    }

    // auth.js ile entegre: login/logout eventleri
    document.addEventListener('user:loggedin',  () => { resetCsrfToken(); refreshSession(); });
    document.addEventListener('auth:userChanged', () => { resetCsrfToken(); refreshSession(); });
    document.addEventListener('user:loggedout', () => {
        resetCsrfToken();
        _session = null;
        _notify();
    });
}

/* ─── Firebase uyumluluk shim ─── */
// Eski firebase.js'i import eden dosyalar için boş shim'ler.
// Bunları gerçek API çağrısıyla değiştirin.
export const db      = null;  // Firestore yok — PHP API kullan
export const auth    = null;  // Firebase auth yok — session kullan
export const storage = null;  // Firebase storage yok — /api/settings/upload-image.php kullan

export default api;