/* Mobil davranışları: 2 kolon görünürlük, bottom bar, boyut değişimlerine uyum */
(function initMobile() {
  const mq = window.matchMedia("(max-width: 900px)");
  const root = document.documentElement;

  // Mobil alt menü elemanları
  const mobMenuBtn = document.getElementById("mobMenuBtn");
  const mobMenu = document.getElementById("mobMenu");
  const mobMenuView = document.getElementById("mobMenuView");
  const mobMenuStaff = document.getElementById("mobMenuStaff");

  // Masaüstü popover tetikleyicileri
  const viewChip = document.getElementById("viewChip");
  const viewPop = document.getElementById("viewPop");
  const staffBtn = document.getElementById("staffBtn");
  const staffPop = document.getElementById("staffPop");

  function isMob() {
    return mq.matches;
  }

  function isMobMenuOpen() {
    return mobMenu && mobMenu.getAttribute("aria-hidden") === "false";
  }

  function openMobMenu() {
    if (!mobMenu || !mobMenuBtn) return;
    mobMenu.setAttribute("aria-hidden", "false");
    mobMenuBtn.setAttribute("aria-expanded", "true");
  }

  function closeMobMenu() {
    if (!mobMenu || !mobMenuBtn) return;
    mobMenu.setAttribute("aria-hidden", "true");
    mobMenuBtn.setAttribute("aria-expanded", "false");
  }

  function toggleMobMenu() {
    if (!mobMenu || !mobMenuBtn) return;
    if (isMobMenuOpen()) closeMobMenu();
    else openMobMenu();
  }

  // Görünüm popover'ını aç (zaten açıksa tekrar toggle etme)
  function openViewPopover() {
    if (!viewChip || !viewPop) return;
    if (!viewPop.classList.contains("open")) {
      viewChip.click();
    }
  }

  // Personel popover'ını aç (zaten açıksa tekrar toggle etme)
  function openStaffPopover() {
    if (!staffBtn || !staffPop) return;
    if (!staffPop.classList.contains("open")) {
      staffBtn.click();
    }
  }

  function applyMobileClass() {
    const mobile = isMob();
    root.classList.toggle("is-mobile", mobile);
    if (!mobile) {
      // Masaüstüne dönünce menü mutlaka kapalı olsun
      closeMobMenu();
    }
  }

  // Aktif görünümü yeniden çiz (gün mü hafta mı açık ise)
  // Not: calendar.js modülünde global fonksiyon yoksa bu çağrı sessizce boşa düşer.
  function reflowIfNeeded() {
    try {
      const dayEl = document.getElementById("dayView");
      const isDayActive = dayEl && !dayEl.hidden;

      if (isDayActive && typeof window.renderDay === "function") {
        window.renderDay();
      } else if (typeof window.renderWeek === "function") {
        window.renderWeek();
      }
    } catch (_) {
      // sessizce geç
    }
  }

  // --- Olay bağlama ---

  // Mobil menü butonu
  mobMenuBtn?.addEventListener("click", (e) => {
    e.preventDefault();
    if (!isMob()) return; // sadece mobilde
    toggleMobMenu();
  });

  // Menü: Görünüm
  mobMenuView?.addEventListener("click", (e) => {
    e.preventDefault();
    if (!isMob()) return;
    closeMobMenu();
    openViewPopover();
  });

  // Menü: Personel
  mobMenuStaff?.addEventListener("click", (e) => {
    e.preventDefault();
    if (!isMob()) return;
    closeMobMenu();
    openStaffPopover();
  });

  // Dışarı tıklayınca alt menüyü kapat
  document.addEventListener("mousedown", (e) => {
    if (!isMob() || !isMobMenuOpen()) return;
    const inside =
      e.target.closest("#mobMenu") || e.target.closest("#mobMenuBtn");
    if (!inside) closeMobMenu();
  });

  // ESC ile kapat
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isMobMenuOpen()) {
      closeMobMenu();
    }
  });

  // İlk durum
  applyMobileClass();
  reflowIfNeeded();

  // Eşik değişince sınıfı güncelle + yeniden çiz
  mq.addEventListener?.("change", () => {
    applyMobileClass();
    reflowIfNeeded();
  });

  // Ekran döndürme / resize’da da yeniden hesapla
  window.addEventListener("orientationchange", reflowIfNeeded);
  window.addEventListener("resize", reflowIfNeeded, { passive: true });
})();
