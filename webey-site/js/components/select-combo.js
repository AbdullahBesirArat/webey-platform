// js/components/select-combo.js
// TürkiyeAPI ile şehir → ilçe → mahalle zinciri
// - Doğru domain: https://turkiyeapi.dev/api/v1
// - localStorage cache (1 gün) + versiyonlu anahtarlar
// - AbortController + timeout
// - Erişilebilir "yükleniyor" durumu
// - Fallback: veri alınamazsa "Merkez" veya minimal İstanbul-Ümraniye listesi
// - Tekrarlı attach koruması + seçili değeri mümkünse korur

const API = "https://turkiyeapi.dev/api/v1";
const ONE_DAY = 24 * 60 * 60 * 1000;
const CACHE_VER = "v1"; // şema/normalize değişirse artır

/* ============ küçük yardımcılar ============ */
const norm = (s = "") =>
  String(s)
    .trim()
    .replace(/[İIı]/g, "i")
    .replace(/[Şş]/g, "s")
    .replace(/[Çç]/g, "c")
    .replace(/[Ğğ]/g, "g")
    .replace(/[Öö]/g, "o")
    .replace(/[Üü]/g, "u")
    .toLowerCase();

const byTR = (a, b) => a.localeCompare(b, "tr", { sensitivity: "base" });

function cacheKey(k) { return `select-combo:${CACHE_VER}:${k}`; }

const cacheGet = (k) => {
  try {
    const raw = localStorage.getItem(cacheKey(k));
    if (!raw) return null;
    const { t, v } = JSON.parse(raw);
    if (Date.now() - t > ONE_DAY) { localStorage.removeItem(cacheKey(k)); return null; }
    return v;
  } catch { return null; }
};
const cacheSet = (k, v) => { try { localStorage.setItem(cacheKey(k), JSON.stringify({ t: Date.now(), v })); } catch {} };
const cached = async (k, fn) => { const c = cacheGet(k); if (c) return c; const v = await fn(); cacheSet(k, v); return v; };

