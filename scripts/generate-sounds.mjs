#!/usr/bin/env node
// Renders the procedural sound effects in game/audio/. Every file is an
// original synthesis from a small physical model (firing pulses through an
// exhaust, stones under a tyre, a struck bell...), so the game ships no
// third-party recordings. Rendering is deterministic: each sound has its own
// seeded random stream. Loops end where they begin (crossfaded tail), so the
// importer can loop them without a click.
//
//   node scripts/generate-sounds.mjs            # every sound
//   node scripts/generate-sounds.mjs step siren # only names starting so
//
// The engine reference revs (ENGINE_RPM) are mirrored in
// game/scripts/cars/vehicle_audio.gd, which pitches the loops to the
// simulated rpm. Each file gets an .import sidecar with its loop mode
// (2, forward, for loops); the Godot import fills in the rest.
import { existsSync } from 'node:fs';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RATE = 32000;
const OUT = join(fileURLToPath(new URL('..', import.meta.url)), 'game', 'audio');
export const ENGINE_RPM = { low: 1500, high: 5000 };

// ---------------------------------------------------------------- DSP kit

function random(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function seedOf(name) {
  let h = 2166136261;
  for (const c of name) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return h >>> 0;
}

// RBJ biquad; 'bp' has 0 dB gain at the centre.
function biquad(type, freq, q = 0.707, gainDb = 0) {
  const w = 2 * Math.PI * Math.min(freq, RATE * 0.45) / RATE;
  const cos = Math.cos(w), alpha = Math.sin(w) / (2 * q), A = 10 ** (gainDb / 40);
  let b0, b1, b2, a0, a1, a2;
  if (type === 'lp') { b0 = (1 - cos) / 2; b1 = 1 - cos; b2 = b0; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; }
  else if (type === 'hp') { b0 = (1 + cos) / 2; b1 = -(1 + cos); b2 = b0; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; }
  else if (type === 'bp') { b0 = alpha; b1 = 0; b2 = -alpha; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; }
  else { b0 = 1 + alpha * A; b1 = -2 * cos; b2 = 1 - alpha * A; a0 = 1 + alpha / A; a1 = -2 * cos; a2 = 1 - alpha / A; }
  const c0 = b0 / a0, c1 = b1 / a0, c2 = b2 / a0, d1 = a1 / a0, d2 = a2 / a0;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return x => {
    const y = c0 * x + c1 * x1 + c2 * x2 - d1 * y1 - d2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

function run(buffer, ...filters) {
  for (const f of filters) for (let i = 0; i < buffer.length; i++) buffer[i] = f(buffer[i]);
  return buffer;
}

function filtered(source, ...filters) {
  return run(Float32Array.from(source), ...filters);
}

function mix(target, source, gain = 1, offset = 0) {
  for (let i = 0; i < source.length && i + offset < target.length; i++) {
    if (i + offset >= 0) target[i + offset] += source[i] * gain;
  }
  return target;
}

function noise(length, rnd) {
  const out = new Float32Array(length);
  for (let i = 0; i < length; i++) out[i] = rnd() * 2 - 1;
  return out;
}

// Smoothed random walk in 0..1: slow variation of a texture.
function drift(length, rnd, rate) {
  const out = new Float32Array(length);
  const smooth = biquad('lp', rate, 0.6);
  let value = 0;
  for (let i = 0; i < length; i++) {
    if (i % 64 === 0) value = rnd();
    out[i] = smooth(value);
  }
  return out;
}

// A short resonant "tick": a few damped modes, e.g. a stone or a latch.
function modes(length, list, rnd = null) {
  const out = new Float32Array(length);
  for (const [freq, decay, gain] of list) {
    const phase = rnd ? rnd() * Math.PI * 2 : 0;
    for (let i = 0; i < length; i++) {
      const t = i / RATE;
      out[i] += Math.sin(2 * Math.PI * freq * t + phase) * Math.exp(-t / decay) * gain;
    }
  }
  return out;
}

function envelope(buffer, fn) {
  for (let i = 0; i < buffer.length; i++) buffer[i] *= fn(i / RATE);
  return buffer;
}

// Loops render PRE seconds of warm-up (filters settling), then `seconds` of
// body and FADE more, which is crossfaded into the head so the end runs into
// the start without a click.
const PRE = 0.2, FADE = 0.08;
const loopSamples = seconds => Math.round((PRE + seconds + FADE) * RATE);

function closeLoop(buffer, seconds) {
  const pre = Math.round(PRE * RATE), n = Math.round(seconds * RATE), xf = Math.round(FADE * RATE);
  const out = buffer.slice(pre, pre + n);
  for (let i = 0; i < xf; i++) {
    const k = i / xf;
    out[i] = buffer[pre + i] * k + buffer[pre + n + i] * (1 - k);
  }
  return out;
}

function rms(buffer) {
  let sum = 0;
  for (const v of buffer) sum += v * v;
  return Math.sqrt(sum / buffer.length);
}

function peak(buffer) {
  let p = 0;
  for (const v of buffer) p = Math.max(p, Math.abs(v));
  return p;
}

// Loops are levelled by loudness, one-shots by peak; a soft knee catches peaks.
// A loop loses its DC offset by subtraction (a filter would start with a
// transient and break the seam), a one-shot through a high-pass.
function level(buffer, { loudness = null, top = 0.89 } = {}) {
  if (loudness !== null) {
    const mean = buffer.reduce((sum, v) => sum + v, 0) / buffer.length;
    for (let i = 0; i < buffer.length; i++) buffer[i] -= mean;
  } else {
    run(buffer, biquad('hp', 25, 0.7));
  }
  const gain = loudness !== null ? loudness / Math.max(rms(buffer), 1e-9) : top / Math.max(peak(buffer), 1e-9);
  for (let i = 0; i < buffer.length; i++) {
    const v = buffer[i] * gain;
    buffer[i] = Math.abs(v) < 0.8 ? v : Math.sign(v) * (0.8 + 0.19 * Math.tanh((Math.abs(v) - 0.8) / 0.19));
  }
  return buffer;
}

function fadeEdges(buffer, inSeconds = 0.002, outSeconds = 0.02) {
  const a = Math.round(inSeconds * RATE), b = Math.round(outSeconds * RATE);
  for (let i = 0; i < a && i < buffer.length; i++) buffer[i] *= i / a;
  for (let i = 0; i < b && i < buffer.length; i++) buffer[buffer.length - 1 - i] *= i / b;
  return buffer;
}

function wav(buffer) {
  const data = Buffer.alloc(buffer.length * 2);
  for (let i = 0; i < buffer.length; i++) data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buffer[i])) * 32767), i * 2);
  const head = Buffer.alloc(44);
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVE', 8);
  head.write('fmt ', 12); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22);
  head.writeUInt32LE(RATE, 24); head.writeUInt32LE(RATE * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34);
  head.write('data', 36); head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

