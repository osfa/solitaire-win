// Solitaire Win in the browser: a port of the macOS screensaver (Sources/*.swift) to WebGL2.
// Speeds and forces are in virtual pixels per 1/60 s tick, as in the Swift version.

const CARD_W = 71, CARD_H = 96;
const STEPS_PER_SECOND = 150;
const STOCK_SLOT = 62;
const MAX_FLYERS = 64, MAX_STAMPS = 40000, STAMP_BUDGET = 900;
const BACKS = [52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 65, 66, 67, 68, 69, 70, 71, 72, 73];
// Launch velocities in card px/s (y down), measured from a recording of the original.
const LAUNCHES = [[-745, -392], [103, -883], [-290, -22], [-290, -197], [-290, 240], [-290, 256], [579, -666],
  [-310, -484], [-290, 440], [248, 0], [-290, -365], [-290, -218], [310, 181], [-310, 280], [-559, 191], [207, -79],
  [-910, -265], [-703, 471], [-600, -416], [-290, 226], [-786, 0], [-559, -520], [-290, 361], [-745, -288], [-310, 300],
  [166, 0], [-290, -380], [-848, 341], [-269, -9], [331, -340], [-621, 0], [-248, -942], [290, -67], [-455, 602],
  [-124, -720], [290, -426], [-434, -100], [434, -824], [-259, -395], [-331, 320], [-310, 10], [-745, 223], [-931, 631]];

// ---------------------------------------------------------------- helpers

function makeRng(seed) {
  let s = seed >>> 0;
  const unit = () => {
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    seed,
    unit,
    range: (a, b) => a + unit() * (b - a),
    int: n => (n <= 0 ? 0 : Math.floor(unit() * n)),
    chance: p => unit() < p,
    sign: () => (unit() < 0.5 ? 1 : -1),
    pick(items, weight) {
      const total = items.reduce((s, i) => s + weight(i), 0);
      if (total <= 0) return null;
      let x = unit() * total;
      for (const i of items) if ((x -= weight(i)) <= 0) return i;
      return items[items.length - 1];
    },
  };
}
const lerp = (a, b, t) => a + (b - a) * t;
const clamp01 = x => Math.min(Math.max(x, 0), 1);

function hsv(h, s, v) {
  const hh = (h - Math.floor(h)) * 6, i = Math.floor(hh) % 6, f = hh - Math.floor(hh);
  const p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i];
}

function defaultParams() {
  return {
    physics: {
      timeScale: 1, gravity: [0, 1.63], restitution: 0.8, drag: 0, walls: false, ceiling: false,
      orbitStrength: 0, orbitCenter: [0, 0], homingStrength: 0, homingTarget: [0, 0], sineAmp: 0, sineFreq: 0,
      jitter: 0, splitOnBounce: 0, teleportRate: 0, cardScale: 1, stickyFloor: 0, wrongLaunch: 0, parallel: 1,
      showBack: 0, cardCycle: 0, rainbow: 0, rainbowSpeed: 0,
    },
    look: {
      hue: 0, paletteMix: 0, paletteShift: 0, invert: 0, rgbSplit: 0, tear: 0, feltMix: 0, feltTint: [0, 0.5, 0],
      atlasOffset: [0, 0], strideExtra: 0, scroll: [0, 0], tintMix: 0, tint: [1, 1, 1], grey: 0, cga: 0,
      flipX: false, flipY: false,
    },
  };
}

// ---------------------------------------------------------------- engine

class Engine {
  constructor(rng) {
    this.rng = rng;
    this.size = [960, 540];
    this.stamps = new Float32Array(MAX_STAMPS * 7);
    this.stampCount = 0;
    this.canvasOps = [];
    this.acc = 0;
    this.restart();
  }

  resize(w, h) { this.size = [w, h]; this.restart(); }

  restart() {
    this.piles = [0, 1, 2, 3].map(suit => Array.from({ length: 13 }, (_, r) => suit * 13 + r));
    this.flyers = [];
    this.nextPile = 0;
    this.roundPause = null;
    this.wipe = true;
    this.stampCount = 0;
    this.stamp(STOCK_SLOT, this.columnX(0), 6, 1);
    for (let i = 0; i < 4; i++) this.stamp(this.piles[i][12], ...this.pilePos(i), 1);
  }

  // Refills the foundations and carries on over the existing trails.
  nextRound() {
    this.piles = [0, 1, 2, 3].map(suit => Array.from({ length: 13 }, (_, r) => suit * 13 + r));
    this.nextPile = 0;
    this.roundPause = null;
  }

  clearOutput() { this.stampCount = 0; this.canvasOps.length = 0; this.wipe = false; }

  columnX(col) {
    const gap = (this.size[0] - 7 * CARD_W) / 8;
    return gap + col * (CARD_W + gap);
  }

  pilePos(i) { return [this.columnX(i + 3), 6]; }

  randomSpot() {
    const r = this.rng;
    return [r.range(0, Math.max(1, this.size[0] - CARD_W)), r.range(0, Math.max(1, this.size[1] - CARD_H))];
  }

  spawnBurst(n) {
    const r = this.rng;
    for (let k = 0; k < n && this.flyers.length < MAX_FLYERS; k++) {
      const pos = r.chance(0.5) ? this.pilePos(r.int(4)) : [r.range(0, this.size[0]), r.range(-50, this.size[1] * 0.3)];
      this.flyers.push({ card: r.int(52), pos, vel: [r.range(1, 9) * r.sign(), -r.range(0, 12)], age: 0, stall: 0, back: null, ghost: true });
    }
  }

