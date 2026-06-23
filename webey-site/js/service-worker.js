/* ============================================================
   Webey Service Worker  v2.0.0
   Geliştirilmiş: 3 cache bucket, offline.html, image TTL,
   background sync hazırlığı, versiyon stratejisi
   ============================================================ */

const CACHE_VERSION  = 'v4';
const STATIC_CACHE   = `webey-static-${CACHE_VERSION}`;
const PAGES_CACHE    = `webey-pages-${CACHE_VERSION}`;
const IMAGES_CACHE   = `webey-images-${CACHE_VERSION}`;
const OFFLINE_URL    = '/offline.html';
const IMAGE_TTL_MS   = 3 * 24 * 60 * 60 * 1000; // 3 gün

/* Kurulumda önbelleğe alınacak statik varlıklar */
const PRECACHE_STATIC = [
  '/js/wb-api-shim.js',
  '/css/index.css',
  '/css/kuafor.css',
  '/css/auth-modal.css',
  '/css/wb-transitions.css',
  '/css/wb-bottom-nav.css',
  '/css/cookie-consent.css',
  '/js/index.js',
  '/js/kuafor.js',
  '/js/auth.js',
  '/js/wb-transitions.js',
  '/js/wb-bottom-nav.js',
  '/js/cookie-consent.js',
  '/manifest.json',
  '/offline.html',
];

const PRECACHE_PAGES = [
  '/',
  '/index.html',
  '/kuafor.html',
  '/sss.html',
  '/fiyat.html',
  '/404.html',
];

/* ── INSTALL ── */
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const [staticCache, pagesCache] = await Promise.all([
      caches.open(STATIC_CACHE),
      caches.open(PAGES_CACHE),
    ]);
    await Promise.allSettled([
      staticCache.addAll(PRECACHE_STATIC),
      pagesCache.addAll(PRECACHE_PAGES),
    ]);
    self.skipWaiting();
  })());
});

/* ── ACTIVATE — Eski cache'leri temizle ── */
self.addEventListener('activate', event => {
  const ACTIVE = new Set([STATIC_CACHE, PAGES_CACHE, IMAGES_CACHE]);
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => !ACTIVE.has(k)).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

/* ── FETCH ── */
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Farklı origin'den gelen istekler (CDN, fonts vb.) → her zaman ağ
  if (url.origin !== self.location.origin && !url.hostname.includes('fonts.gstatic')) {
    return;
  }

  // API istekleri → Network-first, çevrimdışı hata döner
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request).catch(() =>
        new Response(
          JSON.stringify({ ok: false, error: 'Çevrimdışısınız. İnternet bağlantınızı kontrol edin.', code: 'offline' }),
          { status: 503, headers: { 'Content-Type': 'application/json' } }
        )
      )
    );
    return;
  }

  // Resimler → Cache-first, TTL kontrollü
  if (/\.(jpe?g|png|webp|gif|svg|ico)$/i.test(url.pathname) || url.hostname.includes('cdn')) {
    event.respondWith(imageStrategy(request));
    return;
  }

  // Statik varlıklar (JS, CSS) → Stale-while-revalidate
  if (/\.(css|js|woff2?|ttf)$/i.test(url.pathname)) {
    event.respondWith(staleWhileRevalidate(request, STATIC_CACHE));
    return;
  }

  // HTML sayfalar → Network-first, fallback cache, fallback offline
  if (request.headers.get('Accept')?.includes('text/html') || url.pathname.endsWith('.html') || url.pathname === '/') {
    event.respondWith(networkFirstPage(request));
    return;
  }
});

/* ── Strateji: Network-first (HTML) ── */
async function networkFirstPage(request) {
  try {
    const networkRes = await fetch(request);
    if (networkRes.ok) {
      const cache = await caches.open(PAGES_CACHE);
      cache.put(request, networkRes.clone());
    }
    return networkRes;
  } catch {
    const cached = await caches.match(request);
    if (cached) return cached;
    return caches.match(OFFLINE_URL);
  }
}

/* ── Strateji: Stale-while-revalidate (CSS/JS) ── */
async function staleWhileRevalidate(request, cacheName) {
  const cache  = await caches.open(cacheName);
  const cached = await cache.match(request);
  const networkFetch = fetch(request).then(res => {
    if (res.ok) cache.put(request, res.clone());
    return res;
  }).catch(() => null);
  return cached || await networkFetch;
}

/* ── Strateji: Cache-first + TTL (resimler) ── */
async function imageStrategy(request) {
  const cache  = await caches.open(IMAGES_CACHE);
  const cached = await cache.match(request);

  if (cached) {
    const dateHeader = cached.headers.get('date');
    const cachedAt   = dateHeader ? new Date(dateHeader).getTime() : 0;
    if (Date.now() - cachedAt < IMAGE_TTL_MS) {
      return cached; // TTL içinde → direkt cache
    }
  }

  try {
    const res = await fetch(request);
    if (res.ok) cache.put(request, res.clone());
    return res;
  } catch {
    return cached || Response.error();
  }
}

/* ── PUSH Bildirimleri ── */
self.addEventListener('push', event => {
  if (!event.data) return;
  let data = {};
  try { data = event.data.json(); } catch { data = { title: 'Webey', body: event.data.text() }; }

  const options = {
    body:    data.body    || 'Yeni bildiriminiz var',
    icon:    data.icon    || '/img/icon-192.png',
    badge:   data.badge   || '/img/icon-192.png',
    image:   data.image   || undefined,
    data:    data.data    || { url: '/' },
    tag:     data.tag     || 'webey-notification',
    vibrate: [200, 100, 200],
    actions: data.actions || [
      { action: 'open',    title: 'Görüntüle' },
      { action: 'dismiss', title: 'Kapat'     },
    ],
  };

  event.waitUntil(
    self.registration.showNotification(data.title || 'Webey', options)
  );
});

/* ── Bildirime tıklama ── */
self.addEventListener('notificationclick', event => {
  event.notification.close();
  if (event.action === 'dismiss') return;

  const url = event.notification.data?.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(wins => {
      const match = wins.find(w => w.url === url && 'focus' in w);
      if (match) return match.focus();
      return clients.openWindow(url);
    })
  );
});