const samples = seconds => Math.round(seconds * RATE);

// ---------------------------------------------------------------- engines

// Exhaust note of a piston engine: every firing is a pressure pulse (fast rise,
// short decay) plus a burst of combustion noise, sent through the resonances
// of the exhaust. Cylinder-to-cylinder spread and the firing order give each
// engine its beat: an uneven boxer burbles, a five warbles, a V6 sings.
export const ENGINES = {
  // Everyday cars: quiet silencer, little rasp.
  sedan: { cylinders: 4, spread: 0.16, decay: 0.0036, noise: 0.25, rasp: 0.04, body: 260,
    resonances: [[135, 1.4, 1], [290, 2, 0.45], [690, 2, 0.16], [1700, 1.5, 0.05]] },
  utility: { cylinders: 4, spread: 0.3, decay: 0.0045, noise: 0.3, rasp: 0.06, body: 220, knock: 0.08,
    resonances: [[115, 1.3, 1], [250, 2, 0.55], [600, 2, 0.22], [1500, 1.5, 0.06]] },
  kei: { cylinders: 3, spread: 0.22, decay: 0.003, noise: 0.28, rasp: 0.06, body: 300,
    resonances: [[160, 1.5, 1], [370, 2.2, 0.5], [880, 2, 0.2], [2100, 1.5, 0.06]] },
  diesel: { cylinders: 4, spread: 0.14, decay: 0.005, noise: 0.2, rasp: 0.03, body: 200, knock: 0.55,
    resonances: [[105, 1.3, 1], [240, 2, 0.45], [560, 2, 0.12]] },
  // Rally engines: free-flowing exhausts, raspy, some turbocharged.
  i4: { cylinders: 4, spread: 0.18, decay: 0.0028, noise: 0.38, rasp: 0.32, body: 380,
    resonances: [[170, 1.6, 1], [390, 2.6, 0.75], [920, 2.2, 0.4], [2300, 1.6, 0.18]] },
  i4t: { cylinders: 4, spread: 0.15, decay: 0.0034, noise: 0.42, rasp: 0.16, body: 300, turbo: 0.05, whistle: 3300,
    resonances: [[150, 1.5, 1], [340, 2.2, 0.6], [820, 2, 0.28], [2000, 1.5, 0.1]] },
  i5: { cylinders: 5, spread: 0.24, decay: 0.003, noise: 0.36, rasp: 0.3, body: 340, turbo: 0.03, whistle: 2900,
    offsets: [0, 0.012, -0.009, 0.011, -0.006],
    resonances: [[150, 1.6, 1], [330, 2.3, 0.85], [760, 2.2, 0.42], [1900, 1.6, 0.2]] },
  boxer: { cylinders: 4, spread: 0.2, decay: 0.0036, noise: 0.4, rasp: 0.18, body: 260, turbo: 0.045, whistle: 3600,
    order: [0, 0.19, 0.5, 0.69],
    resonances: [[120, 1.4, 1], [285, 2, 0.75], [690, 2, 0.32], [1750, 1.5, 0.1]] },
  v6: { cylinders: 6, spread: 0.1, decay: 0.0024, noise: 0.3, rasp: 0.38, body: 420,
    resonances: [[225, 1.6, 1], [520, 2.6, 0.85], [1300, 2.2, 0.5], [3200, 1.6, 0.24]] },
};