  frame(dt, p) {
    if (this.roundPause !== null) {
      this.roundPause -= dt;
      if (this.roundPause <= 0) this.nextRound();
      return;
    }
    const ticks = STEPS_PER_SECOND * dt * p.timeScale;
    if (ticks === 0) return;
    if (Math.abs(ticks) < 1) {
      this.step(ticks, p, true);
    } else {
      this.acc += Math.abs(ticks);
      const n = Math.min(Math.floor(this.acc), 600);
      this.acc -= Math.floor(this.acc);
      const every = Math.max(1, Math.ceil(Math.max(this.flyers.length, 1) * n / STAMP_BUDGET));
      for (let i = 0; i < n; i++) this.step(ticks > 0 ? 1 : -1, p, (n - 1 - i) % every === 0);
    }
    if (this.flyers.length === 0 && this.piles.every(pl => pl.length === 0)) this.roundPause = 1;
  }

  launchNext(p) {
    const r = this.rng;
    for (let k = 0; k < 4; k++) {
      const i = this.nextPile;
      this.nextPile = (this.nextPile + 1) % 4;
      const card = this.piles[i].pop();
      if (card === undefined) continue;
      // Whole pixels per step keep the copies evenly spaced; starting half a pixel in keeps rounding stable.
      const start = r.chance(p.wrongLaunch) ? this.randomSpot() : this.pilePos(i);
      const pos = [Math.floor(start[0]) + 0.5, Math.floor(start[1]) + 0.5];
      const [lx, ly] = LAUNCHES[r.int(LAUNCHES.length)];
      const dx = Math.max(1, Math.round(Math.abs(lx) / STEPS_PER_SECOND)) * (lx < 0 ? -1 : 1);
      const vy = ly * r.range(0.9, 1.1);
      return { card, pos, vel: [dx * STEPS_PER_SECOND / 60, vy / 60], age: 0, stall: 0, back: null, ghost: false };
    }
    return null;
  }

  step(steps, p, stamping) {
    const h = steps * 60 / STEPS_PER_SECOND;
    const r = this.rng;
    if (h > 0) {
      while (this.flyers.filter(f => !f.ghost).length < p.parallel) {
        const f = this.launchNext(p);
        if (!f) break;
        this.flyers.push(f);
      }
    }
    const cw = CARD_W * p.cardScale, ch = CARD_H * p.cardScale;
    const [W, H] = this.size;
    const keep = [], spawned = [];

    for (const f of this.flyers) {
      let ax = p.gravity[0], ay = p.gravity[1];
      const cx = f.pos[0] + cw / 2, cy = f.pos[1] + ch / 2;
      if (p.orbitStrength > 0) {
        const dx = p.orbitCenter[0] - cx, dy = p.orbitCenter[1] - cy, d = Math.max(Math.hypot(dx, dy), 20);
        ax += dx / d * p.orbitStrength; ay += dy / d * p.orbitStrength;
      }
      if (p.homingStrength > 0) {
        const dx = p.homingTarget[0] - cx, dy = p.homingTarget[1] - cy, d = Math.max(Math.hypot(dx, dy), 1);
        ax += (dx / d * 8 - f.vel[0]) * 0.05 * p.homingStrength;
        ay += (dy / d * 8 - f.vel[1]) * 0.05 * p.homingStrength;
      }
      if (p.jitter > 0) { ax += r.range(-1, 1) * p.jitter; ay += r.range(-1, 1) * p.jitter; }

      if (h > 0) {
        f.vel[0] += ax * h; f.vel[1] += ay * h;
        f.vel[0] *= 1 - p.drag * h; f.vel[1] *= 1 - p.drag * h;
        f.pos[0] += f.vel[0] * h; f.pos[1] += f.vel[1] * h;
      } else {
        f.pos[0] += f.vel[0] * h; f.pos[1] += f.vel[1] * h;
        f.vel[0] += ax * h; f.vel[1] += ay * h;
      }
      if (p.sineAmp !== 0) f.pos[1] += p.sineAmp * (Math.sin(p.sineFreq * (f.age + h)) - Math.sin(p.sineFreq * f.age));
      f.age += h;

      const speed = Math.hypot(f.vel[0], f.vel[1]);
      if (speed > 60) { f.vel[0] *= 60 / speed; f.vel[1] *= 60 / speed; }

      if (f.pos[1] + ch > H) {
        f.pos[1] = H - ch;
        if (f.vel[1] > 0) {
          const impact = f.vel[1];
          f.vel[1] = -impact * p.restitution;
          f.vel[0] *= 1 - p.stickyFloor;
          if (p.splitOnBounce > 0 && impact > 2) {
            for (let k = 0; k < p.splitOnBounce && this.flyers.length + spawned.length < MAX_FLYERS; k++) {
              spawned.push({ ...f, pos: [...f.pos], vel: [r.range(-8, 8), f.vel[1] * r.range(0.5, 1.2)], ghost: true });
            }
          }
        }
      }
      if (p.walls) {
        if (f.pos[0] < 0) { f.pos[0] = 0; f.vel[0] = Math.abs(f.vel[0]); }
        if (f.pos[0] + cw > W) { f.pos[0] = W - cw; f.vel[0] = -Math.abs(f.vel[0]); }
        if (p.ceiling && f.pos[1] < 0) { f.pos[1] = 0; f.vel[1] = Math.abs(f.vel[1]); }
      }
      if (p.teleportRate > 0 && r.chance(p.teleportRate * Math.abs(h) / 60)) f.pos = this.randomSpot();
      if (p.showBack > 0) {
        if (r.chance(p.showBack * 0.03 * Math.abs(h))) f.back = f.back === null ? BACKS[r.int(BACKS.length)] : null;
      } else {
        f.back = null;
      }

      if (Math.hypot(f.vel[0], f.vel[1]) < 0.3) {
        f.stall += Math.abs(h);
        if (f.stall > 240) { f.vel = [r.range(2, 6) * r.sign(), -r.range(4, 12)]; f.stall = 0; }
      } else {
        f.stall = 0;
      }

      if (stamping) {
        let card = f.back ?? f.card;
        if (p.cardCycle > 0) {
          const cells = 52 + BACKS.length;
          const i = (((f.card + Math.floor(f.age * p.cardCycle)) % cells) + cells) % cells;
          card = i < 52 ? i : BACKS[i - 52];
        }
        let tint = [1, 1, 1];
        if (p.rainbow > 0) {
          const c = hsv(f.age * p.rainbowSpeed + f.card / 13, 1, 1);
          tint = tint.map((v, k) => lerp(v, c[k], p.rainbow));
        }
        this.stamp(card, f.pos[0], f.pos[1], p.cardScale, tint);
      }

      const gone = f.pos[0] + cw < -1 || f.pos[0] > W + 1 || f.pos[1] > H + 2000 || f.pos[1] < -3000;
      if (!gone || p.walls) keep.push(f);
    }
    this.flyers = keep.concat(spawned);
  }

