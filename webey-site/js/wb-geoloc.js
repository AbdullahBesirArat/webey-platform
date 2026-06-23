/**
 * wb-geoloc.js — Paylaşımlı konum alma modülü
 * profile.html, navbar.html gibi redirect-mode sayfalarda kullanılır.
 * Konum alınır → kuafor.html?il=X&ilce=Y&mahalle=Z adresine yönlendirilir.
 */

let _cache = null; // session içi cache

async function _fetchLocation() {
  if (_cache) return _cache;
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) { reject(new Error("no_geo")); return; }
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        try {
          const { latitude: lat, longitude: lon } = pos.coords;
          const res = await fetch(
            `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&accept-language=tr`,
            { headers: { "User-Agent": "Webey/1.0 (webey.com.tr)", "Accept": "application/json" } }
          );
          const data = await res.json();
          const addr = data.address || {};
          _cache = {
            il:      addr.province     || addr.city          || addr.state        || "",
            ilce:    addr.district     || addr.county        || addr.town         || addr.municipality || "",
            mahalle: addr.suburb       || addr.neighbourhood || addr.quarter      || addr.village      || "",
          };
          resolve(_cache);
        } catch (e) { reject(e); }
      },
      (err) => reject(err),
      { timeout: 10000, maximumAge: 60000 }
    );
  });
}

function _showToast(msg, type = "") {
  let t = document.getElementById("toast");
  if (!t) {
    t = document.createElement("div");
    t.id = "toast"; t.className = "toast";
    t.setAttribute("role", "status"); t.setAttribute("aria-live", "polite");
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.className = `toast${type ? " " + type : ""}`;
  t.classList.add("show");
  clearTimeout(_showToast._t);
  _showToast._t = setTimeout(() => t.classList.remove("show"), 3200);
}

/**
 * Sayfa konum butonlarını başlatır.
 * Konum alınınca kuafor.html?il=X&ilce=Y&mahalle=Z adresine yönlendirir.
 *
 * @param {Array<{btn: string, inputs: string[]}>} targets
 *   btn    — geo butonunun ID'si
 *   inputs — loading sırasında "Konum alınıyor…" yazılacak input ID'leri
 */
export function initGeoRedirect(targets = []) {
  if (location.protocol !== "https:" && location.hostname !== "localhost") {
    targets.forEach(({ btn }) => {
      const b = document.getElementById(btn);
      if (b) b.style.display = "none";
    });
    return;
  }

  for (const { btn: btnId, inputs: inputIds } of targets) {
    const btn = document.getElementById(btnId);
    if (!btn) continue;

    btn.addEventListener("click", async () => {
      if (!navigator.geolocation) {
        _showToast("Tarayıcınız konum desteklemiyor", "error");
        return;
      }

      const inputEls = inputIds.map(id => document.getElementById(id)).filter(Boolean);

      // Loading
      btn.disabled = true;
      btn.classList.add("loading");
      inputEls.forEach(el => { el.value = "Konum alınıyor…"; el.disabled = true; });

      try {
        const { il, ilce, mahalle } = await _fetchLocation();
        const url = new URL("kuafor.html", location.origin);
        if (il)      url.searchParams.set("il", il);
        if (ilce)    url.searchParams.set("ilce", ilce);
        if (mahalle) url.searchParams.set("mahalle", mahalle);
        location.href = url.pathname + url.search;
      } catch (err) {
        // Reset
        btn.disabled = false;
        btn.classList.remove("loading");
        inputEls.forEach(el => { el.value = ""; el.disabled = false; });

        if (err?.code === 1) {
          _showToast("Konum izni verilmedi, şehir seçin", "error");
        } else if (err?.message === "no_geo") {
          _showToast("Tarayıcınız konum desteklemiyor", "error");
        }
        // Ağ hatası / zaman aşımı: sessizce geç
      }
    });
  }
}