// rpm: a number (loops) or a function of time (start-up). load 0..1.
function engine(spec, { seconds, rpm, load, seed, loop = true, muffle = [] }) {
  const rnd = random(seed);
  const total = loop ? loopSamples(seconds) : samples(seconds);
  const excite = new Float32Array(total);
  const burst = new Float32Array(total);
  const knock = new Float32Array(total);
  const rpmAt = typeof rpm === 'function' ? rpm : () => rpm;
  const loadAt = typeof load === 'function' ? load : () => load;
  const order = spec.order ?? Array.from({ length: spec.cylinders }, (_, k) => k / spec.cylinders);
  const bias = order.map((_, k) => 1 + (spec.offsets ? spec.offsets[k] * 8 : 0));
  const pulseLength = samples(0.03);
  let t = 0;
  while (t < total / RATE) {
    const period = 120 / Math.max(rpmAt(t), 60);
    const cycleLoad = loadAt(t);
    order.forEach((phase, k) => {
      const at = t + (phase + (spec.offsets?.[k] ?? 0)) * period;
      const start = Math.round(at * RATE);
      const amp = (0.25 + 0.75 * cycleLoad) * bias[k] * (1 + spec.spread * (rnd() * 2 - 1));
      const misfire = cycleLoad < 0.3 && rnd() < 0.05 ? 0.3 : 1;
      const n = Math.min(pulseLength, Math.round(period / order.length * 2.5 * RATE));
      for (let i = 0; i < n && start + i < total; i++) {
        if (start + i < 0) continue;
        const dt = i / RATE;
        excite[start + i] += amp * misfire * (Math.exp(-dt / spec.decay) - Math.exp(-dt / 0.00035));
        burst[start + i] += amp * (rnd() * 2 - 1) * Math.exp(-dt / (spec.decay * 0.7));
        if (spec.knock) knock[start + i] += (rnd() * 2 - 1) * Math.exp(-dt / 0.0009) * amp;
      }
    });
    t += period;
  }
  const out = new Float32Array(total);
  const source = new Float32Array(total);
  for (let i = 0; i < total; i++) source[i] = excite[i] + burst[i] * spec.noise;
  for (const [freq, q, gain] of spec.resonances) mix(out, filtered(source, biquad('bp', freq, q)), gain * 2.2);
  mix(out, filtered(excite, biquad('lp', spec.body, 0.8)), 0.9);
  // Rasp: the hot, distorted top of a free exhaust; comes with load.
  const raspy = new Float32Array(total);
  for (let i = 0; i < total; i++) raspy[i] = Math.tanh(out[i] * 3);
  run(raspy, biquad('hp', 1400, 0.7), biquad('lp', 7000, 0.7));
  for (let i = 0; i < total; i++) out[i] += raspy[i] * spec.rasp * (0.3 + 0.7 * loadAt(i / RATE));
  if (spec.knock) mix(out, filtered(knock, biquad('bp', 2600, 1.2)), spec.knock);
  // Intake and mechanical hiss under everything.
  const hiss = filtered(noise(total, rnd), biquad('bp', 900, 0.8));
  const intakeLevel = drift(total, rnd, 6);
  for (let i = 0; i < total; i++) out[i] += hiss[i] * (0.04 + 0.03 * intakeLevel[i]) * (0.5 + loadAt(i / RATE));
  if (spec.turbo) {
    let phase = 0;
    for (let i = 0; i < total; i++) {
      const tt = i / RATE;
      const spool = loadAt(tt);
      phase += 2 * Math.PI * spec.whistle * (1 + 0.004 * Math.sin(2 * Math.PI * 3.1 * tt)) / RATE;
      out[i] += Math.sin(phase) * spec.turbo * 0.6 * (0.25 + 0.75 * spool);
    }
  }
  run(out, biquad('lp', 9000, 0.7), ...muffle);
  return loop ? closeLoop(out, seconds) : out;
}

