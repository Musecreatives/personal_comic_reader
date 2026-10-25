// Landing page behaviour: theme, stamp rally, chapter toys, noren curtain,
// ink trail, lantern, cursor, downloads and the invite ticket.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const root = document.documentElement;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const store = {
    get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} },
  };
  const css = (name) => getComputedStyle(root).getPropertyValue(name).trim();

  // ---- Theme: system, light, dark
  const themes = [['system', 'i-auto', 'follow system'], ['light', 'i-sun', 'Washi (light)'], ['dark', 'i-moon', 'Midnight (dark)']];
  let ti = Math.max(0, themes.findIndex((t) => t[0] === store.get('sr-theme', 'system')));
  const themeBtn = $('#theme');
  function applyTheme() {
    const [name, icon, label] = themes[ti];
    if (name === 'system') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', name);
    themeBtn.innerHTML = `<svg><use href="#${icon}"/></svg>`;
    themeBtn.setAttribute('aria-label', 'Theme: ' + label);
    store.set('sr-theme', name);
    dispatchEvent(new Event('themechange'));
  }
  themeBtn.addEventListener('click', () => { ti = (ti + 1) % themes.length; applyTheme(); });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => dispatchEvent(new Event('themechange')));
  applyTheme();


  // ---- Chapter nav highlight
  const links = $$('.chapters a');
  const io = new IntersectionObserver((es) => es.forEach((e) => {
    if (e.isIntersecting) links.forEach((a) => a.classList.toggle('on', a.getAttribute('href') === '#' + e.target.id));
  }), { rootMargin: '-45% 0px -50% 0px' });
  $$('.chapter').forEach((s) => io.observe(s));

  // ---- Stamp rally
  const found = new Set(store.get('sr-stamps', []));
  const restamp = (el) => { el.classList.remove('stamp-in'); void el.offsetWidth; el.classList.add('stamp-in'); };
  function renderStamps(justGot) {
    $$('.slot').forEach((s) => {
      const i = +s.dataset.slot;
      s.classList.toggle('got', found.has(i));
      if (i === justGot) restamp(s);
    });
    $$('.sfx').forEach((b) => b.classList.toggle('got', found.has(+b.dataset.sfx)));
    const n = found.size;
    $('#card-text').textContent = n === 3 ? 'Card complete. See the last chapter.' : n ? `${n} of 3 found. Keep reading.` : 'Find the sound effect in each chapter';
    const rev = $('#reveal'), was = rev.classList.contains('on');
    rev.classList.toggle('on', n === 3);
    if (n === 3 && !was && justGot !== undefined) restamp($('.full', rev));
  }
  $$('.sfx').forEach((b) => b.addEventListener('click', (e) => {
    e.stopPropagation();
    const i = +b.dataset.sfx;
    if (found.has(i)) return;
    found.add(i); store.set('sr-stamps', [...found]); renderStamps(i);
  }));
  $('#reset').addEventListener('click', () => { found.clear(); store.set('sr-stamps', []); renderStamps(); });
  renderStamps();
  // The card waits until the hero is behind you, so it never covers the hero's download button on a phone.
  const card = $('#card');
  card.hidden = !found.size;
  new IntersectionObserver(([e]) => { card.hidden = e.isIntersecting && !found.size; }).observe($('.hero'));

  // ---- Hanko press (chapter 1)
  const zone = $('#hanko-zone');
  zone.addEventListener('pointerdown', (e) => {
    if (e.target.closest('button, a')) return;
    const r = zone.getBoundingClientRect();
    const s = document.createElement('span');
    s.className = 'seal-press'; s.textContent = '読';
    s.style.left = (e.clientX - r.left) + 'px'; s.style.top = (e.clientY - r.top) + 'px';
    s.style.rotate = (Math.random() * 24 - 12) + 'deg';
    zone.appendChild(s);
    const seals = $$('.seal-press', zone);
    if (seals.length > 6) seals[0].remove();
  });

  // ---- Hangul tiles: tap toggles on touch
  $$('.jamo').forEach((j) => j.addEventListener('click', () => j.classList.toggle('built')));

  // ---- Chop (chapter 3)
  $('#chop').addEventListener('click', () => {
    const box = $('#chops');
    const s = document.createElement('span'); s.textContent = '读'; s.className = 'stamp-in';
    s.style.rotate = (Math.random() * 16 - 8) + 'deg';
    box.appendChild(s);
    if (box.children.length > 10) box.firstElementChild.remove();
  });

  // Runs `step` at most 30 times a second, only while `el` is on screen.
  // `step` returns false when there is nothing left to animate; call the
  // returned kick() to wake it again.
  function loop(el, step) {
    let visible = false, raf = 0, last = 0;
    const tick = (t) => {
      raf = 0;
      if (!visible) return;
      if (t - last >= 33) { last = t; if (step() === false) return; }
      raf = requestAnimationFrame(tick);
    };
    const kick = () => { if (!raf && visible) raf = requestAnimationFrame(tick); };
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; kick(); }).observe(el);
    return kick;
  }

  // ---- Noren: a verlet cloth, four panels hung from a rod.
  const stage = $('#stage'), cv = $('#noren'), cx = cv.getContext('2d');
  const PANELS = 4, COLS = 5, ROWS = 11, GAP = 6, crest = ['漫', '画', '読', '処'];
  let W = 0, H = 0, pts = [], ties = [], opened = false, openT = 0, dragAmount = 0, toneP = null, restW = 1;
  let pointer = null, kick = () => {}, idle = 0;
  function build() {
    const r = stage.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
    W = r.width; H = r.height; cv.width = W * dpr; cv.height = H * dpr; cx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const t = document.createElement('canvas'); t.width = t.height = 8;
    const g = t.getContext('2d'); g.fillStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.arc(4, 4, 1.3, 0, 7); g.fill();
    toneP = cx.createPattern(t, 'repeat');
    pts = []; ties = [];
    const pw = (W - GAP * (PANELS - 1)) / PANELS, rh = (H * 0.8) / (ROWS - 1);
    restW = pw / (COLS - 1);
    for (let p = 0; p < PANELS; p++) {
      const x0 = p * (pw + GAP);
      for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) {
        const px = x0 + x * restW, py = 8 + y * rh;
        pts.push({ x: px, y: py, ox: px, oy: py, hx: px, pin: y === 0, p });
        const i = pts.length - 1;
        if (x) ties.push([i - 1, i, restW]);
        if (y) ties.push([i - COLS, i, rh]);
      }
    }
  }
  const shift = (p, t) => (p < PANELS / 2 ? -1 : 1) * W * 0.62 * t;
  const pos = (e) => { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
  let touched = false;
  cv.addEventListener('pointerdown', (e) => { touched = true; const [x, y] = pos(e); pointer = { x, y, vx: 0, vy: 0, down: true }; kick(); });
  // Visitors who never drag still get to see the app.
  setTimeout(() => { if (!touched) openCurtain(); }, 7000);
  cv.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'touch' && !pointer) return;
    const [x, y] = pos(e), p = pointer || { x, y };
    pointer = { x, y, vx: x - p.x, vy: y - p.y, down: e.buttons > 0 || e.pointerType === 'touch' };
    if (pointer.down) dragAmount += Math.abs(pointer.vx);
    if (dragAmount > W * 0.45) openCurtain();
    kick();
  });
  cv.addEventListener('pointerleave', () => { pointer = null; });
  cv.addEventListener('pointerup', () => { pointer = null; });
  cv.addEventListener('pointercancel', () => { pointer = null; });
  function openCurtain() { if (opened) return; opened = true; openT = 0; stage.classList.add('open'); kick(); }
  $('#part').addEventListener('click', openCurtain);
  function step() {
    if (opened && openT < 1) openT = Math.min(1, openT + 0.03);
    const e = 1 - Math.pow(1 - openT, 3);
    let energy = 0;
    for (const q of pts) {
      if (q.pin) { q.x = q.hx + (opened ? shift(q.p, e) : 0); continue; }
      const vx = (q.x - q.ox) * 0.97, vy = (q.y - q.oy) * 0.97;
      q.ox = q.x; q.oy = q.y; q.x += vx; q.y += vy + 0.55;
      energy += Math.abs(vx) + Math.abs(vy);
      if (pointer && Math.abs(pointer.vx) + Math.abs(pointer.vy) > 0.5) {
        const dx = q.x - pointer.x, dy = q.y - pointer.y, d2 = dx * dx + dy * dy;
        if (d2 < 3600) { const f = 1 - d2 / 3600; q.x += pointer.vx * 0.55 * f; q.y += pointer.vy * 0.25 * f; }
      }
    }
    if (pointer) { pointer.vx *= 0.5; pointer.vy *= 0.5; }
    for (let k = 0; k < 3; k++) for (const [a, b, len] of ties) {
      const A = pts[a], B = pts[b], dx = B.x - A.x, dy = B.y - A.y, d = Math.hypot(dx, dy) || 1, diff = (d - len) / d / 2;
      if (!A.pin) { A.x += dx * diff; A.y += dy * diff; }
      if (!B.pin) { B.x -= dx * diff; B.y -= dy * diff; }
    }
    draw();
    idle = energy < 0.4 && !pointer && (!opened || openT >= 1) ? idle + 1 : 0;
    return idle < 20;
  }
  function draw() {
    cx.clearRect(0, 0, W, H);
    const red = css('--seal'), on = css('--on-seal');
    for (let p = 0; p < PANELS; p++) {
      const off = p * ROWS * COLS;
      for (let y = 0; y < ROWS - 1; y++) for (let x = 0; x < COLS - 1; x++) {
        const a = pts[off + y * COLS + x], b = pts[off + y * COLS + x + 1], c = pts[off + (y + 1) * COLS + x + 1], d = pts[off + (y + 1) * COLS + x];
        cx.beginPath(); cx.moveTo(a.x, a.y); cx.lineTo(b.x, b.y); cx.lineTo(c.x, c.y); cx.lineTo(d.x, d.y); cx.closePath();
        cx.fillStyle = red; cx.fill();
        // Folds: cells squeezed narrower than rest read darker.
        const squeeze = 1 - Math.min(1, Math.hypot(b.x - a.x, b.y - a.y) / restW);
        if (squeeze > 0.02) { cx.fillStyle = `rgba(0,0,0,${Math.min(0.45, squeeze * 1.2)})`; cx.fill(); }
        cx.fillStyle = toneP; cx.fill();
      }
      // Crest at the panel's middle, turned with the cloth.
      const m = pts[off + 3 * COLS + 2], n = pts[off + 4 * COLS + 2];
      cx.save(); cx.translate(m.x, m.y); cx.rotate(-Math.atan2(n.x - m.x, n.y - m.y));
      cx.fillStyle = on; cx.font = `400 ${Math.round(Math.min(60, W / 7.5))}px "Dela Gothic One", sans-serif`;
      cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText(crest[p], 0, 0); cx.restore();
      // Hem line.
      cx.strokeStyle = on; cx.lineWidth = 2; cx.beginPath();
      for (let x = 0; x < COLS; x++) { const q = pts[off + (ROWS - 2) * COLS + x]; x ? cx.lineTo(q.x, q.y) : cx.moveTo(q.x, q.y); }
      cx.stroke();
    }
  }
  if (reduced) {
    stage.classList.add('open'); cv.remove();
  } else {
    build(); draw(); kick = loop(stage, step);
    // A small breeze on load so the cloth reads as cloth.
    setTimeout(() => { pts.forEach((q) => { if (!q.pin) q.ox -= (q.y / H) * 7; }); kick(); }, 500);
    let lastW = W;
    new ResizeObserver(() => {
      const r = stage.getBoundingClientRect();
      if (Math.abs(r.width - lastW) < 1 && Math.abs(r.height - H) < 1) return;
      lastW = r.width; build(); draw(); kick();
    }).observe(stage);
    addEventListener('themechange', () => draw());
    if (document.fonts) document.fonts.ready.then(() => draw());
  }

  // ---- Ink trail that bleeds into the paper (chapter 3)
  const paper = $('#paper'), ink = $('#ink'), ic = ink.getContext('2d');
  let blobs = [], last = null, PW = 0, PH = 0;
  function sizeInk() {
    const r = paper.getBoundingClientRect(), dpr = Math.min(devicePixelRatio || 1, 2);
    PW = r.width; PH = r.height; ink.width = PW * dpr; ink.height = PH * dpr; ic.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  function inkStep() {
    ic.clearRect(0, 0, PW, PH);
    const col = css('--ink');
    blobs = blobs.filter((b) => b.a > 0.01);
    ic.fillStyle = col;
    for (const b of blobs) {
      b.r += (b.max - b.r) * 0.08; b.a *= 0.985;
      // Hard core plus a soft halo: the halo is the bleed into the paper fibres.
      ic.globalAlpha = b.a * 0.25; ic.beginPath(); ic.arc(b.x, b.y, b.r * 1.7, 0, 7); ic.fill();
      ic.globalAlpha = b.a; ic.beginPath(); ic.arc(b.x, b.y, b.r, 0, 7); ic.fill();
    }
    ic.globalAlpha = 1;
    return blobs.length > 0;
  }
  if (!reduced) {
    sizeInk(); new ResizeObserver(sizeInk).observe(paper);
    const kickInk = loop(paper, inkStep);
    paper.addEventListener('pointermove', (e) => {
      const r = paper.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
      const sp = last ? Math.hypot(x - last.x, y - last.y) : 0;
      const n = Math.max(1, Math.ceil(sp / 8));
      for (let i = 1; i <= n; i++) {
        const t = i / n, px = last ? last.x + (x - last.x) * t : x, py = last ? last.y + (y - last.y) * t : y;
        blobs.push({ x: px, y: py, r: 2, max: Math.max(4, 14 - sp * 0.2) + Math.random() * 5, a: 0.8 });
      }
      if (blobs.length > 500) blobs.splice(0, blobs.length - 500);
      last = { x, y }; kickInk();
    });
    paper.addEventListener('pointerleave', () => { last = null; });
  } else { ink.remove(); $('.tip', paper).remove(); }

  // ---- Lantern: a damped pendulum you can push
  const lan = $('#lantern'), lw = $('#lantern-wrap');
  let ang = 0, vel = 0, lastX = null;
  const swing = () => {
    vel += -ang * 0.012; vel *= 0.985; ang += vel;
    lan.style.transform = `rotate(${ang}rad)`;
    return Math.abs(ang) + Math.abs(vel) > 0.0008;
  };
  if (!reduced) {
    const kickLan = loop(lw, swing);
    lw.addEventListener('pointermove', (e) => {
      if (lastX !== null) { vel = Math.max(-0.08, Math.min(0.08, vel + (e.clientX - lastX) * 0.0016)); kickLan(); }
      lastX = e.clientX;
    });
    lw.addEventListener('pointerleave', () => { lastX = null; });
    lan.addEventListener('pointerdown', () => { vel += 0.06; kickLan(); });
  }

  // ---- Ink cursor (mouse and pen only)
  const cur = $('#cursor');
  if (!reduced && matchMedia('(pointer: fine)').matches) {
    root.classList.add('inked');
    let tx = -50, ty = -50, x = -50, y = -50, raf = 0;
    const move = () => {
      x += (tx - x) * 0.35; y += (ty - y) * 0.35;
      cur.style.transform = `translate(${x}px, ${y}px)`;
      raf = Math.abs(tx - x) + Math.abs(ty - y) > 0.3 ? requestAnimationFrame(move) : 0;
    };
    addEventListener('pointermove', (e) => {
      if (e.pointerType === 'touch') return;
      tx = e.clientX; ty = e.clientY; if (!raf) raf = requestAnimationFrame(move);
      cur.classList.toggle('link', !!e.target.closest('a, button'));
    }, { passive: true });
  }

  // ---- Downloads. Release files keep stable names, so these links always
  // point at the newest version.
  const REL = 'https://github.com/Musecreatives/personal_comic_reader/releases/latest/download/';
  // Paste the TestFlight public link here once the iOS build is approved.
  const TESTFLIGHT_URL = '';
  const WEB_APP = new URL('../', location.href).href;
  const platforms = {
    android: { title: 'Download for Android', note: 'For Android phones and tablets.', actions: [['Download the APK', REL + 'ShaddaiReader.apk']], steps: ['Open the downloaded file. If Android asks, allow installs from your browser.', 'Tap Install. Updates install the same way, over the top.'] },
    ios: TESTFLIGHT_URL
      ? { title: 'Get it for iPhone and iPad', note: "Through TestFlight, Apple's app for trying apps before they're in the App Store.", actions: [['Open in TestFlight', TESTFLIGHT_URL]], steps: ['Install TestFlight from the App Store if asked.', 'Tap Accept, then Install.'] }
      : { title: 'Use it on iPhone and iPad', note: 'The iPhone app is on its way. Until then, the web app works the same.', actions: [['Open the web app', WEB_APP]], steps: ['In Safari, tap Share, then Add to Home Screen.', 'Open it from your home screen like any app.'] },
    windows: { title: 'Download for Windows', note: 'Windows 10 or 11.', actions: [['Download for Windows', REL + 'ShaddaiReader-windows.zip']], steps: ['Right-click the file and choose Extract All.', 'Open shaddai_reader.exe. If Windows warns you, choose More info, then Run anyway.'] },
    web: { title: 'Open in your browser', note: "Works on any device. Install it from your browser's menu to get its own window.", actions: [['Open the web app', WEB_APP]], steps: [] },
  };
  const ua = navigator.userAgent;
  const detected = /Android/i.test(ua) ? 'android' : (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) ? 'ios' : /Windows/.test(ua) ? 'windows' : 'web';
  const bubble = $('#primary');
  function show(key) {
    const p = platforms[key];
    $('#primary-h').textContent = p.title; $('#primary-note').textContent = p.note;
    $('#primary-actions').replaceChildren(...p.actions.map(([label, href]) => Object.assign(document.createElement('a'), { className: 'btn', href, textContent: label })));
    const ol = $('#primary-steps');
    ol.replaceChildren(...p.steps.map((s) => Object.assign(document.createElement('li'), { textContent: s })));
    ol.hidden = !p.steps.length;
    $$('.dev').forEach((b) => b.setAttribute('aria-pressed', b.dataset.dl === key));
    bubble.classList.remove('pop'); void bubble.offsetWidth; bubble.classList.add('pop');
  }
  show(detected);
  ['#hero-cta', '#reveal-cta'].forEach((s) => Object.assign($(s), { href: platforms[detected].actions[0][1], textContent: platforms[detected].actions[0][0] }));
  $$('.dev').forEach((b) => b.addEventListener('click', () => show(b.dataset.dl)));
  if (TESTFLIGHT_URL) $('#ios-meta').textContent = 'TESTFLIGHT';

  // ---- Invite ticket. The owner sends a link like /get/?code=XXXX-XXXX;
  // the code is never part of this page itself.
  const code = new URLSearchParams(location.search).get('code');
  if (code) {
    const ticket = $('#invite');
    ticket.hidden = false;
    $('#code').textContent = code;
    $('#copy').addEventListener('click', async (e) => {
      const btn = e.currentTarget;
      try {
        await navigator.clipboard.writeText(code);
        btn.textContent = 'Copied';
        $('.seal-press', ticket)?.remove();
        const s = Object.assign(document.createElement('span'), { className: 'seal-press', textContent: '済' });
        s.style.cssText = 'left: calc(100% - 56px); top: 56px; rotate: -12deg';
        ticket.appendChild(s);
      } catch { getSelection().selectAllChildren($('#code')); btn.textContent = 'Selected. Press Ctrl+C'; }
      setTimeout(() => { btn.textContent = 'Copy code'; }, 2400);
    });
  }
})();