  stamp(card, x, y, scale, tint = [1, 1, 1]) {
    if (this.stampCount >= MAX_STAMPS) return;
    const o = this.stampCount++ * 7, s = this.stamps;
    s[o] = Math.floor(x); s[o + 1] = Math.floor(y); s[o + 2] = scale; s[o + 3] = card;
    s[o + 4] = tint[0]; s[o + 5] = tint[1]; s[o + 6] = tint[2];
  }
}

// ---------------------------------------------------------------- effects

// [name, family, minChaos, weight, [minSeconds, maxSeconds], instant, make]
// make({rng, intensity: i, engine}) returns (params, {env, t, dt, rng, engine, first}) => void.
const FX = [
  ["slow motion", "time", 0, 3, [3, 10], false, ({ intensity: i }) => { const f = lerp(0.3, 0.03, i); return (p, k) => { p.physics.timeScale *= lerp(1, f, k.env); }; }],
  ["burst", "time", 0.1, 3, [0.3, 2.5], true, ({ intensity: i }) => { const f = lerp(4, 30, i); return p => { p.physics.timeScale *= f; }; }],
  ["stutter", "time", 0.2, 2, [2, 6], true, ({ rng }) => { const per = rng.range(0.15, 0.5); return (p, k) => { p.physics.timeScale *= (k.t / per) % 1 < 0.7 ? 0 : 3.3; }; }],
  ["rewind", "time", 0.4, 1.5, [0.7, 3], true, ({ intensity: i }) => { const f = -lerp(1, 4, i); return p => { p.physics.timeScale *= f; }; }],
  ["lurch", "time", 0.3, 1.5, [4, 12], false, ({ rng, intensity: i }) => { const d = lerp(0.7, 2.5, i), r = rng.range(1.5, 5); return (p, k) => { p.physics.timeScale *= Math.exp(Math.sin(k.t * r) * d * k.env); }; }],
  ["hang", "time", 0.3, 1, [1, 4], true, () => p => { p.physics.timeScale = 0; }],

  ["hue cycle", "colour", 0.05, 3, [6, 20], false, ({ rng, intensity: i }) => { const sp = lerp(0.3, 4, i) * rng.sign(); return (p, k) => { p.look.hue += k.env * k.t * sp; }; }],
  ["palette cycle", "colour", 0.25, 2, [4, 15], false, ({ intensity: i }) => { const rate = lerp(2, 20, i); return (p, k) => { p.look.paletteMix = Math.max(p.look.paletteMix, k.env); p.look.paletteShift = Math.floor(k.t * rate); }; }],
  ["felt drift", "colour", 0.05, 2, [8, 25], false, ({ rng, intensity: i }) => { const ph = rng.unit(), a = lerp(0.4, 1, i); return (p, k) => { p.look.feltMix = Math.max(p.look.feltMix, k.env * a); p.look.feltTint = hsv(ph + k.t * 0.05, 0.9, 0.55); }; }],
  ["invert flash", "colour", 0.3, 1.5, [0.5, 3], true, ({ intensity: i }) => { const rate = lerp(2, 12, i); return (p, k) => { if ((k.t * rate) % 1 < 0.5) p.look.invert = 1 - p.look.invert; }; }],
  ["rgb split", "colour", 0.15, 2, [1, 6], false, ({ intensity: i }) => { const a = lerp(1, 12, i); return (p, k) => { p.look.rgbSplit += k.env * a * (0.6 + 0.4 * Math.sin(k.t * 7)); }; }],
  ["rainbow cards", "colour", 0.2, 1.2, [5, 14], false, ({ intensity: i }) => { const sp = lerp(0.02, 0.15, i); return (p, k) => { p.physics.rainbow = Math.max(p.physics.rainbow, k.env); p.physics.rainbowSpeed = sp; }; }],
  ["negative", "colour", 0.3, 0.08, [4, 12], true, () => p => { p.look.invert = 1 - p.look.invert; }],
  ["phosphor", "colour", 0.2, 0.1, [6, 15], false, ({ rng }) => { const t = [[1, 0.68, 0.1], [0.25, 1, 0.3], [0.45, 0.75, 1]][rng.int(3)]; return (p, k) => { p.look.tintMix = Math.max(p.look.tintMix, k.env); p.look.tint = t; }; }],
  ["greyscale", "colour", 0.15, 0.12, [5, 15], false, () => (p, k) => { p.look.grey = Math.max(p.look.grey, k.env); }],
  ["CGA", "colour", 0.35, 0.08, [4, 10], true, () => p => { p.look.cga = 1; }],

  ["sideways gravity", "path", 0.1, 2, [4, 12], false, ({ rng, intensity: i }) => {
    const ang = rng.range(0.5, 3.14) * i * rng.sign();
    return (p, k) => { const a = ang * k.env, [gx, gy] = p.physics.gravity; p.physics.gravity = [gx * Math.cos(a) - gy * Math.sin(a), gx * Math.sin(a) + gy * Math.cos(a)]; };
  }],
  ["gravity flip", "path", 0.35, 1.5, [2, 6], false, () => (p, k) => { p.physics.gravity[1] *= lerp(1, -1, k.env); }],
  ["orbit", "path", 0.3, 1.5, [5, 15], false, ({ rng, intensity: i, engine }) => {
    const c = [rng.range(0.25, 0.75) * engine.size[0], rng.range(0.25, 0.75) * engine.size[1]], s = lerp(0.3, 1.2, i);
    return (p, k) => { p.physics.orbitCenter = c; p.physics.orbitStrength = s * k.env; p.physics.gravity = p.physics.gravity.map(g => g * (1 - k.env)); };
  }],
  ["sine wave", "path", 0.1, 2, [4, 12], false, ({ rng, intensity: i }) => { const a = lerp(5, 60, i), f = rng.range(0.05, 0.3); return (p, k) => { p.physics.sineAmp = a * k.env; p.physics.sineFreq = f; }; }],
  ["homing", "path", 0.25, 1.5, [4, 10], false, ({ rng, intensity: i, engine }) => {
    const fx = rng.range(0.2, 0.9), fy = rng.range(0.2, 0.9), s = lerp(0.2, 1, i), [W, H] = engine.size;
    return (p, k) => { p.physics.homingTarget = [W * (0.5 + 0.4 * Math.sin(k.t * fx)), H * (0.5 + 0.4 * Math.sin(k.t * fy))]; p.physics.homingStrength = s * k.env; };
  }],
  ["walls", "path", 0.2, 2, [8, 20], true, ({ intensity: i }) => { const c = i > 0.5; return p => { p.physics.walls = true; p.physics.ceiling = c; }; }],
  ["drunk", "path", 0.15, 1.5, [3, 10], false, ({ intensity: i }) => { const a = lerp(0.3, 3, i); return (p, k) => { p.physics.jitter += a * k.env; }; }],

  ["super bounce", "physics", 0.15, 2, [5, 15], false, ({ intensity: i }) => { const t = lerp(1.02, 1.25, i); return (p, k) => { p.physics.restitution = lerp(p.physics.restitution, t, k.env); }; }],
  ["dead bounce", "physics", 0.1, 1.5, [4, 10], false, ({ intensity: i }) => { const st = lerp(0, 0.3, i); return (p, k) => { p.physics.restitution = lerp(p.physics.restitution, 0.05, k.env); p.physics.stickyFloor = st * k.env; }; }],
  ["zero g", "physics", 0.2, 1.5, [3, 10], false, () => (p, k) => { p.physics.gravity = p.physics.gravity.map(g => g * (1 - k.env)); }],
  ["split", "physics", 0.35, 1.5, [4, 10], true, ({ intensity: i }) => { const n = 1 + Math.floor(i * 3); return p => { p.physics.splitOnBounce = n; }; }],
  ["teleport", "physics", 0.4, 1, [2, 8], true, ({ intensity: i }) => { const r = lerp(0.5, 6, i); return p => { p.physics.teleportRate = r; }; }],
  ["resize", "physics", 0.2, 1.5, [4, 12], false, ({ rng, intensity: i }) => { const t = rng.chance(0.5) ? lerp(0.7, 0.25, i) : lerp(1.5, 4, i); return (p, k) => { p.physics.cardScale *= lerp(1, t, k.env); }; }],
  ["crowd", "physics", 0.3, 1.5, [6, 20], true, ({ intensity: i }) => { const n = 2 + Math.floor(i * 6); return p => { p.physics.parallel = n; }; }],

  ["wrong card", "glitch", 0.25, 2, [1, 6], true, ({ rng }) => {
    const off = [Math.floor(rng.range(10, 60) * rng.sign()), rng.chance(0.5) ? 0 : Math.floor(rng.range(10, 80) * rng.sign())];
    return p => { p.look.atlasOffset = [p.look.atlasOffset[0] + off[0], p.look.atlasOffset[1] + off[1]]; };
  }],
  ["bad stride", "glitch", 0.4, 2, [0.5, 4], true, ({ rng, intensity: i }) => { const e = Math.round(rng.range(1, lerp(3, 40, i)) * rng.sign()); return p => { p.look.strideExtra += e; }; }],
  ["slices", "glitch", 0.35, 2, [0.3, 2], true, ({ rng, intensity: i }) => {
    const bands = 6 + rng.int(34), shift = lerp(20, 300, i);
    let next = 0;
    return (p, k) => { if (k.t < next) return; k.engine.canvasOps.push({ mode: 1, seed: k.rng.range(0, 1000), bands, amount: shift }); next = k.t + k.rng.range(0.08, 0.4); };
  }],
  ["erase band", "glitch", 0.3, 1.5, [0.1, 0.2], true, ({ intensity: i }) => (p, k) => {
    if (!k.first) return;
    const [W, H] = k.engine.size;
    if (k.rng.chance(0.6)) { const y = k.rng.range(0, H), h = k.rng.range(10, H * 0.4 * i + 10); k.engine.canvasOps.push({ mode: 3, rect: [0, y, W, y + h] }); }
    else { const x = k.rng.range(0, W), w = k.rng.range(10, W * 0.3 * i + 10); k.engine.canvasOps.push({ mode: 3, rect: [x, 0, x + w, H] }); }
  }],
  ["scroll", "glitch", 0.3, 1.5, [2, 8], false, ({ rng, intensity: i }) => {
    const sp = lerp(20, 400, i), dir = rng.chance(0.5) ? [rng.sign(), 0] : [0, rng.sign()];
    return (p, k) => { p.look.scroll = [p.look.scroll[0] + dir[0] * sp * k.env, p.look.scroll[1] + dir[1] * sp * k.env]; };
  }],
  ["melt", "glitch", 0.5, 1, [1, 5], false, ({ rng, intensity: i }) => {
    const seed = rng.range(0, 1000), column = Math.round(rng.range(1, 6)), a = lerp(1, 4, i);
    return (p, k) => { k.engine.canvasOps.push({ mode: 4, seed, bands: column, amount: a * k.env }); };
  }],
  ["card burst", "glitch", 0.3, 1.5, [0.1, 0.2], true, ({ intensity: i }) => { const n = Math.floor(lerp(5, 40, i)); return (p, k) => { if (k.first) k.engine.spawnBurst(n); }; }],
  ["wrong launch", "glitch", 0.25, 1.5, [8, 20], true, ({ intensity: i }) => { const w = lerp(0.3, 1, i); return p => { p.physics.wrongLaunch = w; }; }],
  ["flip to back", "glitch", 0.2, 1.5, [3, 10], false, ({ intensity: i }) => (p, k) => { p.physics.showBack = i * k.env; }],
  ["tear", "glitch", 0.2, 2, [0.5, 4], true, ({ intensity: i }) => p => { p.look.tear = Math.max(p.look.tear, i); }],
  ["card cycle", "glitch", 0.25, 1.2, [3, 10], true, ({ intensity: i }) => { const r = lerp(0.1, 1, i); return p => { p.physics.cardCycle = r; }; }],
  ["upside down", "glitch", 0.5, 0.06, [3, 8], true, () => p => { p.look.flipY = !p.look.flipY; }],
  ["mirror", "glitch", 0.4, 0.06, [3, 8], true, () => p => { p.look.flipX = !p.look.flipX; }],
].map(([name, family, minChaos, weight, duration, hard, make]) => ({ name, family, minChaos, weight, duration, hard, make }));

