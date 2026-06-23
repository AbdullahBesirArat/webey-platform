// Booksy benzeri tarih + saat modalı
const DOW = ["Paz","Pts","Sal","Çar","Per","Cum","Cts"];

function pad(n){ return String(n).padStart(2,"0"); }

function monthMatrix(y,m){ // m:0..11
  const first = new Date(y,m,1).getDay(); // 0=Sun
  const days = new Date(y,m+1,0).getDate();
  const grid = [];
  let row = [];
  for(let i=0;i<first;i++) row.push(null);
  for(let d=1; d<=days; d++){
    row.push(d);
    if(row.length===7){ grid.push(row); row=[]; }
  }
  if(row.length) { while(row.length<7) row.push(null); grid.push(row); }
  return grid;
}

function ensureStyles(){
  if(document.getElementById("whenStyles")) return;
  const css = `
  .when-ov{position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;z-index:10000}
  .when-md{width:min(92vw,640px);background:#fff;border-radius:16px;padding:18px;box-shadow:0 10px 40px rgba(0,0,0,.25)}
  .when-h{font-weight:800;font-size:22px;margin:4px 0 12px}
  .cal{border:1px solid #e5e7eb;border-radius:12px;padding:10px}
  .cal-h{display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;font-weight:700}
  .cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:6px}
  .cal-grid .dow{opacity:.6;text-align:center;font-size:12px}
  .cal-grid .d{height:36px;display:flex;align-items:center;justify-content:center;border-radius:10px;cursor:pointer}
  .cal-grid .d.disabled{opacity:.35;cursor:not-allowed}
  .cal-grid .d.sel{background:#1677ff;color:#fff}
  .tm-wrap{margin-top:10px;display:flex;flex-wrap:wrap;gap:8px;max-height:160px;overflow:auto}
  .tm{min-width:68px;padding:8px 10px;border:1px solid #e5e7eb;border-radius:10px;text-align:center;cursor:pointer}
  .tm.sel{background:#1677ff;color:#fff;border-color:#1677ff}
  .when-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}
  .btn{appearance:none;border:0;border-radius:10px;padding:10px 14px;font-weight:700}
  .btn.cancel{background:#eef2f7}
  .btn.ok{background:#1677ff;color:#fff}
  `;
  const style = document.createElement("style");
  style.id = "whenStyles";
  style.textContent = css;
  document.head.appendChild(style);
}

export function openWhenModal({ initial=new Date(), stepMin=15, minDate=new Date(), onApply }){
  ensureStyles();
  const ov = document.createElement("div");
  ov.className = "when-ov";
  ov.innerHTML = `
  <div class="when-md" role="dialog" aria-modal="true" aria-label="Ne zaman?">
    <div class="when-h">Ne zaman?</div>
    <div class="cal">
      <div class="cal-h">
        <button class="btn cancel nav prev" type="button">◀</button>
        <div class="title"></div>
        <button class="btn cancel nav next" type="button">▶</button>
      </div>
      <div class="cal-grid"></div>
    </div>
    <div class="tm-wrap"></div>
    <div class="when-actions">
      <button class="btn cancel">Kapat</button>
      <button class="btn ok">Seç ve Ara</button>
    </div>
  </div>`;
  document.body.appendChild(ov);

  const title = ov.querySelector(".title");
  const grid  = ov.querySelector(".cal-grid");
  const times = ov.querySelector(".tm-wrap");
  const btnOk = ov.querySelector(".ok");

  let viewY = initial.getFullYear();
  let viewM = initial.getMonth();
  let selDate = new Date(initial.getFullYear(), initial.getMonth(), initial.getDate());
  let selTime = `${pad(initial.getHours())}:${pad(initial.getMinutes())}`;

  function renderCalendar(){
    grid.innerHTML = "";
    title.textContent = selDate.toLocaleString("tr-TR",{month:"long",year:"numeric"});
    // DOW başlık
    DOW.forEach(d => {
      const el = document.createElement("div");
      el.textContent = d;
      el.className = "dow";
      grid.appendChild(el);
    });
    // Günler
    const mat = monthMatrix(viewY, viewM);
    const nowMid = new Date(minDate.getFullYear(), minDate.getMonth(), minDate.getDate()).getTime();
    mat.flat().forEach((d,i)=>{
      const el = document.createElement("div");
      el.className = "d";
      if(d===null){ el.classList.add("disabled"); el.style.visibility="hidden"; }
      else{
        el.textContent = d;
        const cur = new Date(viewY, viewM, d);
        const disabled = cur.getTime() < nowMid;
        if(disabled) el.classList.add("disabled");
        if(cur.getTime() === selDate.getTime()) el.classList.add("sel");
        el.addEventListener("click", ()=>{
          if(disabled) return;
          selDate = cur;
          renderCalendar();
          renderTimes();
        });
      }
      grid.appendChild(el);
    });
  }

  function renderTimes(){
    times.innerHTML = "";
    const start = 8*60, end = 21*60; // 08:00 - 21:00
    for(let m=start; m<=end; m+=stepMin){
      const hh = Math.floor(m/60), mm = m%60;
      const t = `${pad(hh)}:${pad(mm)}`;
      const b = document.createElement("button");
      b.type="button"; b.className="tm";
      b.textContent = t;
      if(t===selTime) b.classList.add("sel");
      b.addEventListener("click", ()=>{
        selTime = t;
        times.querySelectorAll(".tm").forEach(x=>x.classList.toggle("sel", x===b));
      });
      times.appendChild(b);
    }
  }

  renderCalendar(); renderTimes();

  ov.querySelector(".nav.prev").addEventListener("click", ()=>{
    const d = new Date(viewY, viewM-1, 1);
    viewY=d.getFullYear(); viewM=d.getMonth(); renderCalendar();
  });
  ov.querySelector(".nav.next").addEventListener("click", ()=>{
    const d = new Date(viewY, viewM+1, 1);
    viewY=d.getFullYear(); viewM=d.getMonth(); renderCalendar();
  });

  ov.querySelector(".cancel").addEventListener("click", ()=> ov.remove());
  btnOk.addEventListener("click", ()=>{
    const iso = `${selDate.getFullYear()}-${pad(selDate.getMonth()+1)}-${pad(selDate.getDate())}T${selTime}`;
    onApply?.({ iso, date: selDate, time: selTime });
    ov.remove();
  });
}
