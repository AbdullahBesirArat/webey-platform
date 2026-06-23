/**
 * demo-notifications.js — Webey Pazarlama Sayfaları Sahte Bildirim Sistemi
 * isletmeni-listele.html ve fiyat.html sayfalarında çalışır.
 * Sol alt: randevu bildirimleri | Sağ alt: kayıt bildirimleri
 */
(function () {
  'use strict';

  /* ─── Bildirim Havuzu ──────────────────────────────────────────── */
  const LEFT_NOTIFICATIONS = [
    { icon: '📅', color: '#10b981', title: 'Yeni randevu talebi', sub: 'Zeynep Arslan • Bugün 14:30' },
    { icon: '🔄', color: '#f59e0b', title: 'Randevu saatini değiştirmek istiyor', sub: 'Mehmet Yılmaz • Yarın 11:00 → 13:00' },
    { icon: '⭐', color: '#6366f1', title: 'İlk defa sizden randevu aldı!', sub: 'Fatma Kaya • Saç Boyama' },
    { icon: '📅', color: '#10b981', title: 'Yeni randevu talebi', sub: 'Hasan Demir • Yarın 16:00' },
    { icon: '✅', color: '#10b981', title: 'Randevu onaylandı', sub: 'Ayşe Çelik • Manikür & Pedikür' },
    { icon: '🔄', color: '#f59e0b', title: 'Randevu saatini değiştirmek istiyor', sub: 'Elif Şahin • Cmt 10:00 → 12:30' },
    { icon: '⭐', color: '#6366f1', title: 'İlk defa sizden randevu aldı!', sub: 'Selin Koca • Keratin Bakımı' },
    { icon: '📅', color: '#10b981', title: 'Yeni randevu talebi', sub: 'Murat Aydın • Bugün 18:30' },
    { icon: '⭐', color: '#6366f1', title: 'İlk defa sizden randevu aldı!', sub: 'Büşra Öztürk • Saç Kesimi' },
    { icon: '🔄', color: '#f59e0b', title: 'Randevu iptali isteniyor', sub: 'Tolga Kurt • Yarın 15:00' },
    { icon: '📅', color: '#10b981', title: 'Yeni randevu talebi', sub: 'Gülşen Yıldız • Pzr 11:00' },
    { icon: '📅', color: '#10b981', title: 'Yeni randevu talebi', sub: 'Ahmet Bozkurt • Sal 09:30' },
    { icon: '⭐', color: '#6366f1', title: 'İlk defa sizden randevu aldı!', sub: 'Merve Polat • Cilt Bakımı' },
  ];

  const RIGHT_NOTIFICATIONS = [
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Zeynep A. siteye üye oldu • İstanbul' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Güzellik Studio siteye eklendi • Ankara' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Emre K. siteye üye oldu • İzmir' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Lara Güzellik Salonu • Bursa' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Dilara M. siteye üye oldu • Antalya' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Berber Şükrü admin olarak katıldı • Konya' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Ozan T. siteye üye oldu • Adana' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Bayan Kuaförü Pınar • Gaziantep' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Ceyda N. siteye üye oldu • Kayseri' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Elit Hair Studio admin olarak katıldı • İstanbul' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Barış S. siteye üye oldu • Trabzon' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'MakasSanatı Kuaför • Eskişehir' },
    { icon: '👤', color: '#0ea5e9', title: 'Yeni müşteri kaydoldu', sub: 'Neslihan Y. siteye üye oldu • Samsun' },
    { icon: '🏪', color: '#8b5cf6', title: 'Yeni işletme kaydoldu', sub: 'Prestige Güzellik Merkezi • Mersin' },
  ];

  /* ─── Stil Enjeksiyonu ─────────────────────────────────────────── */
  function injectStyles() {
    if (document.getElementById('demoNotifStyles')) return;
    const s = document.createElement('style');
    s.id = 'demoNotifStyles';
    s.textContent = `
      /* Container'lar */
      #demoNotifLeft,
      #demoNotifRight {
        position: fixed;
        bottom: 24px;
        z-index: 99;
        display: flex;
        flex-direction: column-reverse;
        gap: 10px;
        pointer-events: none;
        max-width: min(300px, calc(50vw - 20px));
      }
      #demoNotifLeft  { left: 20px; }
      #demoNotifRight { right: 20px; }

      /* Tek kart */
      .demo-toast {
        pointer-events: all;
        background: rgba(14, 16, 25, 0.96);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        border: 1px solid rgba(255,255,255,0.10);
        border-radius: 14px;
        padding: 12px 14px;
        display: flex;
        align-items: center;
        gap: 11px;
        box-shadow: 0 12px 40px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.04);
        animation: demoToastIn .4s cubic-bezier(.34,1.46,.64,1) forwards;
        border-left: 3px solid var(--dc, #6366f1);
        min-width: 230px;
        cursor: default;
        user-select: none;
      }
      .demo-toast.out {
        animation: demoToastOut .3s ease forwards;
      }
      @keyframes demoToastIn {
        from { opacity: 0; transform: translateY(18px) scale(.90); }
        to   { opacity: 1; transform: translateY(0)   scale(1); }
      }
      @keyframes demoToastOut {
        to { opacity: 0; transform: translateY(8px) scale(.93); max-height: 0; padding: 0; margin: 0; }
      }

      .demo-toast-icon {
        width: 36px;
        height: 36px;
        border-radius: 10px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 17px;
        flex-shrink: 0;
        background: var(--di-bg, rgba(99,102,241,0.15));
      }
      .demo-toast-body { flex: 1; min-width: 0; }
      .demo-toast-title {
        font-size: 12px;
        font-weight: 700;
        color: #f1f5f9;
        line-height: 1.3;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .demo-toast-sub {
        font-size: 11px;
        color: #64748b;
        margin-top: 2px;
        line-height: 1.4;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .demo-toast-time {
        font-size: 10px;
        color: #374151;
        flex-shrink: 0;
        align-self: flex-start;
        padding-top: 2px;
      }

      /* Canlı nokta */
      .demo-live-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #10b981;
        flex-shrink: 0;
        animation: demoBlink 1.5s ease-in-out infinite;
      }
      @keyframes demoBlink {
        0%, 100% { opacity: 1; }
        50%       { opacity: .3; }
      }

      /* Mobilde sağı gizle */
      @media (max-width: 640px) {
        #demoNotifRight { display: none; }
        #demoNotifLeft  { max-width: calc(100vw - 40px); }
      }
    `;
    document.head.appendChild(s);
  }

  /* ─── Container oluştur ────────────────────────────────────────── */
  function createContainers() {
    if (!document.getElementById('demoNotifLeft')) {
      const l = document.createElement('div');
      l.id = 'demoNotifLeft';
      document.body.appendChild(l);
    }
    if (!document.getElementById('demoNotifRight')) {
      const r = document.createElement('div');
      r.id = 'demoNotifRight';
      document.body.appendChild(r);
    }
  }

  /* ─── Toast render ─────────────────────────────────────────────── */
  function makeToast(notif) {
    const el = document.createElement('div');
    el.className = 'demo-toast';
    el.style.setProperty('--dc', notif.color);
    el.style.setProperty('--di-bg', notif.color + '22');

    // Zaman
    const now = new Date();
    const t = `${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}`;

    el.innerHTML = `
      <div class="demo-toast-icon">${notif.icon}</div>
      <div class="demo-toast-body">
        <div class="demo-toast-title">${notif.title}</div>
        <div class="demo-toast-sub">${notif.sub}</div>
      </div>
      <div style="display:flex;flex-direction:column;align-items:flex-end;gap:5px;flex-shrink:0">
        <div class="demo-toast-time">${t}</div>
        <div class="demo-live-dot"></div>
      </div>
    `;
    return el;
  }

  /* ─── Toast göster ─────────────────────────────────────────────── */
  let leftIdx  = Math.floor(Math.random() * LEFT_NOTIFICATIONS.length);
  let rightIdx = Math.floor(Math.random() * RIGHT_NOTIFICATIONS.length);
  const MAX_VISIBLE = 3;

  function showLeft() {
    const container = document.getElementById('demoNotifLeft');
    if (!container) return;

    // Max 3 kart
    const existing = container.querySelectorAll('.demo-toast');
    if (existing.length >= MAX_VISIBLE) {
      const oldest = existing[existing.length - 1];
      oldest.classList.add('out');
      oldest.addEventListener('animationend', () => oldest.remove(), { once: true });
    }

    const notif = LEFT_NOTIFICATIONS[leftIdx % LEFT_NOTIFICATIONS.length];
    leftIdx++;
    const toast = makeToast(notif);
    container.prepend(toast);

    // 6 saniye sonra çıkış animasyonu
    setTimeout(() => {
      toast.classList.add('out');
      toast.addEventListener('animationend', () => toast.remove(), { once: true });
    }, 6000);
  }

  function showRight() {
    const container = document.getElementById('demoNotifRight');
    if (!container) return;

    const existing = container.querySelectorAll('.demo-toast');
    if (existing.length >= MAX_VISIBLE) {
      const oldest = existing[existing.length - 1];
      oldest.classList.add('out');
      oldest.addEventListener('animationend', () => oldest.remove(), { once: true });
    }

    const notif = RIGHT_NOTIFICATIONS[rightIdx % RIGHT_NOTIFICATIONS.length];
    rightIdx++;
    const toast = makeToast(notif);
    container.prepend(toast);

    setTimeout(() => {
      toast.classList.add('out');
      toast.addEventListener('animationend', () => toast.remove(), { once: true });
    }, 6000);
  }

  /* ─── Başlat ───────────────────────────────────────────────────── */
  function init() {
    injectStyles();
    createContainers();

    // İlk bildirimler hemen gelsin
    setTimeout(showLeft,  800);
    setTimeout(showRight, 2200);

    // Sol: her 5sn, sağ: her 5sn (2.5sn offset ile birbirini takip eder)
    setInterval(showLeft,  5000);
    setInterval(showRight, 5000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();