async function fetchJSON(url, { timeout = 8000 } = {}) {
  const ctl = new AbortController();
  const to = setTimeout(() => ctl.abort(), timeout);
  try {
    const r = await fetch(url, { credentials: "omit", cache: "force-cache", signal: ctl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const j = await r.json().catch(() => ({}));
    return j?.data || j?.results || [];
  } finally {
    clearTimeout(to);
  }
}

/* ============ UI helpers ============ */
function setLoadingState(sel, isLoading, placeholderText) {
  if (!sel) return;
  sel.disabled = true;
  if (isLoading) {
    sel.setAttribute("aria-busy", "true");
    sel.innerHTML = `<option value="" selected disabled>${placeholderText || "Yükleniyor..."}</option>`;
  } else {
    sel.removeAttribute("aria-busy");
  }
}

function fillSelect(sel, items, placeholder, keepValue = true) {
  if (!sel) return;
  const prev = keepValue ? (sel.value || "") : "";
  sel.innerHTML = `<option value="" selected disabled>${placeholder}</option>`;

  const toName = (o) =>
    (typeof o === "string"
      ? o
      : (o.name || o.ilce_adi || o.ilce || o.mahalle_adi || o.mahalle || "")).trim();

  items.forEach((it) => {
    const name = toName(it);
    if (!name) return;
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = name;
    sel.appendChild(opt);
  });

  sel.disabled = false;

  if (keepValue && prev) {
    // Önce birebir eşleşme, yoksa normalize ile eşleşme
    const exact = Array.from(sel.options).find((o) => o.value === prev);
    if (exact) {
      sel.value = prev;
    } else {
      const prevN = norm(prev);
      const near = Array.from(sel.options).find((o) => norm(o.value) === prevN);
      if (near) sel.value = near.value;
    }
  }
}

/* ============ Ana bağlayıcı ============ */
export async function attachTRLocationCombo({ citySelect, districtSelect, neighborhoodSelect } = {}) {
  if (!citySelect || !districtSelect || !neighborhoodSelect) return;

  // Aynı select setine ikinci kez bağlanmayalım
  if (citySelect.dataset.comboReady === "1") return;
  citySelect.dataset.comboReady = "1";

  // Başlangıç: placeholder ve disable
  setLoadingState(citySelect, true, "Şehirler yükleniyor…");
  setLoadingState(districtSelect, false);
  setLoadingState(neighborhoodSelect, false);
  fillSelect(districtSelect, [], "İlçe seçin", false);
  fillSelect(neighborhoodSelect, [], "Mahalle seçin", false);

  // 1) Şehirler
  try {
    const provinces = await cached("provinces", () => fetchJSON(`${API}/provinces`));
    const list = (provinces || [])
      .map((p) => p?.name || p)
      .filter(Boolean)
      .sort(byTR);
    fillSelect(citySelect, list, "Şehir seçin", true);
  } catch {
    // Minimal fallback
    fillSelect(citySelect, ["İstanbul"], "Şehir seçin", true);
  } finally {
    citySelect.removeAttribute("aria-busy");
  }

  // 2) İlçe (şehir seçildiğinde)
  citySelect.addEventListener("change", async () => {
    const city = citySelect.value;
    setLoadingState(districtSelect, true, "İlçeler yükleniyor…");
    setLoadingState(neighborhoodSelect, false);
    fillSelect(neighborhoodSelect, [], "Mahalle seçin", false);

    try {
      const districts = await cached(`districts:${city}`, () =>
        fetchJSON(`${API}/districts?province=${encodeURIComponent(city)}`)
      );
      const list = (districts || [])
        .map((d) => d?.name || d)
        .filter(Boolean)
        .sort(byTR);

      if (list.length) {
        fillSelect(districtSelect, list, "İlçe seçin", false);
      } else {
        throw new Error("empty");
      }
    } catch {
      if (norm(city) === norm("İstanbul")) {
        fillSelect(
          districtSelect,
          ["Ümraniye", "Kadıköy", "Ataşehir", "Üsküdar", "Beşiktaş", "Şişli", "Beyoğlu", "Bakırköy", "Sarıyer"],
          "İlçe seçin",
          false
        );
      } else {
        fillSelect(districtSelect, ["Merkez"], "İlçe seçin", false);
      }
    } finally {
      districtSelect.removeAttribute("aria-busy");
    }
  });

  // 3) Mahalle (ilçe seçildiğinde)
  districtSelect.addEventListener("change", async () => {
    const city = citySelect.value;
    const district = districtSelect.value;

    setLoadingState(neighborhoodSelect, true, "Mahalleler yükleniyor…");

    try {
      const nbs = await cached(`neighborhoods:${city}:${district}`, () =>
        fetchJSON(
          `${API}/neighborhoods?province=${encodeURIComponent(city)}&district=${encodeURIComponent(district)}`
        )
      );

      // TürkiyeAPI farklı alanlarda isim döndürebilir → normalize et
      const uniq = Array.from(
        new Set(
          (nbs || [])
            .map((x) => (x?.name || x?.mahalle || x?.neighborhood || "").trim())
            .filter(Boolean)
        )
      ).sort(byTR);

      if (uniq.length) {
        fillSelect(neighborhoodSelect, uniq, "Mahalle seçin", false);
      } else {
        throw new Error("empty");
      }
    } catch {
      // Minimal ve güvenli fallback
      const FB = {
        "İstanbul": {
          "Ümraniye": [
            "Atakent",
            "Armağanevler",
            "Aşağı Dudullu",
            "Yukarı Dudullu",
            "Tatlısu",
            "Ihlamurkuyu",
            "Çakmak",
            "Esenkent",
            "Huzur",
          ],
        },
      };
      const list = FB[city]?.[district] || ["Merkez"];
      fillSelect(neighborhoodSelect, list, "Mahalle seçin", false);
    } finally {
      neighborhoodSelect.removeAttribute("aria-busy");
    }
  });

  // Eğer sayfa yüklenirken select’lerde değer varsa (prefill), tetikle
  if (citySelect.value) {
    // şehir seçiliyse ilçe listesini çek
    citySelect.dispatchEvent(new Event("change"));
    // ilçe değeri varsa, mahalleyi de tetiklemek için küçük gecikme
    if (districtSelect.value) {
      setTimeout(() => districtSelect.dispatchEvent(new Event("change")), 80);
    }
  }
}
