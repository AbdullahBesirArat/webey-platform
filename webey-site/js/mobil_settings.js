// js/mobil_settings.js — bar-menu.html loader (yeni app-bar)
// Sayfalarda sadece bu script import edilecek.

(() => {
  const BAR_HTML_URL = "bar-menu.html?v=20251117";
  const APP_BAR_SEL = ".app-bar";
  let mounted = false;

  // Hangi sayfada olduğumuzu bul
  function getCurrentPageKey() {
    const fromBody = document.body.dataset.page;
    if (fromBody) return fromBody;

    const file = window.location.pathname.split("/").pop().split("?")[0] || "index.html";

    if (file === "" || file === "index.html") return "calendar";
    if (file === "calendar.html") return "calendar";
    if (file === "staff.html") return "staff";
    if (file === "settings.html") return "settings";
    if (file === "admin-profile.html") return "profile";

    return file.replace(/\.html$/i, "");
  }

  // Bar üzerindeki aktif linki işaretle + body sınıfı
  function initAppBar(root) {
    const nav = root || document.querySelector(APP_BAR_SEL);
    if (!nav) return;

    document.body.classList.add("has-app-bar");

    const current = getCurrentPageKey();
    nav.querySelectorAll(".app-bar__item").forEach((link) => {
      const page = link.getAttribute("data-page");
      if (page === current) link.classList.add("app-bar__item--active");
      else link.classList.remove("app-bar__item--active");
    });
  }

  async function ensureAppBarMounted() {
    // Zaten nav varsa sadece init et
    const existing = document.querySelector(APP_BAR_SEL);
    if (existing) {
      mounted = true;
      initAppBar(existing);
      return;
    }

    if (mounted) return;

    try {
      const res = await fetch(BAR_HTML_URL, { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);

      const html = await res.text();
      const doc = new DOMParser().parseFromString(html, "text/html");

      // Google font link
      const fontLink = doc.querySelector('link[rel="stylesheet"]');
      if (fontLink && !document.querySelector('link[data-app-bar-font="1"]')) {
        const clone = fontLink.cloneNode(true);
        clone.setAttribute("data-app-bar-font", "1");
        document.head.appendChild(clone);
      }

      // Inline stil
      const inlineStyle = doc.querySelector("style");
      if (inlineStyle && !document.getElementById("app-bar-style")) {
        const st = document.createElement("style");
        st.id = "app-bar-style";
        st.textContent = inlineStyle.textContent;
        document.head.appendChild(st);
      }

      // Nav.app-bar
      const nav = doc.querySelector(APP_BAR_SEL);
      if (nav && !document.querySelector(APP_BAR_SEL)) {
        document.body.appendChild(nav.cloneNode(true));
      }

      mounted = true;
      initAppBar();
    } catch (e) {
      console.warn("[mobil_settings] app-bar yüklenemedi:", e);
    }
  }

  document.addEventListener("DOMContentLoaded", ensureAppBarMounted);
})();
