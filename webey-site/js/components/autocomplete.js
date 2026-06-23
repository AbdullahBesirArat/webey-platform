// js/components/autocomplete.js
// Viewport-anchored, accessible autocomplete dropdown (fixed panel + smart reposition)

export function attachAutocomplete(input, {
  fetcher,          // async (q) => Promise<{sections: [{title?, items:[{id,label,subtitle?,icon?,onSelect?}]}]}>
  minLength = 1,
  debounceMs = 120,
  maxHeightVh = 60,
  closeOnOutside = true,
  closeOnEsc = true,
  closeOnEnterWhenEmpty = true,
  zIndex = 4600,    // navbar ve modallardan aşağı/yukarı ayarla (index.css z'lerine göre)
} = {}) {
  if (!input || typeof fetcher !== "function") return;
  if (input.dataset.acReady === "1") return; // idempotent
  input.dataset.acReady = "1";

  /* ---------- helpers ---------- */
  const $ = (s, r=document) => r.querySelector(s);
  const escHtml = s => String(s||"").replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const isMobile = () => matchMedia("(max-width:860px)").matches;

  let panel, listWrap, currentItems = [], activeIndex = -1, open = false;
  let rafId = 0, debTimer = 0;

  // Build panel once
  function ensurePanel(){
    if (panel) return;
    panel = document.createElement("div");
    panel.className = "ac-panel";
    panel.setAttribute("role", "listbox");
    panel.style.zIndex = String(zIndex);
    panel.style.maxHeight = `${maxHeightVh}vh`;

    listWrap = document.createElement("div");
    listWrap.className = "ac-content";
    panel.appendChild(listWrap);
  }

  function mount(){
    ensurePanel();
    if (!panel.isConnected) document.body.appendChild(panel);
    position();
    panel.hidden = false;
    open = true;
    input.setAttribute("aria-expanded", "true");
  }
  function unmount(){
    if (!panel) return;
    panel.hidden = true;
    open = false;
    input.setAttribute("aria-expanded", "false");
    activeIndex = -1;
  }

  function position(){
    cancelAnimationFrame(rafId);
    rafId = requestAnimationFrame(() => {
      const r = input.getBoundingClientRect();
      const pad = 4;
      // mobile: ekranda taşma olmasın → genişlik viewport’a göre kısalır
      const vw = Math.max(document.documentElement.clientWidth, window.innerWidth || 0);
      panel.style.position = "fixed";
      panel.style.left = Math.max(8, r.left) + "px";
      panel.style.top  = (r.bottom + pad) + "px";
      const maxWidth = vw - 16; // 8px sağ-sol güvenlik
      panel.style.width = Math.min(r.width, maxWidth) + "px";
    });
  }

  function render(data){
    // data: {sections:[{title?,items:[...] }]}
    listWrap.innerHTML = "";
    currentItems = [];
    let idx = 0;

    (data?.sections || []).forEach(sec=>{
      if (sec.title){
        const h = document.createElement("div");
        h.className = "ac-section";
        h.textContent = sec.title;
        listWrap.appendChild(h);
      }
      (sec.items || []).forEach(it=>{
        const row = document.createElement("button");
        row.type = "button";
        row.className = "ac-row";
        row.setAttribute("role","option");
        row.setAttribute("data-index", String(idx));

        row.innerHTML = `
          <span class="ac-ico">${escHtml(it.icon || "🔎")}</span>
          <span class="ac-main">
            <span class="ac-label">${escHtml(it.label || "")}</span>
            ${it.subtitle ? `<span class="ac-sub">${escHtml(it.subtitle)}</span>` : ""}
          </span>
        `;
        row.addEventListener("click", ()=>select(idx));
        row.addEventListener("mousemove", ()=>highlight(idx));
        listWrap.appendChild(row);
        currentItems.push(it);
        idx++;
      });
    });

    if (currentItems.length === 0) {
      const empty = document.createElement("div");
      empty.className = "ac-empty";
      empty.textContent = "Sonuç yok";
      listWrap.appendChild(empty);
    }

    // reset active
    activeIndex = -1;
    updateActive();
  }

  function highlight(i){
    activeIndex = i;
    updateActive();
  }
  function updateActive(){
    listWrap.querySelectorAll(".ac-row").forEach(el => el.classList.remove("is-active"));
    if (activeIndex >= 0){
      const el = listWrap.querySelector(`.ac-row[data-index="${activeIndex}"]`);
      el?.classList.add("is-active");
      // ensure visible
      const wrapRect = listWrap.getBoundingClientRect();
      const rowRect = el.getBoundingClientRect();
      if (rowRect.bottom > wrapRect.bottom) el.scrollIntoView({ block:"nearest" });
      if (rowRect.top < wrapRect.top) el.scrollIntoView({ block:"nearest" });
    }
  }

  function select(i){
    const it = currentItems[i];
    if (!it) return;
    // input doldur + onSelect
    input.value = it.label || input.value;
    input.dispatchEvent(new Event("input",{bubbles:true}));
    input.dispatchEvent(new Event("change",{bubbles:true}));
    try{ it.onSelect?.(it, input); }catch{}
    unmount();
  }

  async function query(q){
    if (!q || q.length < minLength){ unmount(); return; }
    try{
      const data = await fetcher(q);
      render(data);
      mount();
    }catch(e){
      // sessiz fail + paneli kapat
      unmount();
      // console.warn("[autocomplete] fetcher error:", e);
    }
  }

  /* ---------- Events ---------- */
  input.setAttribute("autocomplete","off");
  input.setAttribute("aria-haspopup","listbox");
  input.setAttribute("aria-expanded","false");

  input.addEventListener("input", ()=>{
    clearTimeout(debTimer);
    const val = input.value.trim();
    debTimer = setTimeout(()=> query(val), debounceMs);
  });

  input.addEventListener("focus", ()=>{
    // mevcut değerle yeniden konumla + isteğe bağlı aç
    if (panel && open) position();
  });

  // Klavye
  input.addEventListener("keydown", (e)=>{
    if (!open){
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && input.value.trim().length >= minLength){
        e.preventDefault();
        query(input.value.trim());
      }
      return;
    }
    if (e.key === "Escape" && closeOnEsc){ e.preventDefault(); unmount(); return; }
    if (e.key === "ArrowDown"){ e.preventDefault(); highlight(Math.min(activeIndex+1, currentItems.length-1)); }
    else if (e.key === "ArrowUp"){ e.preventDefault(); highlight(Math.max(activeIndex-1, 0)); }
    else if (e.key === "Enter"){
      if (activeIndex >= 0){ e.preventDefault(); select(activeIndex); }
      else if (closeOnEnterWhenEmpty){ unmount(); }
    }
  });

  // Panel açıkken viewport değişimleri → yeniden konumla
  const onWin = ()=> { if (open) position(); };
  window.addEventListener("scroll", onWin, true); // capture true: herhangi bir scroll’da tetiklensin
  window.addEventListener("resize", onWin);
  new ResizeObserver(()=> onWin()).observe(input);

  // Dış tık
  document.addEventListener("pointerdown", (e)=>{
    if (!open || !closeOnOutside) return;
    if (e.target === input) return;
    if (panel && panel.contains(e.target)) return;
    unmount();
  });

  // Input blur → dış tıkla zaten kapanıyor; klavye ile sekmede kalması için otomatik kapatma yapmıyoruz

  // Mobile soft keyboard hareketi için periyodik konum güncelleme (çok hafif)
  let rafTicker = 0;
  function tick() {
    if (!open) return;
    position();
    rafTicker = requestAnimationFrame(tick);
  }
  input.addEventListener("focus", ()=>{ if (isMobile()) { cancelAnimationFrame(rafTicker); rafTicker = requestAnimationFrame(tick); } });
  input.addEventListener("blur",  ()=>{ cancelAnimationFrame(rafTicker); });

  // public API (gerekirse dışarıdan da kapatılabilsin)
  return {
    close: unmount,
    open: ()=> { if (input.value.trim().length >= minLength) query(input.value.trim()); },
    rerender: render,
    reposition: position
  };
}