// Overrun: off the throttle the note drops and the exhaust spits.
function overrun(spec, options) {
  const out = engine(spec, { ...options, load: 0.08, muffle: [biquad('lp', 2400, 0.7), biquad('peak', 180, 1, 3)] });
  const rnd = random(options.seed + 7);
  const crackle = new Float32Array(out.length);
  const count = Math.round(options.seconds * (spec.rasp > 0.15 ? 9 : 0));
  for (let k = 0; k < count; k++) {
    const at = Math.floor(rnd() * (out.length - 600));
    const amp = 0.4 + rnd() * 0.8;
    for (let i = 0; i < 400; i++) crackle[at + i] += (rnd() * 2 - 1) * amp * Math.exp(-i / 60);
  }
  run(crackle, biquad('bp', 1100, 0.9));
  return mix(out, crackle, rms(out) * 2.2);
}

// ---------------------------------------------------------------- one-shots

// Loose stones and grit: a rain of small pings and crunches.
function grains(length, rnd, { rate, band, q = 1.5, decay, sizeSpread = 1 }) {
  const out = new Float32Array(length);
  const count = Math.round(rate * length / RATE);
  for (let k = 0; k < count; k++) {
    const at = Math.floor(rnd() * length);
    const amp = Math.pow(rnd(), 2.5) * sizeSpread + 0.05;
    const n = Math.round(decay * RATE * (0.5 + rnd()));
    for (let i = 0; i < n * 5 && at + i < length; i++) out[at + i] += (rnd() * 2 - 1) * amp * Math.exp(-i / n);
  }
  const lo = filtered(out, biquad('bp', band[0], q));
  const hi = filtered(out, biquad('bp', band[1], q));
  return mix(lo, hi, 0.7);
}


function thump(length, freq, decay, rnd) {
  const out = new Float32Array(length);
  let phase = 0;
  for (let i = 0; i < length; i++) {
    const t = i / RATE;
    phase += 2 * Math.PI * freq * (1 + 0.8 * Math.exp(-t / 0.01)) / RATE;
    out[i] = Math.sin(phase) * Math.exp(-t / decay);
  }
  const body = filtered(noise(length, rnd), biquad('lp', freq * 3, 0.7));
  return mix(out, envelope(body, t => Math.exp(-t / (decay * 0.6))), 0.5);
}

function burstAt(target, at, seconds, decay, rnd, ...filters) {
  const n = samples(seconds);
  const b = envelope(noise(n, rnd), t => Math.exp(-t / decay));
  mix(target, filtered(b, ...filters), 1, Math.round(at * RATE));
  return target;
}

function door(seed) {
  const rnd = random(seed);
  const out = new Float32Array(samples(1.1));
  // Handle and latch release.
  mix(out, modes(samples(0.05), [[2300, 0.008, 0.4], [3700, 0.006, 0.3], [5200, 0.004, 0.2]], rnd), 0.6, samples(0.02));
  burstAt(out, 0.02, 0.03, 0.004, rnd, biquad('bp', 3000, 1.2));
  // The slam: a heavy low thump, the panel ringing, the latch catching.
  const slam = samples(0.6);
  mix(out, thump(samples(0.4), 75, 0.07, rnd), 1, slam);
  mix(out, modes(samples(0.3), [[310, 0.06, 0.4], [470, 0.05, 0.3], [690, 0.04, 0.2], [1130, 0.03, 0.12]], rnd), 0.6, slam);
  mix(out, modes(samples(0.05), [[2900, 0.006, 0.4], [4400, 0.004, 0.3]], rnd), 0.7, slam + samples(0.004));
  burstAt(out, 0.6, 0.1, 0.012, rnd, biquad('bp', 1600, 0.8));
  return fadeEdges(out);
}

function trunk(open, seed) {
  const rnd = random(seed);
  const out = new Float32Array(samples(open ? 0.9 : 0.7));
  if (open) {
    // Latch pop, then gas struts lifting the lid.
    mix(out, modes(samples(0.05), [[1900, 0.01, 0.5], [3100, 0.006, 0.3]], rnd), 0.7);
    mix(out, thump(samples(0.15), 120, 0.03, rnd), 0.4);
    const hiss = envelope(filtered(noise(samples(0.7), rnd), biquad('bp', 2600, 0.7)), t => Math.sin(Math.PI * Math.min(t / 0.7, 1)) * 0.07);
    mix(out, hiss, 1, samples(0.1));
  } else {
    mix(out, thump(samples(0.45), 65, 0.09, rnd), 1, samples(0.02));
    mix(out, modes(samples(0.35), [[240, 0.08, 0.4], [410, 0.06, 0.3], [820, 0.04, 0.15]], rnd), 0.5, samples(0.02));
    mix(out, modes(samples(0.05), [[3100, 0.005, 0.4]], rnd), 0.6, samples(0.025));
  }
  return fadeEdges(out);
}