const FAMILIES = ["time", "colour", "path", "physics", "glitch"];

// ---------------------------------------------------------------- director

class Director {
  constructor(rng, { rampMinutes = 8, maxChaos = 1 } = {}) {
    this.rng = rng;
    this.ramp = rampMinutes * 60;
    this.delay = Math.min(this.ramp * 0.25, 45);
    this.maxChaos = maxChaos;
    this.clock = 0;
    this.clockSpeed = 1;
    this.chaosOverride = null;
    this.active = [];
    this.now = 0;
    this.nextRoll = 1;
    this.rebootLeft = null;
    this.scheduleReboot();
  }

  get chaos() {
    if (this.chaosOverride !== null) return this.chaosOverride;
    const x = clamp01((this.clock - this.delay) / this.ramp);
    return x * x * (3 - 2 * x) * this.maxChaos;
  }

  clockFor(c) {
    const y = clamp01(c / Math.max(this.maxChaos, 0.01));
    return this.delay + this.ramp * (0.5 - Math.sin(Math.asin(1 - 2 * y) / 3));
  }

  scheduleReboot() { this.nextReboot = this.delay + this.ramp + this.rng.range(120, 600); }

  update(dt, engine) {
    this.now += dt;
    this.clock += dt * this.clockSpeed;
    const p = defaultParams();

    if (this.rebootLeft === null && this.clock >= this.nextReboot && this.chaosOverride === null) this.rebootLeft = 1.2;
    if (this.rebootLeft !== null) {
      p.physics.timeScale = 0;
      p.look.tear = 0.5;
      this.rebootLeft -= dt;
      if (this.rebootLeft <= 0) {
        this.rebootLeft = null;
        this.active = [];
        engine.restart();
        this.clock = this.clockFor(0.2);
        this.scheduleReboot();
      }
      return p;
    }

    if (this.now >= this.nextRoll) { this.nextRoll = this.now + 1; this.roll(engine); }

    for (const e of this.active) {
      const t = this.now - e.start;
      const fade = e.spec.hard ? 0 : Math.min(1.5, e.duration * 0.2);
      const env = fade === 0 ? 1 : clamp01(Math.min(t / fade, (e.duration - t) / fade));
      e.body(p, { env, t, dt, rng: this.rng, engine, first: e.ticks === 0 });
      e.ticks++;
    }
    this.active = this.active.filter(e => this.now - e.start <= e.duration);
    return p;
  }

