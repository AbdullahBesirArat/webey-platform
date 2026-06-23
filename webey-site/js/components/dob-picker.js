// components/dob-picker.js
// Takvim tipi doğum tarihi seçici
// Ay/yıl dropdown + ileri geri ok + 7 günlük ızgara

export function attachDOBPicker({
  input,
  years = { min: new Date().getFullYear() - 100, max: new Date().getFullYear() },
  locale = "tr",
  format = "yyyy-MM-dd",
} = {}) {
  if (!input) return;
  if (input.dataset.dobReady === "1") return;
  input.dataset.dobReady = "1";

  if (typeof years?.min === "number" && typeof years?.max === "number" && years.min > years.max) {
    const t = years.min; years.min = years.max; years.max = t;
  }

  input.readOnly = true;
  input.setAttribute("role", "button");
  input.setAttribute("aria-haspopup", "dialog");
  input.setAttribute("aria-expanded", "false");

  input.addEventListener("keydown", (e) => {
    if (!["Enter", " ", "ArrowDown", "ArrowUp", "Tab"].includes(e.key)) e.preventDefault();
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openPicker(); }
  });
  input.addEventListener("click", openPicker);

  const isNativeDate = input.type === "date";
  const effectiveFormat = isNativeDate ? "yyyy-MM-dd" : format;

  const MONTHS_LONG = ["Ocak","Şubat","Mart","Nisan","Mayıs","Haziran",
                        "Temmuz","Ağustos","Eylül","Ekim","Kasım","Aralık"];
  const DAYS_SHORT  = ["Pzt","Sal","Çar","Per","Cum","Cmt","Paz"];

  const today = new Date();
  let selY = null, selM = null, selD = null;
  let viewY, viewM;

  const parsed = parseExisting(input.value);
  if (parsed) {
    selY = parsed.y; selM = parsed.m; selD = parsed.d;
    viewY = selY; viewM = selM;
  } else {
    viewY = clamp(today.getFullYear() - 18, years.min, years.max);
    viewM = today.getMonth() + 1;
  }

  let overlay = null;
  let _addedNoScroll = false;
  let lastFocused = null;

  function openPicker() {
    if (overlay?.isConnected) return;
    lastFocused = document.activeElement;
    buildUI();
    input.setAttribute("aria-expanded", "true");
    document.body.appendChild(overlay);
    _addedNoScroll = !document.body.classList.contains("no-scroll");
    if (_addedNoScroll) document.body.classList.add("no-scroll");
  }

  function closePicker() {
    overlay?.remove();
    overlay = null;
    if (_addedNoScroll) { document.body.classList.remove("no-scroll"); _addedNoScroll = false; }
    input.setAttribute("aria-expanded", "false");
    if (lastFocused?.focus) lastFocused.focus();
  }

  function confirmDate() {
    if (!selY || !selM || !selD) return;
    if (isNativeDate) {
      input.value = isoYYYYMMDD(selY, selM, selD);
      try {
        const d = new Date(selY, selM - 1, selD);
        input.valueAsDate = d;
      } catch(_) {}
    } else {
      input.value = fmtDate(selY, selM, selD, effectiveFormat);
    }
    input.dispatchEvent(new Event("input",  { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    closePicker();
  }

  function buildUI() {
    overlay = mkEl("div", { class: "dobp-overlay", role: "dialog", "aria-modal": "true" });
    overlay.style.zIndex = "2147483647";
    overlay.addEventListener("click", e => { if (e.target === overlay) closePicker(); });
    overlay.addEventListener("keydown", e => {
      if (e.key === "Escape") { e.preventDefault(); closePicker(); }
      if (e.key === "Tab") trapTab(overlay, e);
    });

    const box = mkEl("div", { class: "dobp-box dobcal-box" });
    const head = mkEl("div", { class: "dobp-head" }, mkTxt("Doğum tarihi seç"));

    // Nav
    const nav = mkEl("div", { class: "dobcal-nav" });
    const btnPrev = mkEl("button", { class: "dobcal-arrow", type: "button", "aria-label": "Önceki ay" }, mkTxt("‹"));
    const btnNext = mkEl("button", { class: "dobcal-arrow", type: "button", "aria-label": "Sonraki ay" }, mkTxt("›"));

    const selMonth = mkEl("select", { class: "dobcal-select", "aria-label": "Ay" });
    MONTHS_LONG.forEach((name, i) => {
      const opt = mkEl("option", { value: String(i + 1) }, mkTxt(name));
      if (i + 1 === viewM) opt.selected = true;
      selMonth.appendChild(opt);
    });

    const selYear = mkEl("select", { class: "dobcal-select", "aria-label": "Yıl" });
    for (let y = years.max; y >= years.min; y--) {
      const opt = mkEl("option", { value: String(y) }, mkTxt(String(y)));
      if (y === viewY) opt.selected = true;
      selYear.appendChild(opt);
    }

    function syncSelects() {
      selMonth.value = String(viewM);
      selYear.value  = String(viewY);
    }

    function navigate(delta) {
      viewM += delta;
      if (viewM > 12) { viewM = 1;  viewY++; }
      if (viewM < 1)  { viewM = 12; viewY--; }
      viewY = clamp(viewY, years.min, years.max);
      syncSelects();
      renderGrid();
    }

    btnPrev.addEventListener("click", () => navigate(-1));
    btnNext.addEventListener("click", () => navigate(+1));
    selMonth.addEventListener("change", () => { viewM = +selMonth.value; renderGrid(); });
    selYear.addEventListener("change",  () => { viewY = +selYear.value;  renderGrid(); });

    nav.append(btnPrev, selMonth, selYear, btnNext);

    // Gün isimleri
    const headers = mkEl("div", { class: "dobcal-headers" });
    DAYS_SHORT.forEach(d => headers.appendChild(mkEl("span", { class: "dobcal-dh" }, mkTxt(d))));

    // Grid
    const grid = mkEl("div", { class: "dobcal-grid", role: "grid" });

    // Actions
    const actions = mkEl("div", { class: "dobp-actions" });
    const btnCancel = mkEl("button", { class: "btn-ghost", type: "button" }, mkTxt("İptal"));
    const btnOk     = mkEl("button", { class: "auth-btn",  type: "button", style: "min-width:130px" }, mkTxt("Ayarla"));
    btnCancel.addEventListener("click", closePicker);
    btnOk.addEventListener("click", confirmDate);
    actions.append(btnCancel, btnOk);

    box.append(head, nav, headers, grid, actions);
    overlay.append(box);

    function renderGrid() {
      grid.innerHTML = "";

      const firstDow  = new Date(viewY, viewM - 1, 1).getDay(); // 0=Paz
      const startOff  = (firstDow + 6) % 7; // Pzt bazlı
      const dim       = new Date(viewY, viewM, 0).getDate();
      const prevDim   = new Date(viewY, viewM - 1, 0).getDate();

      // Önceki ay solma
      for (let i = startOff - 1; i >= 0; i--) {
        grid.appendChild(mkDayCell(prevDim - i, false, true));
      }

      // Bu ay
      for (let d = 1; d <= dim; d++) {
        const isSel   = selY === viewY && selM === viewM && selD === d;
        const isToday = today.getFullYear() === viewY && today.getMonth() + 1 === viewM && today.getDate() === d;
        const isOOR   = isOutOfRange(viewY, viewM, d);
        const cell    = mkDayCell(d, true, false, isSel, isToday, isOOR);
        if (!isOOR) {
          cell.addEventListener("click", () => {
            selY = viewY; selM = viewM; selD = d;
            renderGrid();
          });
        }
        grid.appendChild(cell);
      }

      // Sonraki ay solma
      const total    = startOff + dim;
      const trailing = total % 7 === 0 ? 0 : 7 - (total % 7);
      for (let i = 1; i <= trailing; i++) {
        grid.appendChild(mkDayCell(i, false, true));
      }

      // Ok limitler
      btnPrev.disabled = (viewY <= years.min && viewM <= 1);
      btnNext.disabled = (viewY >= years.max && viewM >= 12);

      syncSelects();
    }

    renderGrid();
  }

  /* ── Yardımcılar ── */
  function mkDayCell(num, active, faded, selected = false, isToday = false, disabled = false) {
    const cls = ["dobcal-day"];
    if (faded)    cls.push("dobcal-day--faded");
    if (selected) cls.push("dobcal-day--selected");
    if (isToday && !selected) cls.push("dobcal-day--today");
    if (disabled) cls.push("dobcal-day--disabled");

    const btn = document.createElement("button");
    btn.className = cls.join(" ");
    btn.type = "button";
    btn.textContent = String(num);
    if (!active || disabled) btn.tabIndex = -1;
    if (disabled) btn.disabled = true;
    return btn;
  }

  function isOutOfRange(y, m, d) {
    const ts  = new Date(y, m - 1, d).getTime();
    const min = new Date(years.min, 0, 1).getTime();
    const max = new Date(years.max, 11, 31).getTime();
    return ts < min || ts > max;
  }

  function fmtDate(y, m, d, fmt) {
    const p = n => String(n).padStart(2, "0");
    return fmt.replace("yyyy", y).replace("MM", p(m)).replace("dd", p(d));
  }

  function isoYYYYMMDD(y, m, d) {
    const p = n => String(n).padStart(2, "0");
    return `${y}-${p(m)}-${p(d)}`;
  }

  function parseExisting(v) {
    if (!v) return null;
    let r = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(v);
    if (r) return { d: +r[1], m: +r[2], y: +r[3] };
    r = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
    if (r) return { y: +r[1], m: +r[2], d: +r[3] };
    return null;
  }

  function mkEl(tag, attrs = {}, ...children) {
    const n = document.createElement(tag);
    for (const k in attrs) n.setAttribute(k, attrs[k]);
    children.forEach(c => n.appendChild(c));
    return n;
  }
  function mkTxt(s) { return document.createTextNode(s); }
  function clamp(v, a, b) { return Math.min(Math.max(v, a), b); }

  function trapTab(container, e) {
    const sel = "button:not([disabled]),select,[tabindex]:not([tabindex='-1'])";
    const list = Array.from(container.querySelectorAll(sel));
    if (!list.length) return;
    const first = list[0], last = list[list.length - 1];
    if (e.shiftKey) { if (document.activeElement === first) { e.preventDefault(); last.focus(); } }
    else            { if (document.activeElement === last)  { e.preventDefault(); first.focus(); } }
  }
}