function engineStart(spec, seed) {
  const rnd = random(seed);
  const seconds = 1.9;
  const out = new Float32Array(samples(seconds));
  // Starter: a geared electric motor buzzing, slowed by every compression
  // stroke, and the dull thud of each piston coming up.
  const crank = samples(0.75);
  const strokes = 8.5;
  const motor = new Float32Array(crank);
  let phase = 0;
  for (let i = 0; i < crank; i++) {
    const t = i / RATE;
    const stroke = 0.5 + 0.5 * Math.cos(2 * Math.PI * strokes * t);
    phase += (95 * (1 - 0.2 * stroke) * (0.75 + 0.25 * Math.min(t / 0.12, 1))) / RATE;
    motor[i] = (2 * (phase % 1) - 1) * (0.55 + 0.45 * stroke) * Math.min(t / 0.02, 1);
  }
  run(motor, biquad('bp', 380, 0.8), biquad('lp', 1400, 0.7));
  mix(out, motor, 0.5);
  for (let k = 0; k / strokes < 0.7; k++) mix(out, thump(samples(0.1), 55, 0.03, rnd), 0.55, samples(0.01 + k / strokes));
  mix(out, envelope(filtered(noise(crank, rnd), biquad('lp', 260, 0.8)), t => 0.5 + 0.5 * Math.cos(2 * Math.PI * strokes * t)), 0.3);
  // Catch: the engine fires, flares and settles to idle.
  const fire = engine(spec, {
    seconds: seconds - 0.62, seed, loop: false,
    rpm: t => (t < 0.25 ? 600 + 5200 * t : 1900 - 900 * Math.min((t - 0.25) / 0.6, 1)),
    load: t => (t < 0.25 ? 0.9 : 0.3),
  });
  envelope(fire, t => Math.min(t / 0.05, 1));
  const firePeak = peak(fire) || 1;
  mix(out, fire, 0.55 / firePeak, samples(0.62));
  envelope(out, t => (t > seconds - 0.4 ? (seconds - t) / 0.4 : 1));
  return fadeEdges(out);
}

function crash(heavy, seed) {
  const rnd = random(seed);
  const seconds = heavy ? 1.4 : 0.6;
  const out = new Float32Array(samples(seconds));
  mix(out, thump(samples(0.5), heavy ? 48 : 70, heavy ? 0.12 : 0.06, rnd), 1);
  // Sheet metal: many inharmonic modes, struck and bending.
  const sheet = [];
  for (let k = 0; k < (heavy ? 14 : 8); k++) sheet.push([250 + rnd() * 2600, 0.02 + rnd() * (heavy ? 0.12 : 0.05), 0.2 + rnd() * 0.4]);
  mix(out, modes(samples(seconds), sheet, rnd), 0.35);
  // Crunch: a dense, decaying scatter of tearing and plastic cracking.
  const crunch = grains(samples(heavy ? 0.6 : 0.25), rnd, { rate: heavy ? 1500 : 700, band: [700, 2600], decay: 0.002 });
  envelope(crunch, t => Math.exp(-t / (heavy ? 0.15 : 0.06)));
  mix(out, crunch, 1.4);
  if (heavy) {
    // Glass and loose bits settling.
    for (let k = 0; k < 14; k++) {
      const at = 0.15 + Math.pow(rnd(), 1.5) * 0.9;
      mix(out, modes(samples(0.08), [[3500 + rnd() * 4000, 0.01 + rnd() * 0.02, 0.15 + rnd() * 0.2]], rnd), 0.8 * Math.exp(-at * 2), samples(at));
    }
  }
  return fadeEdges(out, 0.001, 0.05);
}

function bodyThud(seed) {
  const rnd = random(seed);
  const out = thump(samples(0.35), 90, 0.05, rnd);
  burstAt(out, 0.0, 0.12, 0.02, rnd, biquad('lp', 900, 0.7));
  burstAt(out, 0.06, 0.1, 0.02, rnd, biquad('bp', 1400, 0.6), biquad('lp', 2500, 0.7));
  return fadeEdges(out);
}

// Anti-lag / afterfire: fuel lighting in the hot exhaust, a bang or two.
function backfire(seed, count) {
  const rnd = random(seed);
  const out = new Float32Array(samples(0.5));
  let at = 0;
  for (let k = 0; k < count; k++) {
    const amp = k === 0 ? 1 : 0.5 + rnd() * 0.4;
    mix(out, thump(samples(0.12), 85 + rnd() * 30, 0.018, rnd), amp, samples(at));
    burstAt(out, at, 0.08, 0.006 + rnd() * 0.004, rnd, biquad('bp', 700 + rnd() * 600, 0.7));
    burstAt(out, at, 0.05, 0.003, rnd, biquad('hp', 2500, 0.7));
    at += 0.07 + rnd() * 0.08;
  }
  return fadeEdges(out);
}