  roll(engine) {
    const c = this.chaos;
    const started = this.chaosOverride === null ? this.clock >= this.delay : c > 0.01;
    if (!started || this.active.length >= 1 + Math.floor(3 * c) || !this.rng.chance(0.03 + 0.5 * c * c)) return;
    const running = new Set(this.active.map(a => a.spec.name));
    const pool = FX.filter(s => s.minChaos <= c && !running.has(s.name));
    const spec = this.rng.pick(pool, s => s.weight);
    if (spec) this.start(spec, this.rng.range(0.3, 1) * lerp(0.4, 1, c), lerp(0.6, 1.5, c), engine);
  }

  force(family, engine) {
    const spec = this.rng.pick(FX.filter(s => s.family === family), () => 1);
    if (spec) this.start(spec, this.rng.range(0.6, 1), 1, engine);
  }

  start(spec, intensity, scale, engine) {
    const body = spec.make({ rng: this.rng, intensity, engine });
    this.active.push({ spec, start: this.now, duration: this.rng.range(...spec.duration) * scale, body, ticks: 0 });
  }
}

// ---------------------------------------------------------------- renderer

const STAMP_VS = `#version 300 es
layout(location = 0) in vec2 a_pos;
layout(location = 1) in float a_scale;
layout(location = 2) in float a_card;
layout(location = 3) in vec3 a_tint;
uniform vec2 u_virt;
out vec2 v_local;
flat out int v_card;
flat out vec3 v_tint;
void main() {
  int id = gl_VertexID;
  vec2 c = vec2((id == 1 || id == 3 || id == 4) ? 1.0 : 0.0, (id == 2 || id == 4 || id == 5) ? 1.0 : 0.0);
  vec2 card = vec2(71.0, 96.0);
  vec2 p = a_pos + c * card * a_scale;
  gl_Position = vec4(p.x / u_virt.x * 2.0 - 1.0, 1.0 - p.y / u_virt.y * 2.0, 0.0, 1.0);
  v_local = c * card;
  v_card = int(a_card + 0.5);
  v_tint = a_tint;
}`;

