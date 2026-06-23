// js/navbar-suggest.js — Firebase YOK, PHP API tabanlı
// Navbar autocomplete

const normalize = (s = '') =>
  s.toLocaleLowerCase('tr')
   .normalize('NFD')
   .replace(/[\u0300-\u036f]/g, '')
   .replace(/ı/g, 'i')
   .trim();

function makeDropdown(anchor) {
  const box = document.createElement('div');
  box.className = 'nav-suggest';
  Object.assign(box.style, {
    position: 'fixed', left: '0', top: '0', width: '0',
    background: 'var(--card, #fff)', color: 'inherit',
    border: '1px solid var(--border, #ececf0)', borderRadius: '12px',
    boxShadow: '0 10px 30px rgba(0,0,0,.12)', zIndex: '10000',
    display: 'none', overflow: 'hidden'
  });
  document.body.appendChild(box);

  const place = () => {
    const r = anchor.getBoundingClientRect();
    box.style.left  = `${r.left}px`;
    box.style.top   = `${r.bottom + 6}px`;
    box.style.width = `${r.width}px`;
  };
  const show = () => { place(); box.style.display = 'block'; };
  const hide = () => { box.style.display = 'none'; };
  const render = (items = []) => {
    box.innerHTML = items.map(it =>
      `<button class="nav-sg-row" data-q="${it.q}" style="
        width:100%;text-align:left;border:0;background:transparent;padding:10px 12px;cursor:pointer">
        <div style="font-weight:800">${it.t}</div>
        ${it.s ? `<div style="font-size:12px;opacity:.7">${it.s}</div>` : ''}
      </button>`
    ).join('');
    box.querySelectorAll('.nav-sg-row').forEach(btn => {
      btn.addEventListener('click', () => goSearch({ q: btn.dataset.q }));
    });
  };

  window.addEventListener('scroll', () => { if (box.style.display !== 'none') place(); }, { passive: true });
  window.addEventListener('resize', () => { if (box.style.display !== 'none') place(); }, { passive: true });
  document.addEventListener('click', (e) => {
    if (e.target !== anchor && !box.contains(e.target)) hide();
  });

  return { show, hide, render, place, el: box };
}

function goSearch({ q, loc, whenIso }) {
  const url = new URL('kuafor.html', location.origin);
  if (q) url.searchParams.set('q', q);
  if (loc) url.searchParams.set('loc', loc);
  if (whenIso) url.searchParams.set('when', whenIso);
  location.href = url.pathname + (url.search || '');
}

async function fetchSuggestions(term) {
  try {
    const t = normalize(term);
    if (!t) return [];
    const res = await fetch(`/api/public/suggest.php?q=${encodeURIComponent(t)}`, { credentials: 'same-origin' });
    if (!res.ok) return [];
    const json = await res.json();
    return (json.data || []).map(x => ({
      t: x.name || x.title || '',
      s: x.type === 'business' ? 'İşletme' : 'Hizmet',
      q: x.name || '',
    }));
  } catch {
    return [];
  }
}

function attachNavbarSuggest() {
  const qInput   = document.getElementById('navQuery');
  const locInput = document.getElementById('navLoc');
  const whenInput = document.getElementById('whenNavInput');
  if (!qInput) return;

  const dd = makeDropdown(qInput);

  const tryGo = (e) => {
    if (e.key === 'Enter') {
      const whenIso = whenInput?.dataset?.whenIso || '';
      goSearch({ q: qInput.value.trim(), loc: locInput?.value.trim(), whenIso });
    }
  };
  qInput.addEventListener('keydown', tryGo);
  locInput?.addEventListener('keydown', tryGo);

  let tId = null;
  qInput.addEventListener('input', () => {
    clearTimeout(tId);
    const term = qInput.value.trim();
    if (!term) { dd.hide(); return; }
    tId = setTimeout(async () => {
      const list = await fetchSuggestions(term);
      const items = list.length
        ? list
        : [{ t: `"${term}" için ara`, s: 'Kuaförler ve hizmetler', q: term }];
      dd.render(items);
      dd.show();
    }, 120);
  });

  qInput.addEventListener('focus', () => {
    if (qInput.value.trim()) dd.show();
  });
}

// CSS
(function injectCss() {
  const css = `
  .nav-suggest .nav-sg-row:hover{ background:rgba(0,0,0,.04) }
  @media (prefers-color-scheme: dark){
    .nav-suggest{ background:#13151a; border-color:#2a2f38 }
    .nav-suggest .nav-sg-row:hover{ background:rgba(255,255,255,.06) }
  }`;
  const s = document.createElement('style');
  s.textContent = css;
  document.head.appendChild(s);
})();

document.addEventListener('navbar:ready', attachNavbarSuggest);
if (document.readyState !== 'loading') attachNavbarSuggest();