// Sirens: a tone through a horn speaker (bandpassed square, slight overdrive).
function siren(kind) {
  const seconds = kind === 'police' ? 1.6 : 2.4;
  const n = loopSamples(seconds);
  const out = new Float32Array(n);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    let f;
    if (kind === 'police') {
      // Yelp: fast rising sweeps.
      const cycle = (t % 0.4) / 0.4;
      f = 620 + 760 * Math.sin(cycle * Math.PI / 2);
    } else {
      // Two-tone "hi-lo" of an ambulance.
      f = (t % 1.2) < 0.6 ? 935 : 680;
    }
    phase += 2 * Math.PI * f / RATE;
    const square = Math.tanh(Math.sin(phase) * 4);
    out[i] = square;
  }
  run(out, biquad('bp', 1100, 0.9), biquad('peak', 2300, 2, 4));
  for (let i = 0; i < n; i++) out[i] = Math.tanh(out[i] * 2);
  return closeLoop(out, seconds);
}

// The police "quack" (крякалка): two short throaty whoops through the same
// horn speaker, a fast rise and a slower fall, the second a little lower.
function sirenChirp() {
  const out = new Float32Array(samples(0.62));
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / RATE;
    const second = t >= 0.3;
    const u = second ? t - 0.3 : t;
    if (u > 0.26) continue;
    const top = second ? 1250 : 1400;
    const f = u < 0.04 ? 480 + (top - 480) * (u / 0.04) : 480 + (top - 480) * Math.exp(-(u - 0.04) / 0.07);
    phase += 2 * Math.PI * f / RATE;
    const gain = Math.min(1, u / 0.008) * Math.min(1, (0.26 - u) / 0.04);
    out[i] = Math.tanh(Math.sin(phase) * 5) * gain;
  }
  run(out, biquad('bp', 1000, 0.8), biquad('peak', 2300, 2, 4));
  for (let i = 0; i < out.length; i++) out[i] = Math.tanh(out[i] * 2.5);
  return fadeEdges(out);
}

function ropeHook(seed) {
  const rnd = random(seed);
  const out = new Float32Array(samples(0.6));
  mix(out, modes(samples(0.4), [[1450, 0.08, 0.4], [2980, 0.05, 0.3], [4300, 0.03, 0.2], [6100, 0.02, 0.1]], rnd), 0.7);
  mix(out, modes(samples(0.3), [[1520, 0.05, 0.3], [3200, 0.03, 0.2]], rnd), 0.5, samples(0.11));
  // Rope snapping taut: a creak.
  const creak = new Float32Array(samples(0.3));
  for (let i = 0; i < creak.length; i++) {
    const t = i / RATE;
    if (i % Math.round(RATE / (90 + 40 * t)) === 0) creak[i] = 1;
  }
  run(creak, biquad('bp', 900, 3));
  envelope(creak, t => Math.sin(Math.PI * t / 0.3));
  mix(out, creak, 0.5, samples(0.22));
  return fadeEdges(out);
}

// ---------------------------------------------------------------- people and camp

function step(surface, variant) {
  const rnd = random(seedOf(`step-${surface}-${variant}`));
  const out = new Float32Array(samples(0.3));
  const heel = 0.0, toe = 0.05 + rnd() * 0.03;
  if (surface === 'gravel') {
    for (const [at, amp] of [[heel, 1], [toe, 0.7]]) {
      const g = grains(samples(0.14), rnd, { rate: 3500, band: [1100, 3400], decay: 0.0011 });
      envelope(g, t => Math.exp(-t / 0.035));
      mix(out, g, amp, samples(at));
      mix(out, thump(samples(0.08), 95, 0.015, rnd), 0.35 * amp, samples(at));
    }
  } else if (surface === 'snow') {
    for (const [at, amp] of [[heel, 0.8], [toe + 0.02, 1]]) {
      const g = grains(samples(0.2), rnd, { rate: 1800, band: [800, 2100], q: 3, decay: 0.003 });
      envelope(g, t => Math.sin(Math.PI * Math.min(t / 0.13, 1)));
      mix(out, g, amp, samples(at));
    }
    mix(out, thump(samples(0.1), 80, 0.02, rnd), 0.25);
  } else if (surface === 'asphalt') {
    mix(out, thump(samples(0.08), 110, 0.012, rnd), 0.8);
    burstAt(out, heel, 0.04, 0.004, rnd, biquad('bp', 2200, 0.9));
    burstAt(out, toe, 0.05, 0.006, rnd, biquad('bp', 1500, 0.8));
  } else {
    // grass and forest floor: a soft press and a swish of stems.
    mix(out, thump(samples(0.1), 85, 0.02, rnd), 0.7);
    burstAt(out, heel, 0.16, 0.04, rnd, biquad('bp', 3200, 0.6));
    mix(out, envelope(grains(samples(0.12), rnd, { rate: 300, band: [500, 1800], decay: 0.003 }), t => Math.exp(-t / 0.04)), 0.6, samples(toe));
  }
  return fadeEdges(out);
}