const STAMP_FS = `#version 300 es
precision highp float;
precision highp int;
uniform sampler2D u_atlas;
uniform vec2 u_atlasSize;
uniform vec2 u_off;
uniform float u_stride;
in vec2 v_local;
flat in int v_card;
flat in vec3 v_tint;
out vec4 o;
int wrapi(int v, int n) { return v - n * int(floor(float(v) / float(n))); }
void main() {
  int px = clamp(int(floor(v_local.x)), 0, 70);
  int py = clamp(int(floor(v_local.y)), 0, 95);
  int aw = int(u_atlasSize.x), ah = int(u_atlasSize.y);
  int cx = (v_card - 13 * (v_card / 13)) * 71 + int(u_off.x);
  int cy = (v_card / 13) * 96 + int(u_off.y);
  // Copy with a wrong row stride, like a blitter given the wrong pitch.
  int lin = wrapi(cy * aw + cx + py * (aw + int(u_stride)) + px, aw * ah);
  vec4 c = texelFetch(u_atlas, ivec2(wrapi(lin, aw), lin / aw), 0);
  if (c.a < 0.5) discard;
  o = vec4(c.rgb * v_tint, 1.0);
}`;

const FULL_VS = `#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

const COMMON = `
precision highp float;
precision highp int;
float hash11(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
int wrapi(int v, int n) { return v - n * int(floor(float(v) / float(n))); }
vec4 readWrap(sampler2D t, ivec2 p, ivec2 s) { return texelFetch(t, ivec2(wrapi(p.x, s.x), wrapi(p.y, s.y)), 0); }
`;

// GL's framebuffer rows run bottom-up; "top" below is the row counted from the top, as in the Metal version.
const CANVAS_FS = `#version 300 es
${COMMON}
uniform sampler2D u_src;
uniform int u_mode;
uniform vec2 u_tex;
uniform float u_seed, u_bands, u_amount, u_dx, u_dy;
uniform vec4 u_rect;
out vec4 o;
void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  float top = u_tex.y - gl_FragCoord.y;
  if (u_mode == 1) {
    float band = floor(top / u_tex.y * u_bands);
    if (hash11(band + u_seed * 13.0) > 0.4) p.x += int((hash11(band * 7.3 + u_seed) * 2.0 - 1.0) * u_amount);
  } else if (u_mode == 2) {
    p.x -= int(u_dx);
    p.y += int(u_dy);
  } else if (u_mode == 3) {
    if (gl_FragCoord.x >= u_rect.x && gl_FragCoord.x < u_rect.z && top >= u_rect.y && top < u_rect.w) { o = vec4(0.0, 128.0 / 255.0, 0.0, 1.0); return; }
  } else if (u_mode == 4) {
    float h = hash11(floor(gl_FragCoord.x / u_bands) + u_seed);
    if (h > 0.5) p.y += int(ceil(u_amount * h));
  }
  o = readWrap(u_src, p, ivec2(u_tex));
}`;

const POST_FS = `#version 300 es
${COMMON}
uniform sampler2D u_src;
uniform vec2 u_tex;
uniform float u_time, u_seed, u_hue, u_paletteMix, u_paletteShift, u_invert, u_split, u_tear, u_feltMix, u_pixelScale;
uniform vec3 u_feltTint;
uniform float u_tintMix, u_grey, u_cga, u_flipX, u_flipY;
uniform vec3 u_tint;
out vec4 o;
const vec3 ega[16] = vec3[16](
  vec3(0,0,0), vec3(0,0,0.5), vec3(0,0.5,0), vec3(0,0.5,0.5), vec3(0.5,0,0), vec3(0.5,0,0.5), vec3(0.5,0.5,0), vec3(0.75,0.75,0.75),
  vec3(0.5,0.5,0.5), vec3(0,0,1), vec3(0,1,0), vec3(0,1,1), vec3(1,0,0), vec3(1,0,1), vec3(1,1,0), vec3(1,1,1));
