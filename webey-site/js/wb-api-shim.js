/**
 * js/wb-api-shim.js
 * ──────────────────────────────────────────────────────────────────
 * calendar.js, settings.js, staff.js, profile.js ve admin-profile.js
 * içindeki yerel apiGet / apiPost fonksiyonlarının merkezi, tek sürümü.
 *
 * KULLANIM:
 *   1. HTML'de api-client.js'den ÖNCE yükle:
 *      <script type="module" src="js/wb-api-shim.js"></script>
 *      YA DA diğer script'ler global window.WbApi'yi kullanır.
 *
 *   2. Eski dosyaları güncellemeden önce bu shim'i include etmek yeterli;
 *      window.apiGet / window.apiPost olarak global erişilebilir.
 *
 * ÖZELLİKLER:
 *   - Timeout (12sn) ve retry (1 kez) otomatik
 *   - 401/403 → otomatik login redirect
 *   - X-CSRF-Token header otomatik eklenir (wb_csrf_token'den)
 *   - Çevrimdışı durumu detect edilir
 * ──────────────────────────────────────────────────────────────────
 */

const WbApi = (() => {
    const APP_BASE = window.location.pathname.startsWith('/webey/') ? '/webey' : '';
    const BASE          = '';
    const TIMEOUT_MS    = 12_000;
    // Kullanıcı sayfaları (user-profile, bildirimler vb.) index'e, admin sayfaları kendi login'ine
    const _USER_PAGES   = ['/user-profile.html', '/bildirimler.html', '/appointments.html'];
    // profile.html kendi authModal'ını açıyor — redirect etme
    const _MODAL_PAGES  = ['/profile.html'];
    const LOGIN_PATH    = _USER_PAGES.some(p => window.location.pathname.endsWith(p))
        ? (APP_BASE + '/index.html')
        : (APP_BASE + '/admin-register-login.html#login');
    let   _csrfToken    = null;  // PHP'den /api/session/me.php içinde gelir

    /* ── Dahili: Login yönlendirme ── */
    function _redirectLogin(url) {
        // Sayfanın kendi auth modal'ı varsa: sadece randevu endpoint'leri için modal aç
        if (_MODAL_PAGES.some(p => window.location.pathname.endsWith(p))) {
            const _BOOKING = ['/lock.php', '/book.php', '/check-conflict.php', '/unlock.php'];
            const isBooking = _BOOKING.some(p => (url || '').includes(p));
            if (isBooking) {
                window.dispatchEvent(new CustomEvent('wb:needsLogin'));
            }
            return; // next.php, session/me.php vb. 401'ler için sessizce geç
        }
        const here = window.location.pathname + window.location.search + window.location.hash;
        const loginUrl  = new URL(LOGIN_PATH, window.location.origin);
        loginUrl.searchParams.set('return_to', here);
        location.replace(loginUrl.toString());
    }

    function _isAuthFailurePayload(payload) {
        const code = String(payload?.code || '').toLowerCase();
        const err  = String(payload?.error || '').toLowerCase();
        return (
            code === 'unauthorized' ||
            code === 'unauthenticated' ||
            code === 'not_authenticated' ||
            err.includes('yetkisiz') ||
            err.includes('oturum')
        );
    }

    function _pathWithBase(path) {
        if (!path) return path;
        if (/^https?:\/\//i.test(path)) return path;
        if (APP_BASE && path.startsWith('/')) return APP_BASE + path;
        return path;
    }

    /* ── Dahili: Timeout promise ── */
    function _timeout(ms) {
        return new Promise((_, reject) =>
            setTimeout(() => reject(new Error(`İstek zaman aşımı (${ms}ms)`)), ms)
        );
    }

    /* ── Dahili: Güvenli JSON parse ── */
    async function _parseJson(res, path) {
        const ct = res.headers.get('content-type') || '';
        if (!ct.includes('application/json')) {
            const txt = await res.text().catch(() => '');
            throw new Error(`JSON dışı yanıt: ${path} — ${txt.slice(0, 120)}`);
        }
        return res.json();
    }

    /* ── Dahili: Ortak fetch ── */
    async function _fetch(method, url, body, attempt = 0) {
        if (!navigator.onLine) {
            return { ok: false, error: 'Çevrimdışısınız. İnternet bağlantınızı kontrol edin.', code: 'offline' };
        }

        const headers = {
            'Accept':       'application/json',
            'Cache-Control':'no-store',
        };

        if (body !== null) {
            headers['Content-Type'] = 'application/json';
        }

        // CSRF token ekle (POST/PUT/DELETE)
        // Önce kendi cache'ine bak, yoksa window.__csrfToken fallback
        const token = _csrfToken || window.__csrfToken || null;
        if (method !== 'GET' && token) {
            headers['X-CSRF-Token'] = token;
        }

        try {
            const res = await Promise.race([
                fetch(BASE + url, {
                    method,
                    credentials: 'same-origin',
                    headers,
                    cache: 'no-store',
                    body: body !== null ? JSON.stringify(body) : undefined,
                }),
                _timeout(TIMEOUT_MS)
            ]);

            // Auth hataları: sadece gerçek oturum hatalarında login'e yönlendir
            if (res.status === 401 || res.status === 403) {
                let jsonAuth = null;
                try { jsonAuth = await _parseJson(res, url); } catch (_) {}
                if (res.status === 401 || _isAuthFailurePayload(jsonAuth)) {
                    _redirectLogin(url);
                    return null;
                }
                // 403 ama auth değil (ör. wrong_password) ise olduğu gibi döndür
                if (jsonAuth) return jsonAuth;
            }

            // 5xx → 1 kez retry
            if (res.status >= 500 && attempt === 0) {
                await new Promise(r => setTimeout(r, 800));
                return _fetch(method, url, body, 1);
            }

            const json = await _parseJson(res, url);
            return json;

        } catch (err) {
            if (attempt === 0 && navigator.onLine) {
                await new Promise(r => setTimeout(r, 500));
                return _fetch(method, url, body, 1);
            }
            console.error(`[WbApi] ${method} ${url}:`, err.message);
            return { ok: false, error: err.message, code: 'fetch_error' };
        }
    }

    /* ── Public API ── */
    async function get(path, params) {
        const url = new URL(_pathWithBase(path), window.location.origin);
        if (params && typeof params === 'object') {
            Object.entries(params).forEach(([k, v]) => {
                if (v != null) url.searchParams.set(k, String(v));
            });
        }
        return _fetch('GET', url.toString(), null);
    }

    async function post(path, body = {}) {
        return _fetch('POST', _pathWithBase(path), body);
    }

    async function put(path, body = {}) {
        return _fetch('PUT', _pathWithBase(path), body);
    }

    async function del(path, body = {}) {
        return _fetch('DELETE', _pathWithBase(path), body);
    }

    /** Multipart FormData yüklemesi (fotoğraf, görsel vb.) */
    async function upload(path, formData) {
        const uploadPath = _pathWithBase(path);
        const token = _csrfToken || window.__csrfToken || null;
        const headers = { 'Accept': 'application/json' };
        if (token) headers['X-CSRF-Token'] = token;
        try {
            const res = await Promise.race([
                fetch(BASE + uploadPath, {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers,
                    body: formData,
                }),
                _timeout(TIMEOUT_MS)
            ]);
            if (res.status === 401 || res.status === 403) {
                let jsonAuth = null;
                try { jsonAuth = await _parseJson(res, path); } catch (_) {}
                if (res.status === 401 || _isAuthFailurePayload(jsonAuth)) {
                    _redirectLogin(uploadPath);
                    return null;
                }
                if (jsonAuth) return jsonAuth;
            }
            return _parseJson(res, uploadPath);
        } catch (err) {
            console.error(`[WbApi] upload ${uploadPath}:`, err.message);
            return { ok: false, error: err.message, code: 'fetch_error' };
        }
    }

    /** Session'ı yenile + CSRF token'ı güncelle */
    async function refreshSession() {
        const res = await get('/api/session/me.php');
        if (res?.data?.csrf_token) {
            _csrfToken = res.data.csrf_token;
        }
        return res;
    }

    return { get, post, put, del, upload, refreshSession };
})();

/* ── Geriye dönük uyumluluk: eski dosyalar için global ── */
window.WbApi = WbApi;

/* ── Sayfa yüklenince CSRF token'ı otomatik al ── */
(async function _initCsrf() {
    try {
        const csrfPath = (window.location.pathname.startsWith('/webey/') ? '/webey' : '') + '/api/csrf.php';
        const res = await fetch(csrfPath, {
            credentials: 'same-origin',
            cache: 'no-store',
            headers: { 'Accept': 'application/json' }
        });
        const json = await res.json();
        if (json?.ok && json?.data?.token) {
            window.__csrfToken = json.data.token;
        }
    } catch (e) {
        console.warn('[WbApi] CSRF init failed:', e.message);
    }
})();

/**
 * apiGet(path, params?) — calendar.js, settings.js vb. için drop-in
 */
window.apiGet = async function(path, params) {
    return WbApi.get(path, params);
};

/**
 * apiPost(path, body?) — drop-in
 */
window.apiPost = async function(path, body) {
    return WbApi.post(path, body || {});
};

/**
 * apiUpload(path, formData) — drop-in
 */
window.apiUpload = async function(path, formData) {
    return WbApi.upload(path, formData);
};

/* ── Service Worker: offline dedektörü ── */
window.addEventListener('online',  () => console.info('[WbApi] Bağlantı geri geldi ✓'));
window.addEventListener('offline', () => console.warn('[WbApi] Çevrimdışı!'));

// CommonJS ortamında (Node.js / test) export desteği
// Browser'da exports tanımsız olduğu için try/catch ile sarılır
try {
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = WbApi;
    }
} catch (_) { /* browser'da sessizce geç */ }