function place(material, seed) {
  const rnd = random(seed);
  const out = new Float32Array(samples(0.6));
  if (material === 'wood') {
    mix(out, thump(samples(0.25), 120, 0.03, rnd), 0.7);
    mix(out, modes(samples(0.3), [[260, 0.05, 0.4], [520, 0.035, 0.3], [930, 0.02, 0.2], [1650, 0.012, 0.1]], rnd), 0.7);
    // Legs settling a moment later.
    mix(out, modes(samples(0.15), [[340, 0.03, 0.3], [780, 0.02, 0.2]], rnd), 0.35, samples(0.09));
  } else {
    mix(out, thump(samples(0.2), 100, 0.03, rnd), 0.6);
    mix(out, modes(samples(0.6), [[530, 0.18, 0.3], [1370, 0.12, 0.25], [2410, 0.08, 0.2], [3720, 0.05, 0.12]], rnd), 0.6);
    mix(out, modes(samples(0.3), [[610, 0.1, 0.2], [1730, 0.06, 0.15]], rnd), 0.35, samples(0.07));
  }
  return fadeEdges(out);
}

function eat(seed) {
  const rnd = random(seed);
  const out = new Float32Array(samples(0.7));
  // Bite: a short crunch; then two muffled chews.
  const bite = grains(samples(0.12), rnd, { rate: 2500, band: [1500, 4200], decay: 0.0009 });
  mix(out, envelope(bite, t => Math.exp(-t / 0.03)), 1);
  for (const at of [0.28, 0.5]) burstAt(out, at, 0.12, 0.03, rnd, biquad('bp', 500, 1.2), biquad('lp', 1200, 0.7));
  return fadeEdges(out);
}

// Songbirds: tonal phrases with fast pitch contours and a faint harmonic.
function bird(variant) {
  const rnd = random(seedOf(`bird-${variant}`));
  const phrases = [
    // Finch-like: an accelerating, descending trill ending in a flourish.
    () => {
      const notes = [];
      let t = 0, f = 5200;
      for (let k = 0; k < 11; k++) { notes.push([t, 0.05 - k * 0.002, f, f - 900, 0.8]); t += 0.075 - k * 0.003; f -= 140; }
      notes.push([t + 0.03, 0.16, 3100, 4600, 1]);
      return notes;
    },
    // Tit-like "tee-cher" pairs.
    () => {
      const notes = [];
      for (let k = 0; k < 3; k++) {
        notes.push([k * 0.36, 0.11, 6400, 6200, 0.9]);
        notes.push([k * 0.36 + 0.14, 0.12, 4300, 3900, 1]);
      }
      return notes;
    },
    // Robin-like: varied liquid warble.
    () => {
      const notes = [];
      let t = 0;
      for (let k = 0; k < 9; k++) {
        const f = 2600 + rnd() * 3400, len = 0.05 + rnd() * 0.09;
        notes.push([t, len, f, f + (rnd() - 0.5) * 2400, 0.5 + rnd() * 0.5]);
        t += len + 0.02 + rnd() * 0.05;
      }
      return notes;
    },
  ];
  const notes = phrases[variant]();
  const end = Math.max(...notes.map(n => n[0] + n[1])) + 0.05;
  const out = new Float32Array(samples(end));
  for (const [at, len, f0, f1, amp] of notes) {
    const n = samples(len);
    let phase = 0;
    for (let i = 0; i < n; i++) {
      const k = i / n;
      const f = f0 + (f1 - f0) * k + 180 * Math.sin(2 * Math.PI * 70 * i / RATE) * (variant === 2 ? 1 : 0.3);
      phase += 2 * Math.PI * f / RATE;
      const env = Math.sin(Math.PI * k) ** 1.5;
      out[samples(at) + i] += (Math.sin(phase) + 0.12 * Math.sin(phase * 2)) * env * amp;
    }
  }
  return fadeEdges(out, 0.001, 0.01);
}

// Cicadas: tymbal clicks ringing a 5–7 kHz body, several insects in chorus.
function cicadas() {
  const rnd = random(seedOf('cicadas'));
  const seconds = 3.0;
  const out = new Float32Array(samples(seconds));
  for (let insect = 0; insect < 5; insect++) {
    const rate = 170 + rnd() * 90, freq = 5000 + rnd() * 1800, gain = 0.4 + rnd() * 0.6;
    const clicks = new Float32Array(out.length);
    const startAt = rnd() * 0.6, stopAt = seconds - rnd() * 0.6;
    for (let t = startAt; t < stopAt; t += 1 / rate * (0.97 + rnd() * 0.06)) {
      const swell = Math.sin(Math.PI * (t - startAt) / (stopAt - startAt));
      clicks[samples(t)] += swell * (0.7 + 0.3 * rnd());
    }
    mix(out, filtered(clicks, biquad('bp', freq, 9), biquad('bp', freq * 1.02, 6)), gain);
  }
  return fadeEdges(out, 0.05, 0.2);
}