const vec3 cgaPal[4] = vec3[4](vec3(0), vec3(0.33, 1, 1), vec3(1, 0.33, 1), vec3(1));
vec3 hueRotate(vec3 c, float a) {
  vec3 k = vec3(0.57735);
  float ca = cos(a), sa = sin(a);
  return clamp(c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca), 0.0, 1.0);
}
void main() {
  vec2 p = gl_FragCoord.xy;
  if (u_flipX > 0.0) p.x = u_tex.x - 1.0 - p.x;
  if (u_flipY > 0.0) p.y = u_tex.y - 1.0 - p.y;
  if (u_tear > 0.0) {
    float tick = floor(u_time * 15.0);
    float band = floor((u_tex.y - p.y) / (24.0 * u_pixelScale));
    if (hash11(band * 3.1 + tick * 0.9 + u_seed) < u_tear * 0.35) p.x += (hash11(band + tick * 1.3) * 2.0 - 1.0) * u_tear * 0.25 * u_tex.x;
  }
  ivec2 ip = ivec2(p), s = ivec2(u_tex);
  int sp = int(u_split);
  vec3 c = vec3(readWrap(u_src, ip + ivec2(sp, 0), s).r, readWrap(u_src, ip, s).g, readWrap(u_src, ip - ivec2(sp, 0), s).b);
  if (u_feltMix > 0.0 && distance(c, vec3(0.0, 128.0 / 255.0, 0.0)) < 0.06) c = mix(c, u_feltTint, u_feltMix);
  if (u_paletteMix > 0.0) {
    int best = 0; float bd = 1e9;
    for (int i = 0; i < 16; i++) { float d = dot(c - ega[i], c - ega[i]); if (d < bd) { bd = d; best = i; } }
    c = mix(c, ega[(best + int(u_paletteShift)) % 16], u_paletteMix);
  }
  if (u_hue != 0.0) c = hueRotate(c, u_hue);
  float lum = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(c, vec3(lum), u_grey);
  c = mix(c, clamp(lum * 1.6 * u_tint, 0.0, 1.0), u_tintMix);
  if (u_cga > 0.0) {
    int best = 0; float bd = 1e9;
    for (int i = 0; i < 4; i++) { float d = dot(c - cgaPal[i], c - cgaPal[i]); if (d < bd) { bd = d; best = i; } }
    c = mix(c, cgaPal[best], u_cga);
  }
  c = mix(c, 1.0 - c, u_invert);
  o = vec4(c, 1.0);
}`;

class Renderer {
  constructor(canvas, atlasImage) {
    const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, depth: false, stencil: false, preserveDrawingBuffer: false });
    if (!gl) throw new Error("WebGL2 is not available in this browser.");
    this.gl = gl;
    this.canvas = canvas;
    this.time = 0;
    this.seed = Math.random() * 1000;
    this.scrollAcc = [0, 0];
    this.pixelScale = 1;
    this.stampProg = this.program(STAMP_VS, STAMP_FS);
    this.canvasProg = this.program(FULL_VS, CANVAS_FS);
    this.postProg = this.program(FULL_VS, POST_FS);
    this.emptyVao = gl.createVertexArray();

    this.stampVao = gl.createVertexArray();
    gl.bindVertexArray(this.stampVao);
    this.stampBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.stampBuf);
    gl.bufferData(gl.ARRAY_BUFFER, MAX_STAMPS * 7 * 4, gl.DYNAMIC_DRAW);
    const attr = (loc, size, offset) => {
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 28, offset);
      gl.vertexAttribDivisor(loc, 1);
    };
    attr(0, 2, 0); attr(1, 1, 8); attr(2, 1, 12); attr(3, 3, 16);
    gl.bindVertexArray(null);

    this.atlasSize = [atlasImage.width, atlasImage.height];
    this.atlas = this.texture(atlasImage.width, atlasImage.height, atlasImage);
  }

  program(vs, fs) {
    const gl = this.gl;
    const compile = (type, src) => {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const p = gl.createProgram();
    gl.attachShader(p, compile(gl.VERTEX_SHADER, vs));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const uniforms = {};
    for (let i = 0; i < gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS); i++) {
      const name = gl.getActiveUniform(p, i).name;
      uniforms[name] = gl.getUniformLocation(p, name);
    }
    return { p, u: uniforms };
  }

  texture(w, h, source = null) {
    const gl = this.gl;
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    if (source) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, source);
    else gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, w, h);
    return t;
  }

  target(w, h) {
    const gl = this.gl, tex = this.texture(w, h), fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    return { tex, fb };
  }

  /** Returns true when the canvas was (re)made, which wipes it. */
  ensureTargets() {
    const w = this.canvas.width, h = this.canvas.height;
    if (w === 0 || h === 0 || (this.size && this.size[0] === w && this.size[1] === h)) return false;
    const gl = this.gl;
    for (const t of [this.canvasT, this.scratchT]) if (t) { gl.deleteTexture(t.tex); gl.deleteFramebuffer(t.fb); }
    this.canvasT = this.target(w, h);
    this.scratchT = this.target(w, h);
    this.size = [w, h];
    this.pixelScale = Math.max(1, Math.round(h / 540));
    return true;
  }

  get virtualSize() { return [this.size[0] / this.pixelScale, this.size[1] / this.pixelScale]; }

  render(engine, params, dt) {
    const gl = this.gl, [w, h] = this.size, look = params.look, ps = this.pixelScale;
    this.time += dt;
    gl.viewport(0, 0, w, h);

    gl.bindFramebuffer(gl.FRAMEBUFFER, this.canvasT.fb);
    if (engine.wipe) { gl.clearColor(0, 128 / 255, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT); }
    if (engine.stampCount > 0) {
      const { p, u } = this.stampProg;
      gl.useProgram(p);
      gl.bindVertexArray(this.stampVao);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.stampBuf);
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, engine.stamps, 0, engine.stampCount * 7);
      gl.uniform2f(u.u_virt, ...this.virtualSize);
      gl.uniform2f(u.u_atlasSize, ...this.atlasSize);
      gl.uniform2f(u.u_off, ...look.atlasOffset);
      gl.uniform1f(u.u_stride, look.strideExtra);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.atlas);
      gl.uniform1i(u.u_atlas, 0);
      gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, engine.stampCount);
    }

    const ops = engine.canvasOps.map(op => ({ ...op }));
    this.scrollAcc[0] += look.scroll[0] * dt * ps;
    this.scrollAcc[1] += look.scroll[1] * dt * ps;
    const whole = this.scrollAcc.map(Math.trunc);
    if (whole[0] || whole[1]) {
      this.scrollAcc = [this.scrollAcc[0] - whole[0], this.scrollAcc[1] - whole[1]];
      ops.push({ mode: 2, dx: whole[0], dy: whole[1], pixels: true });
    }
    for (const op of ops) this.canvasPass(op);

    const { p, u } = this.postProg;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.useProgram(p);
    gl.bindVertexArray(this.emptyVao);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.canvasT.tex);
    gl.uniform1i(u.u_src, 0);
    gl.uniform2f(u.u_tex, w, h);
    gl.uniform1f(u.u_time, this.time);
    gl.uniform1f(u.u_seed, this.seed);
    gl.uniform1f(u.u_hue, look.hue);
    gl.uniform1f(u.u_paletteMix, look.paletteMix);
    gl.uniform1f(u.u_paletteShift, Math.max(0, look.paletteShift));
    gl.uniform1f(u.u_invert, look.invert);
    gl.uniform1f(u.u_split, look.rgbSplit * ps);
    gl.uniform1f(u.u_tear, look.tear);
    gl.uniform1f(u.u_feltMix, look.feltMix);
    gl.uniform3f(u.u_feltTint, ...look.feltTint);
    gl.uniform1f(u.u_pixelScale, ps);
    gl.uniform1f(u.u_tintMix, look.tintMix);
    gl.uniform3f(u.u_tint, ...look.tint);
    gl.uniform1f(u.u_grey, look.grey);
    gl.uniform1f(u.u_cga, look.cga);
    gl.uniform1f(u.u_flipX, look.flipX ? 1 : 0);
    gl.uniform1f(u.u_flipY, look.flipY ? 1 : 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  canvasPass(op) {
    const gl = this.gl, ps = this.pixelScale, { p, u } = this.canvasProg;
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.scratchT.fb);
    gl.useProgram(p);
    gl.bindVertexArray(this.emptyVao);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.canvasT.tex);
    gl.uniform1i(u.u_src, 0);
    gl.uniform1i(u.u_mode, op.mode);
    gl.uniform2f(u.u_tex, ...this.size);
    gl.uniform1f(u.u_seed, op.seed ?? 0);
    gl.uniform1f(u.u_bands, op.mode === 4 ? (op.bands ?? 1) * ps : op.bands ?? 0);
    gl.uniform1f(u.u_amount, (op.amount ?? 0) * ps);
    gl.uniform1f(u.u_dx, op.dx ?? 0);
    gl.uniform1f(u.u_dy, op.dy ?? 0);
    const r = op.rect ?? [0, 0, 0, 0];
    gl.uniform4f(u.u_rect, r[0] * ps, r[1] * ps, r[2] * ps, r[3] * ps);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    [this.canvasT, this.scratchT] = [this.scratchT, this.canvasT];
  }
}

// ---------------------------------------------------------------- page

// The sprite sheet's background green shows through at card corners and in empty cells.
async function loadAtlas(url) {
  const img = new Image();
  img.src = url;
  await img.decode();
  const c = document.createElement("canvas");
  c.width = img.width;
  c.height = img.height;
  const ctx = c.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);
  const data = ctx.getImageData(0, 0, c.width, c.height);
  const px = data.data;
  for (let i = 0; i < px.length; i += 4) if (px[i] === 0 && px[i + 1] === 99 && px[i + 2] === 0) px[i + 3] = 0;
  return data;
}

export async function start(canvas, { status, atlasUrl = "cards.png", onError } = {}) {
  let renderer;
  try {
    renderer = new Renderer(canvas, await loadAtlas(atlasUrl));
  } catch (e) {
    onError?.(e);
    return null;
  }
  const params = new URLSearchParams(location.search);
  const seed = Number(params.get("seed")) || Math.floor(Math.random() * 2 ** 31);
  const rng = makeRng(seed);
  const engine = new Engine(rng);
  const director = new Director(rng, { rampMinutes: Number(params.get("ramp")) || 8 });
  if (params.has("fast")) director.clockSpeed = 10;
  if (params.has("chaos")) director.chaosOverride = clamp01(Number(params.get("chaos")));
  let paused = false, last = null, showNames = false;

  const resize = () => {
    const dpr = window.devicePixelRatio || 1;
    const w = Math.round(canvas.clientWidth * dpr), h = Math.round(canvas.clientHeight * dpr);
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
  };

  const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
  const advance = dt => {
    resize();
    if (renderer.ensureTargets()) engine.resize(...renderer.virtualSize);
    let p = defaultParams();
    if (!paused) {
      p = director.update(dt, engine);
      engine.frame(dt, p.physics);
    }
    renderer.render(engine, p, paused ? 0 : dt);
    engine.clearOutput();
  };
  // Test hooks: ?effect=name,name starts effects at once; ?warmup=seconds runs that long before the first frame.
  advance(1 / 60);
  for (const name of (params.get("effect") ?? "").split(",").filter(Boolean)) {
    const spec = FX.find(s => s.name === name);
    if (spec) director.start(spec, 1, 3, engine);
  }
  for (let t = 0; t < (Number(params.get("warmup")) || 0); t += 1 / 60) advance(1 / 60);
  const tick = now => {
    const dt = last === null ? 1 / 60 : Math.min((now - last) / 1000, 0.1);
    last = now;
    advance(dt);
    if (status) {
      const names = showNames ? " · " + director.active.map(a => a.spec.name).join(", ") : "";
      status.textContent = `${paused ? "Paused" : "Running"} · ${fmt(director.now)} · chaos ${director.chaos.toFixed(2)}${director.clockSpeed > 1 ? " · ×10" : ""}${names}`;
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);

  const controls = {
    togglePause: () => { paused = !paused; },
    toggleFast: () => { director.clockSpeed = director.clockSpeed > 1 ? 1 : 10; return director.clockSpeed > 1; },
    restart: () => { director.active = []; engine.restart(); },
    reboot: () => { director.rebootLeft = 1.2; },
    key(k) {
      if (k === " ") paused = !paused;
      else if ("12345".includes(k)) director.force(FAMILIES[Number(k) - 1], engine);
      else if (k === "0") director.active = [];
      else if (k === "=" || k === "+") director.chaosOverride = Math.min(1, (director.chaosOverride ?? director.chaos) + 0.1);
      else if (k === "-") director.chaosOverride = Math.max(0, (director.chaosOverride ?? director.chaos) - 0.1);
      else if (k === "a") director.chaosOverride = null;
      else if (k === "f") director.clockSpeed = director.clockSpeed > 1 ? 1 : 10;
      else if (k === "r") director.rebootLeft = 1.2;
      else if (k === "d") showNames = !showNames;
      else return false;
      return true;
    },
  };
  return controls;
}
