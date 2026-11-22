// Hero scene, after Keyrate. The Tether window on the desk reconnects on a loop; the keys under the buttons type the
// whole routine (Command Space, "tether", Return); loose keycaps drift at three depths. Every layer eases toward the
// scroll position at its own speed and leans from the pointer on desktop. The demo window below the hero drops and
// comes back on a click. Reduced motion gets a still, connected scene.
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
const el = (t, c, x) => { const e = document.createElement(t); if (c) e.className = c; if (x != null) e.textContent = x; return e; };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const NAME = 'Incase Ergonomic Mouse';

// Every [data-win] slot gets a copy of the app's one screen.
const tpl = document.getElementById('win');
const wins = [...document.querySelectorAll('[data-win]')].map((slot) => { slot.append(tpl.content.cloneNode(true)); return slot.querySelector('.win'); });
const set = (win, state) => {
  win.dataset.state = state;
  win.querySelector('h3').textContent = state === 'connected' ? 'Connected' : 'Connecting';
  win.querySelector('p').textContent = state === 'connected' ? `${NAME} is ready to go.` : `Looking for ${NAME}.`;
};
const [hero, live] = wins;

// The keys, typed, while the window on the desk follows along.
const typed = document.querySelector('.typed');
if (typed) {
  const [cmd, space, ret] = typed.querySelectorAll('kbd'), q = typed.querySelector('.q');
  const press = async (...ks) => { ks.forEach((k) => k.classList.add('down')); await wait(160); ks.forEach((k) => k.classList.remove('down')); };
  if (still) { q.textContent = 'tether'; set(hero, 'connected'); }
  else (async () => {
    for (;;) {
      q.textContent = ''; set(hero, 'connected');
      await wait(1200);
      await press(cmd, space); await wait(380);
      for (const ch of 'tether') { q.textContent += ch; await wait(90 + Math.random() * 70); }
      await wait(300); await press(ret);
      set(hero, 'connecting'); await wait(1500); set(hero, 'connected');
      await wait(2600);
    }
  })();
}

// The demo: connects once when it scrolls in, then again on every drop.
let timer;
const drop = (e) => { e?.preventDefault(); clearTimeout(timer); set(live, 'connecting'); timer = setTimeout(() => set(live, 'connected'), 1400); };
set(live, 'connected');
document.getElementById('drop')?.addEventListener('click', drop);
if (!still && 'IntersectionObserver' in window) {
  const io = new IntersectionObserver((es) => { if (es[0].isIntersecting) { drop(); io.disconnect(); } }, { threshold: .6 });
  io.observe(live);
}

// Loose keycaps at three depths; the middle stays clear for the title.
const MOUSE = '<svg viewBox="0 0 1024 1024"><use href="#g-mouse"/></svg>';
const BT = '<svg viewBox="0 0 100 100"><use href="#g-bt"/></svg>';
const CAPS = [['⌘', 1], ['esc'], [MOUSE, 1], ['⏎', 1], ['T'], [BT], ['⌥'], ['space', 0, 1], ['⌘'], ['⏎'], [MOUSE], ['⇧']];
const sky = document.getElementById('sky');
const layers = [];
if (sky) {
  let seed = 11;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const few = innerWidth < 600;
  const depths = [
    { cls: 'far', n: 10, size: 22, lag: .7, tilt: 10, spin: .02 },
    { cls: 'mid', n: 8, size: 36, lag: .35, tilt: 20, spin: .05 },
    { cls: 'near', n: 6, size: 60, lag: -.35, tilt: 36, spin: .1 },
  ];
  let k = 0;
  for (const d of depths) {
    const layer = sky.appendChild(el('div', 'layer ' + d.cls));
    const n = few ? (d.cls === 'near' ? 0 : d.cls === 'mid' ? 0 : 6) : d.n; // phones: small caps only, clear of the copy
    for (let i = 0; i < n; i++) {
      const side = i % 2, slot = Math.floor(i / 2), slots = Math.ceil(n / 2);
      const band = few ? 7 : d.cls === 'far' ? 22 : 12; // caps keep to the edges, clear of the headline
      const x = side ? 98 - band + rnd() * band - 6 : 1 + rnd() * band;
      const y = 3 + (slot + .15 + rnd() * .7) * (60 / slots);
      let [label, lit, wide] = CAPS[k++ % CAPS.length];
      if (few && wide) label = '⌘', wide = 0; // no wide cap on a phone
      const c = layer.appendChild(el('span', 'cap' + (lit && d.cls !== 'far' ? ' lit' : '') + (wide ? ' wide' : '')));
      c.innerHTML = label;
      c.style.cssText = `left:${x.toFixed(1)}%;top:${y.toFixed(1)}%;--s:${d.size}px;` +
        `animation-duration:${(5 + rnd() * 5).toFixed(1)}s;animation-delay:${(-rnd() * 10).toFixed(1)}s;--r:${Math.round(rnd() * 40 - 20)}deg`;
      c.dataset.spin = ((rnd() < .5 ? -1 : 1) * d.spin * (.6 + rnd() * .8)).toFixed(3);
    }
    layers.push({ layer, lag: d.lag, tilt: d.tilt, caps: [...layer.children] });
  }
}

// Parallax, eased toward the target each frame so a flick of the wheel glides. The copy lifts and fades.
const ground = document.querySelector('.ground'), copy = document.querySelector('.lp-hero .hero-copy');
if (!still) {
  const now = { y: scrollY, px: 0, py: 0 }, goal = { y: scrollY, px: 0, py: 0 };
  let running = false;
  const frame = () => {
    let moving = false;
    for (const key in now) {
      const d = goal[key] - now[key];
      now[key] = Math.abs(d) < .05 ? goal[key] : now[key] + d * .12;
      if (now[key] !== goal[key]) moving = true;
    }
    const y = now.y;
    if (y < innerHeight * 1.4) {
      if (ground) ground.style.transform = `translate3d(${(now.px * 8).toFixed(2)}px,${(y * .45 + now.py * 5).toFixed(2)}px,0)`;
      for (const { layer, lag, tilt, caps } of layers) {
        layer.style.transform = `translate3d(${(now.px * tilt).toFixed(2)}px,${(y * lag + now.py * tilt * .6).toFixed(2)}px,0)`;
        for (const c of caps) c.style.rotate = `${(y * c.dataset.spin).toFixed(2)}deg`;
      }
      if (copy) { copy.style.transform = `translate3d(0,${(y * .2).toFixed(2)}px,0)`; copy.style.opacity = Math.max(0, 1 - y / (innerHeight * .7)); }
    }
    running = moving;
    if (moving) requestAnimationFrame(frame);
  };
  const kick = () => { if (!running) { running = true; requestAnimationFrame(frame); } };
  addEventListener('scroll', () => { goal.y = scrollY; kick(); }, { passive: true });
  if (matchMedia('(pointer: fine)').matches) addEventListener('pointermove', (e) => {
    goal.px = -(e.clientX / innerWidth - .5) * 2; goal.py = -(e.clientY / innerHeight - .5) * 2; kick();
  }, { passive: true });
}
