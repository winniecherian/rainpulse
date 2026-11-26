// Flip to true the day RainPulse goes live on the App Store.
const APP_LIVE = false;
const STORE_URL = "https://apps.apple.com/app/id6838320608";

document.querySelectorAll("[data-store]").forEach(a => {
  if (APP_LIVE) { a.href = STORE_URL; return; }
  a.href = "https://x.com/NeuralOrbitX";
  a.setAttribute("rel", "noopener");
  if (a.classList.contains("store-mini")) a.textContent = "Launching soon";
});
document.querySelectorAll("[data-store-small]").forEach(s => {
  s.textContent = APP_LIVE ? "Download on the" : "Coming soon on the";
});
if (!APP_LIVE) {
  const note = document.querySelector(".cta-note");
  if (note) note.innerHTML = 'Launching soon for iPhone. Follow <a href="https://x.com/NeuralOrbitX">@NeuralOrbitX</a> to hear the day it lands.';
}

// ---------- Rain Clock ----------
const COLORS = ["#2a4060", "var(--r1)", "var(--r2)", "var(--r3)", "var(--r4)", "var(--r5)"];
const seg = parts => { const a = []; parts.forEach(([n, v]) => { for (let i = 0; i < n; i++) a.push(typeof v === "function" ? v(i, n) : v); }); return a.slice(0, 120); };
const ramp = (from, to) => (i, n) => Math.round(from + (to - from) * (i / Math.max(1, n - 1)));

const CITIES = {
  chennai:   { warn: ["Heavy rain", "India Meteorological Department, for Chennai district, until 9 pm"], head: "Rain in\u00a018\u00a0min", sub: "Heavy for 25 min, then easing. Dry again by 7:40.",
               data: seg([[18,0],[4,ramp(2,4)],[22,i=>i%7<3?5:4],[16,ramp(4,3)],[14,ramp(2,1)],[46,0]]) },
  london:    { warn: ["Yellow warning: rain", "Met Office, for London, until 6 am"], head: "Drizzle now", sub: "Dry window from 35 to 70 min. Leave then.",
               data: seg([[35,1],[35,0],[10,ramp(1,2)],[40,i=>i%9<4?2:1]]) },
  mumbai:    { warn: ["Orange alert: very heavy rain", "India Meteorological Department, for Mumbai district, until midnight"], head: "Downpour now", sub: "Easing in about 50 min. Low roads may flood.",
               data: seg([[30,i=>i%6<3?5:4],[20,ramp(5,3)],[25,ramp(3,2)],[45,i=>i%5<2?2:1]]) },
  singapore: { head: "Dry for 75\u00a0min", sub: "Thunderstorm expected after that.",
               data: seg([[75,0],[5,ramp(2,4)],[22,i=>i%5<2?5:4],[18,ramp(3,1)]]) },
};

const svg = document.getElementById("dial");
const ticksG = document.getElementById("ticks");
const hand = document.getElementById("hand");
const head = document.getElementById("c-head");
const sub = document.getElementById("c-sub");
const NS = "http://www.w3.org/2000/svg";
const C = 200, R0 = 132;
const ticks = [];
for (let m = 0; m < 120; m++) {
  const a = (m / 120) * Math.PI * 2 - Math.PI / 2;
  const l = document.createElementNS(NS, "line");
  l.setAttribute("class", "tick");
  l.dataset.a = a;
  ticksG.appendChild(l);
  ticks.push(l);
}
[["Now",0],["30",30],["60",60],["90",90]].forEach(([t, m]) => {
  const a = (m / 120) * Math.PI * 2 - Math.PI / 2, r = 196;
  const tx = document.createElementNS(NS, "text");
  tx.setAttribute("class", "hour");
  tx.setAttribute("x", C + Math.cos(a) * r);
  tx.setAttribute("y", C + Math.sin(a) * r + 4);
  tx.setAttribute("text-anchor", m === 30 ? "start" : m === 90 ? "end" : "middle");
  if (m === 0) tx.setAttribute("y", C + Math.sin(a) * r - 2);
  if (m === 60) tx.setAttribute("y", C + Math.sin(a) * r + 12);
  tx.textContent = t;
  svg.insertBefore(tx, ticksG);
});

function setTick(l, v) {
  const a = +l.dataset.a, len = v === 0 ? 8 : 14 + v * 7;
  l.setAttribute("x1", C + Math.cos(a) * R0);
  l.setAttribute("y1", C + Math.sin(a) * R0);
  l.setAttribute("x2", C + Math.cos(a) * (R0 + len));
  l.setAttribute("y2", C + Math.sin(a) * (R0 + len));
  l.setAttribute("stroke-width", v === 0 ? 2 : 3.2);
  l.style.stroke = COLORS[v];
}

const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
function show(name, sweep) {
  const c = CITIES[name];
  head.textContent = c.head;
  const w = document.getElementById("warn");
  if (c.warn) { document.getElementById("w-title").textContent = c.warn[0]; document.getElementById("w-meta").textContent = c.warn[1]; w.classList.remove("off"); }
  else w.classList.add("off");
  sub.textContent = c.sub;
  if (!sweep || reduce) { c.data.forEach((v, i) => setTick(ticks[i], v)); setHand(0); return; }
  // one orchestrated moment: the hand sweeps the next two hours and lays the rain down behind it
  ticks.forEach(t => setTick(t, 0));
  const start = performance.now(), dur = 1800;
  (function frame(now) {
    const p = Math.min(1, (now - start) / dur), e = 1 - Math.pow(1 - p, 3), upto = Math.floor(e * 120);
    for (let i = 0; i < upto; i++) if (!ticks[i]._on) { setTick(ticks[i], c.data[i]); ticks[i]._on = true; }
    setHand(e * 120);
    if (p < 1) requestAnimationFrame(frame);
    else { ticks.forEach(t => t._on = false); setHand(0, true); }
  })(start);
}
function setHand(min, ease) {
  hand.style.transition = ease && !reduce ? "transform .6s ease" : "none";
  hand.style.transform = `rotate(${(min / 120) * 360}deg)`;
}

const tabs = document.querySelectorAll(".cities button");
tabs.forEach(b => b.addEventListener("click", () => {
  tabs.forEach(x => x.setAttribute("aria-selected", x === b ? "true" : "false"));
  show(b.dataset.city, false);
}));
show("chennai", true);