// A cast bronze bell: hum, prime, minor-third tierce, quint, nominal and
// upper partials, each split in a slow-beating doublet; higher ones die faster.
function bell() {
  const rnd = random(seedOf('church-bell'));
  const seconds = 5.5;
  const out = new Float32Array(samples(seconds));
  const base = 360;
  const partials = [[0.5, 4.2, 0.55], [1.0, 3.0, 0.7], [1.19, 2.4, 0.5], [1.5, 1.8, 0.25], [2.0, 1.6, 0.6], [2.51, 0.9, 0.3], [2.66, 0.8, 0.25], [3.01, 0.6, 0.2], [4.17, 0.35, 0.15], [5.43, 0.22, 0.1]];
  for (const [ratio, decay, gain] of partials) {
    const split = 0.2 + rnd() * 0.5;
    for (const sign of [-1, 1]) {
      const f = base * ratio + sign * split;
      const phase = rnd() * Math.PI * 2;
      for (let i = 0; i < out.length; i++) {
        const t = i / RATE;
        out[i] += Math.sin(2 * Math.PI * f * t + phase) * Math.exp(-t / decay) * gain * 0.5;
      }
    }
  }
  // The clapper's strike.
  burstAt(out, 0, 0.05, 0.006, rnd, biquad('bp', 2400, 0.7));
  return fadeEdges(out, 0.001, 0.3);
}

// ---------------------------------------------------------------- catalogue

const LOOP = { loudness: 0.16 };
const sounds = {};
for (const [name, spec] of Object.entries(ENGINES)) {
  const seed = seedOf(name);
  sounds[`engine-${name}-low`] = () => level(engine(spec, { seconds: 1.2, rpm: ENGINE_RPM.low, load: 0.45, seed }), LOOP);
  sounds[`engine-${name}-on`] = () => level(engine(spec, { seconds: 1.2, rpm: ENGINE_RPM.high, load: 1, seed: seed + 1 }), LOOP);
  sounds[`engine-${name}-off`] = () => level(overrun(spec, { seconds: 1.2, rpm: ENGINE_RPM.high, seed: seed + 2 }), { loudness: 0.11 });
}
sounds['engine-start'] = () => level(engineStart(ENGINES.sedan, seedOf('engine-start')));
sounds['car-door'] = () => level(door(seedOf('car-door')));
sounds['trunk-open'] = () => level(trunk(true, seedOf('trunk-open')));
sounds['trunk-close'] = () => level(trunk(false, seedOf('trunk-close')));
sounds['crash-light'] = () => level(crash(false, seedOf('crash-light')));
sounds['crash-heavy'] = () => level(crash(true, seedOf('crash-heavy')));
sounds['body-thud'] = () => level(bodyThud(seedOf('body-thud')));
for (let k = 1; k <= 3; k++) sounds[`backfire-${k}`] = () => level(backfire(seedOf(`backfire-${k}`), k));
sounds['siren-police'] = () => level(siren('police'), LOOP);
sounds['siren-ambulance'] = () => level(siren('ambulance'), LOOP);
sounds['siren-chirp'] = () => level(sirenChirp());
sounds['rope-hook'] = () => level(ropeHook(seedOf('rope-hook')));
for (const surface of ['gravel', 'grass', 'snow', 'asphalt']) {
  for (let k = 1; k <= 3; k++) sounds[`step-${surface}-${k}`] = () => level(step(surface, k));
}
sounds['place-wood'] = () => level(place('wood', seedOf('place-wood')));
sounds['place-metal'] = () => level(place('metal', seedOf('place-metal')));
sounds['eat'] = () => level(eat(seedOf('eat')));
for (let k = 1; k <= 3; k++) sounds[`bird-${k}`] = () => level(bird(k - 1));
sounds['cicadas'] = () => level(cicadas());
sounds['church-bell'] = () => level(bell());

export const LOOPS = Object.keys(sounds).filter(name => /^(engine-.*-(low|on|off)|siren-(police|ambulance))/.test(name));

const SIDECAR = name => `[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="res://audio/${name}.wav"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=2
`;

async function sidecar(name) {
  const path = join(OUT, `${name}.wav.import`);
  const text = existsSync(path) ? await readFile(path, 'utf8') : SIDECAR(name);
  await writeFile(path, text.replace(/edit\/loop_mode=\d/, `edit/loop_mode=${LOOPS.includes(name) ? 2 : 0}`));
}

export async function generate(filter = []) {
  const names = Object.keys(sounds).filter(name => filter.length === 0 || filter.some(prefix => name.startsWith(prefix)));
  for (const name of names) {
    await writeFile(join(OUT, `${name}.wav`), wav(sounds[name]()));
    await sidecar(name);
  }
  return names;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const names = await generate(process.argv.slice(2));
  console.log(`Rendered ${names.length} sounds into game/audio/`);
}
