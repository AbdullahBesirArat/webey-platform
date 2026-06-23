/**
 * js/kuafor-map.js
 * â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
 * kuafor.html'e ekstra Ã¶zellikler:
 *   1. Sort chipleri (En Yeni / Puan / Fiyat)
 *   2. "Åu an aÃ§Ä±k" toggle
 *   3. Leaflet.js harita gÃ¶rÃ¼nÃ¼mÃ¼
 *   4. "Daha Fazla GÃ¶ster" (Load More) butonu
 *
 * Mevcut kuafor.js'e dokunmaz â€” window.ALL_SALONS ve window.renderList
 * fonksiyonlarÄ±na hook eder. kuafor.js'den SONRA yÃ¼klenmelidir.
 *
 * HTML'e ekle (kuafor.js'den sonra):
 *   <script src="js/kuafor-map.js" defer></script>
 * â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
 */

(function () {
  'use strict';

  /* â”€â”€ Ayarlar â”€â”€ */
  const PAGE_SIZE   = 18;    // Her sayfada kaÃ§ salon
  const MAP_CENTER  = [41.015, 28.979]; // Ä°stanbul
  const MAP_ZOOM    = 12;
  const LEAFLET_CSS = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
  const LEAFLET_JS  = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';

  /* â”€â”€ State â”€â”€ */
  let currentSort    = 'newest';
  let openNowActive  = false;
  let currentPage    = 1;
  let mapInitialized = false;
  let leafletMap     = null;
  let markers        = [];

  /* â”€â”€ DOM ReferanslarÄ± â”€â”€ */
  const chipBtns    = document.querySelectorAll('.wb-chip[data-sort]');
  const toggle      = document.getElementById('openNowToggle');
  const toggleLabel = document.getElementById('openNowLabel');
  const mapViewBtn  = document.getElementById('mapViewBtn');
  const closeMapBtn = document.getElementById('closeMapBtn');
  const mapPanel    = document.getElementById('mapPanel');
  const loadMoreWrap = document.getElementById('loadMoreWrap');
  const loadMoreBtn  = document.getElementById('loadMoreBtn');
  const grid         = document.getElementById('salonGrid');

  /* â”€â”€ Sort chipleri â”€â”€ */
  chipBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      chipBtns.forEach(b => b.classList.remove('wb-chip--active'));
      btn.classList.add('wb-chip--active');
      currentSort = btn.dataset.sort;
      currentPage = 1;
      applyEnhancements();
    });
  });

  /* â”€â”€ Åu an aÃ§Ä±k toggle â”€â”€ */
  function setToggle(active) {
    openNowActive = active;
    toggle?.setAttribute('aria-checked', String(active));
    if (toggleLabel) toggleLabel.style.color = active ? '#0ea5b3' : '#374151';
  }

  toggle?.addEventListener('click', () => {
    setToggle(!openNowActive);
    currentPage = 1;
    applyEnhancements();
  });

  toggle?.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      toggle.click();
    }
  });

  /* â”€â”€ AÃ§Ä±k mÄ± kontrolÃ¼ (client-side) â”€â”€ */
  function isOpenNow(salon) {
    const hours = salon.hours || salon.business_hours;
    if (!hours || !Array.isArray(hours)) return true; // Bilgi yoksa gÃ¶ster
    const now  = new Date();
    const dow  = now.getDay(); // 0=Pazar
    const nowMin = now.getHours() * 60 + now.getMinutes();
    const todayHours = hours.find(h => h.day_of_week === dow);
    if (!todayHours || !todayHours.is_open) return false;
    const [oh, om] = (todayHours.open_time  || '00:00').split(':').map(Number);
    const [ch, cm] = (todayHours.close_time || '23:59').split(':').map(Number);
    return nowMin >= oh * 60 + om && nowMin <= ch * 60 + cm;
  }

  /* â”€â”€ SÄ±ralama fonksiyonu â”€â”€ */
  function sortSalons(list) {
    const sorted = [...list];
    switch (currentSort) {
      case 'price_asc':
        sorted.sort((a, b) => {
          const pa = a.min_price ?? a.minPrice ?? Infinity;
          const pb = b.min_price ?? b.minPrice ?? Infinity;
          return pa - pb;
        });
        break;
      case 'price_desc':
        sorted.sort((a, b) => {
          const pa = a.min_price ?? a.minPrice ?? 0;
          const pb = b.min_price ?? b.minPrice ?? 0;
          return pb - pa;
        });
        break;
      default: // newest â€” orijinal sÄ±ra
        break;
    }
    return sorted;
  }

  /* â”€â”€ TÃ¼m geliÅŸtirmeleri uygula â”€â”€ */
  function applyEnhancements() {
    const salons = window.ALL_SALONS;
    if (!Array.isArray(salons)) return;

    // Filtrele
    let filtered = openNowActive ? salons.filter(isOpenNow) : salons.slice();

    // SÄ±rala
    filtered = sortSalons(filtered);

    // Sayfala
    const total     = filtered.length;
    const pageItems = filtered.slice(0, currentPage * PAGE_SIZE);

    // Grid'i yeniden Ã§iz
    renderCustom(pageItems);

    // Load More gÃ¶ster/gizle
    if (loadMoreWrap) {
      loadMoreWrap.style.display = (total > currentPage * PAGE_SIZE) ? 'block' : 'none';
    }
    if (loadMoreBtn) {
      const remaining = total - currentPage * PAGE_SIZE;
      loadMoreBtn.textContent = `Daha Fazla GÃ¶ster (${remaining} kaldÄ±)`;
    }
  }

  /* â”€â”€ KartlarÄ± render et (kuafor.js'deki renderList yerine pagination iÃ§in) â”€â”€ */
  function renderCustom(salons) {
    if (!grid) return;
    if (!salons.length) {
      grid.innerHTML = '';
      document.getElementById('emptyState').style.display = 'block';
      return;
    }
    document.getElementById('emptyState').style.display = 'none';

    grid.innerHTML = salons.map(s => {
      const name     = s.name || s.businessName || '';
      const cover    = s.coverUrl || s.cover || '';
      const city     = s.loc?.city || s.businessLocation?.province || '';
      const district = s.loc?.district || s.businessLocation?.district || '';
      const minPrice = s.min_price || s.minPrice;
      const id       = s.id || s.businessId || '';
      const slug     = s.slug || id;

      return `<a class="card" href="profile.html?id=${id}" style="text-decoration:none;display:block;cursor:pointer;">
        <div class="img" style="background:#f3f4f6;${cover ? `background-image:url('${cover}');background-size:cover;background-position:center;` : ''}"></div>
        <div class="card-body" style="padding:12px 14px;">
          <div style="font-size:15px;font-weight:700;color:#111827;margin-bottom:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${name}</div>
          <div style="font-size:12px;color:#9ca3af;margin-bottom:6px;">${[district,city].filter(Boolean).join(', ')}</div>
          <div style="display:flex;align-items:center;justify-content:space-between;">
            <span></span>
            ${minPrice ? `<span style="font-size:11px;font-weight:800;color:#0ea5b3;">â‚º${minPrice}<span style="font-size:10px;font-weight:500;color:#9ca3af;">'dan baÅŸlayan fiyatlar</span></span>` : ''}
          </div>
        </div>
      </a>`;
    }).join('');
  }

  /* â”€â”€ Load More â”€â”€ */
  loadMoreBtn?.addEventListener('click', () => {
    currentPage++;
    applyEnhancements();
    // Smooth scroll to new items
    const cards = grid?.querySelectorAll('.card');
    if (cards?.length) {
      const newStart = (currentPage - 1) * PAGE_SIZE;
      cards[newStart]?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  });

  /* â”€â”€ Leaflet Harita â”€â”€ */
  function loadLeaflet(cb) {
    if (window.L) { cb(); return; }
    // CSS
    if (!document.getElementById('leaflet-css')) {
      const link = document.createElement('link');
      link.id   = 'leaflet-css';
      link.rel  = 'stylesheet';
      link.href = LEAFLET_CSS;
      document.head.appendChild(link);
    }
    // JS
    const script   = document.createElement('script');
    script.src     = LEAFLET_JS;
    script.onload  = cb;
    document.head.appendChild(script);
  }

  function initMap() {
    if (mapInitialized) return;
    mapInitialized = true;
    leafletMap = L.map('leafletMap').setView(MAP_CENTER, MAP_ZOOM);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: 'Â© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19,
    }).addTo(leafletMap);
  }

  /* â”€â”€ Google Maps URL'inden koordinat Ã§Ä±kar â”€â”€ */
  function extractCoordsFromMapUrl(url) {
    if (!url) return null;
    // Format: .../@lat,lng,zoom  veya  .../@lat,lng,
    let m = url.match(/@(-?\d+\.?\d*),(-?\d+\.?\d*)/);
    if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
    // Format: ?q=lat,lng veya &q=lat,lng
    m = url.match(/[?&]q=(-?\d+\.?\d*),(-?\d+\.?\d*)/);
    if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
    // Format: ll=lat,lng
    m = url.match(/ll=(-?\d+\.?\d*),(-?\d+\.?\d*)/);
    if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
    return null;
  }

  function populateMap() {
    if (!leafletMap || !window.ALL_SALONS) return;

    // Eski markerlarÄ± temizle
    markers.forEach(m => m.remove());
    markers = [];

    const salons = window.ALL_SALONS;
    const bounds = [];
    let mapUrlCount = 0;

    salons.forEach(s => {
      let lat = parseFloat(s.loc?.latitude || s.latitude || s.lat || 0);
      let lng = parseFloat(s.loc?.longitude || s.longitude || s.lng || 0);
      const hasMapUrl = !!(s.map_url || s.mapUrl);

      // lat/lng yoksa Google Maps URL'inden Ã§Ä±karmaya Ã§alÄ±ÅŸ
      if ((!lat || !lng) && hasMapUrl) {
        const coords = extractCoordsFromMapUrl(s.map_url || s.mapUrl);
        if (coords) {
          lat = coords.lat;
          lng = coords.lng;
          mapUrlCount++;
        }
      }

      if (!lat || !lng) return;

      const minPrice = s.min_price || s.minPrice;
      const name     = s.name || '';
      const city     = s.loc?.city || '';
      const district = s.loc?.district || '';
      const id       = s.id || '';
      const mapUrl   = s.map_url || s.mapUrl || null;

      const popup = L.popup({ className: 'wb-map-popup' }).setContent(`
        <div class="wb-popup-inner">
          <div class="wb-popup-name">${name}</div>
          <div class="wb-popup-loc">${[district,city].filter(Boolean).join(', ')}</div>
          ${minPrice ? `<div class="wb-popup-price">â‚º${minPrice}+'dan</div>` : ''}
          ${mapUrl ? `<a href="${mapUrl}" target="_blank" rel="noopener" class="wb-popup-gmaps-link">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>
            Google Maps'te GÃ¶r
          </a>` : ''}
          <a href="profile.html?id=${id}" class="wb-popup-btn">Randevu Al</a>
        </div>
      `);

      // Ã–zel ikon â€” map_url olanlar mor pin
      const pinColor = hasMapUrl ? '#7c3aed' : '#0ea5b3';
      const icon = L.divIcon({
        html: `<div class="wb-gmap-pin${hasMapUrl ? ' has-url' : ''}" style="background:${pinColor}">âœ‚ï¸${rating > 0 ? ' ' + rating.toFixed(1) : ''}</div>`,
        className: '',
        iconAnchor: [24, 14],
      });

      const marker = L.marker([lat, lng], { icon }).addTo(leafletMap).bindPopup(popup);
      markers.push(marker);
      bounds.push([lat, lng]);
    });

    if (bounds.length > 0) {
      leafletMap.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
    } else {
      // HiÃ§ koordinat yoksa boÅŸ uyarÄ± gÃ¶ster
      const empty = document.createElement('div');
      empty.className = 'wb-map-empty';
      empty.innerHTML = `<div class="wb-map-empty-icon">ğŸ“</div><div class="wb-map-empty-title">Haritada gÃ¶sterilecek salon yok</div><div class="wb-map-empty-sub">Salonlar konum bilgisi ekledikÃ§e burada gÃ¶rÃ¼necek</div>`;
      document.getElementById('mapPanel')?.appendChild(empty);
    }
  }

  function showMap() {
    if (!mapPanel) return;
    mapPanel.style.display = 'block';
    mapViewBtn?.classList.add('active');
    document.getElementById('mainContent').style.display = 'none';
    document.getElementById('loadMoreWrap') && (document.getElementById('loadMoreWrap').style.display = 'none');

    loadLeaflet(() => {
      initMap();
      setTimeout(() => {
        leafletMap.invalidateSize();
        populateMap();
      }, 100);
    });
  }

  function hideMap() {
    if (mapPanel) mapPanel.style.display = 'none';
    mapViewBtn?.classList.remove('active');
    document.getElementById('mainContent').style.display = 'block';
    applyEnhancements(); // Load more durumunu gÃ¼ncelle
    // Banner'in gÃ¶rÃ¼nmesi iÃ§in sayfayÄ± en Ã¼ste al
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  mapViewBtn?.addEventListener('click',  showMap);
  closeMapBtn?.addEventListener('click', hideMap);

  /* â”€â”€ kuafor.js'den sonra yÃ¼klenince hook kur â”€â”€ */
  function hookIntoKuafor() {
    // ALL_SALONS deÄŸiÅŸtiÄŸinde sort/filtre/paginationu uygula
    let lastLen = -1;
    const interval = setInterval(() => {
      const salons = window.ALL_SALONS;
      if (Array.isArray(salons) && salons.length !== lastLen) {
        lastLen = salons.length;
        currentPage = 1;
        applyEnhancements();
      }
    }, 300);

    // 10sn sonra interval'Ä± kapat (sayfa yÃ¼klendi)
    setTimeout(() => clearInterval(interval), 10_000);
  }

  // DOM hazÄ±r olduÄŸunda baÅŸlat
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hookIntoKuafor);
  } else {
    hookIntoKuafor();
  }

  // Global eriÅŸim (debug iÃ§in)
  window.WbEnhanced = { applyEnhancements, showMap, hideMap };

})();
