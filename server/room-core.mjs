import protocol from '../game/data/net_protocol.json' with { type: 'json' };
import { catalog } from './store.mjs';
// Limits and the action list come from the protocol file the game reads too.
export { protocol };
export const MAX_PLAYERS = protocol.max_players;
const LIMIT = protocol.limits;
const COLD_SECTIONS = LIMIT.cold_sections;
const SECTION = /^[a-z_]{1,24}$/;
const COMMANDS = new Set(protocol.actions);
// Content counts follow the catalog: a new stage or car needs no server change.
export const STAGE_COUNT = catalog.filter(p => p.type === 'stage').length;
export const CAR_COUNT = catalog.filter(p => p.type === 'car').length;
// The host's world is the game's own snapshot; the server checks its shape:
// a bounded number of plain top-level keys and a bounded serialized size.
const WORLD_KEY = /^[a-z_]{1,32}$/;
const WORLD_KEYS = 96;
export function validWorld(world) {
  if (!world || typeof world !== 'object' || Array.isArray(world)) return false;
  const keys = Object.keys(world);
  return keys.length <= WORLD_KEYS && keys.every(key => WORLD_KEY.test(key));
}
const vec = value => Array.isArray(value) && value.length === 3 && value.every(n => Number.isFinite(n) && Math.abs(n) < 3000);
const number = n => Number.isFinite(n) && Math.abs(n) < 100000;
export class RoomError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
export class RoomState {
  constructor(data = null) {
    this.data = data ?? { players: {}, host: '', world: null, commands: [], closed: false };
  }
  expire(now) {
    const d = this.data;
    if (d.host && (!d.players[d.host] || now - d.players[d.host].seen > 90000)) d.closed = true;
    for (const [id, p] of Object.entries(d.players)) if (id !== d.host && now - p.seen > 90000) delete d.players[id];
    d.commands = d.commands.filter(c => d.players[c.player]);
  }
  member(token) {
    const p = Object.values(this.data.players).find(p => p.token === token);
    if (!p) throw new RoomError(401, 'Участник не найден. Войди в комнату заново.');
    return p;
  }
  add(name, now, host = false, options = {}) {
    if (!host && (!this.data.host || this.data.closed)) throw new RoomError(404, 'Комната не найдена или закрыта.');
    if (host && this.data.host) throw new RoomError(409, 'Этот ID занят.');
    if (Object.keys(this.data.players).length >= MAX_PLAYERS) throw new RoomError(409, `Комната заполнена: максимум ${MAX_PLAYERS} игроков.`);
    const used = new Set(Object.values(this.data.players).map(p => p.slot));
    let slot = 0;
    while (used.has(slot)) slot++;
    const car_model = Number.isSafeInteger(options.car_model) && options.car_model >= 0 && options.car_model < CAR_COUNT ? options.car_model : slot;
    if (host) this.data.stage = Number.isSafeInteger(options.stage) ? Math.max(0, Math.min(STAGE_COUNT - 1, options.stage)) : 0;
    const id = crypto.randomUUID();
    const p = { id, slot, car_model, token: crypto.randomUUID(), name: String(name || 'Овощ').replace(/[\u0000-\u001f]/g, '').trim().slice(0, protocol.name_max_length) || 'Овощ', seen: now, state: null, seq: 0, protocol: Number.isSafeInteger(options.protocol) ? options.protocol : 0 };
    this.data.players[id] = p;
    if (host) this.data.host = id;
    return { player: id, token: p.token, host, name: p.name, slot, car_model, stage: this.data.stage ?? 0 };
  }
  // A guest's car is simulated by the host as soon as that guest has received
  // the host's world. Protocol 2 clients cannot opt out afterwards; older
  // clients keep reporting the flag themselves.
  driveEnabled(p, s) {
    if (p.id === this.data.host) return false;
    if ((p.protocol ?? 0) >= 2) return p.world_seen === true || s.drive_enabled === true;
    return s.drive_enabled === true;
  }
  rateLimit(player, action, now, limit, period) {
    player.limits ??= {};
    let bucket = player.limits[action];
    if (!bucket || now >= bucket.until) bucket = player.limits[action] = {count:0, until:now + period};
    if (bucket.count >= limit) {
      const error = new RoomError(429, 'Слишком много запросов. Подождите немного.');
      error.retryAfter = Math.max(1, Math.ceil((bucket.until - now) / 1000));
      throw error;
    }
    bucket.count++;
  }
  sync(body, now) {
    if (this.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
    const p = this.member(body.token);
    this.rateLimit(p, "sync", now, 150, 10000);
    const s = body.state;
    if (!s || !vec(s.pos) || !vec(s.car) || !number(s.heading) || !number(s.yaw) || !number(s.pitch) || typeof s.in_car !== 'boolean') throw new RoomError(400, 'Некорректное состояние игрока.');
    const drive_inputs = (Array.isArray(s.drive_inputs) ? s.drive_inputs.slice(0, LIMIT.drive_inputs_per_sync) : []).filter(c =>
      Number.isSafeInteger(c?.seq) && c.seq > 0 && Number.isSafeInteger(c.ticks) && c.ticks >= 1 && c.ticks <= LIMIT.ticks_per_input
      && Number.isFinite(c.throttle) && Math.abs(c.throttle) <= 1 && Number.isFinite(c.steer) && Math.abs(c.steer) <= 1 && typeof c.brake === 'boolean')
      .map(({seq,ticks,throttle,steer,brake,recover}) => ({seq,ticks,throttle,steer,brake, ...(recover === true ? {recover: true} : {})}));
    p.state = { drive_enabled: this.driveEnabled(p, s), drive_inputs, pos: s.pos, car: s.car, heading: s.heading, tilt: vec(s.tilt) ? s.tilt : [0, s.heading, 0], yaw: s.yaw, pitch: s.pitch, in_car: s.in_car, tow: s.tow === true && !s.in_car, push: vec(s.push) ? s.push.map((n, i) => i === 1 ? 0 : Math.max(-1, Math.min(1, n))) : [0, 0, 0], speed: number(s.speed) ? Math.max(-50, Math.min(50, s.speed)) : 0, beers: Number.isSafeInteger(s.beers) ? Math.max(0, Math.min(100000, s.beers)) : 0, trees: Array.isArray(s.trees) ? s.trees.slice(0, LIMIT.object_requests_per_sync).filter(t => Number.isSafeInteger(t?.id) && t.id >= 0 && t.id < 20000 && vec(t.dir)).map(t => ({ id: t.id, dir: t.dir })) : [], lamps: Array.isArray(s.lamps) ? s.lamps.slice(0, LIMIT.object_requests_per_sync).filter(t => Number.isSafeInteger(t?.id) && t.id >= 0 && t.id < 512 && vec(t.dir)).map(t => ({ id: t.id, dir: t.dir })) : [], seated: s.seated === true && !s.in_car, running: s.running === true && !s.in_car && s.seated !== true, airborne: s.airborne === true && !s.in_car && s.seated !== true, food_species: ['edible', 'fly_agaric', 'toadstool'].includes(s.food_species) ? s.food_species : 'edible', food_kind: ['meat', 'mushroom', 'berries', 'plov'].includes(s.food_kind) ? s.food_kind : 'meat', eat: Number.isFinite(s.eat) ? Math.max(-1, Math.min(protocol.durations.eat, s.eat)) : -1, beer: Math.max(-1, Math.min(protocol.durations.drink, Number(s.beer) || 0)) };
    p.seen = now;
    p.state_time = now;
    this.trackColdRevisions(p, body);
    if (p.id === this.data.host) {
      if (body.world !== undefined) {
        if (!validWorld(body.world)) throw new RoomError(400, 'Некорректный снимок мира.');
        this.data.world = body.world; this.data.world_time = now;
      }
      // Slowly changing world sections arrive only when their revision changes.
      const revisions = body.world?.cold_revs;
      if (body.cold && typeof body.cold === 'object' && !Array.isArray(body.cold) && revisions && typeof revisions === 'object') {
        for (const [section, value] of Object.entries(body.cold).slice(0, COLD_SECTIONS)) {
          if (!SECTION.test(section) || !Number.isSafeInteger(revisions[section])) continue;
          (this.data.cold ??= {})[section] = value;
          (this.data.cold_revs ??= {})[section] = revisions[section];
        }
      }
      const ack = new Set(Array.isArray(body.ack) ? body.ack.slice(0, LIMIT.acknowledgements_per_sync) : []);
      this.data.commands = this.data.commands.filter(c => !ack.has(c.id));
    } else {
      for (const c of (Array.isArray(body.commands) ? body.commands.slice(0, LIMIT.commands_per_sync) : [])) {
        if (!Number.isSafeInteger(c.seq) || c.seq <= p.seq || !COMMANDS.has(c.action)) continue;
        if (this.data.commands.length >= LIMIT.queued_commands) throw new RoomError(429, 'Подожди выполнения предыдущих действий.');
        const placement = {};
        // Point actions such as digging carry no yaw; a missing yaw means 0, an invalid one rejects the spot.
        const yaw = c.placement?.yaw === undefined ? 0 : c.placement.yaw;
        if (c.placement && vec(c.placement.pos) && number(yaw) && Math.hypot(...c.placement.pos.map((v, i) => v - p.state.pos[i])) <= 5) {
          placement.pos = c.placement.pos;
          placement.yaw = yaw;
        }
        if (Number.isSafeInteger(c.placement?.resource_id) && c.placement.resource_id >= 0 && c.placement.resource_id < 10000) placement.resource_id = c.placement.resource_id;
        if (Number.isSafeInteger(c.placement?.source) && c.placement.source >= -1 && c.placement.source < 100) placement.source = c.placement.source;
        this.data.commands.push({ id: `${p.id}:${c.seq}`, player: p.id, action: c.action, state: p.state, placement });
        p.seq = c.seq;
      }
    }
    return this.view(p, now);
  }
  // Snapshot as seen by one participant. Used for sync replies and for
  // WebSocket pushes, which deliver the same payload without a new request.
  view(p, now) {
    const hostId = this.data.host;
    const isHost = p.id === hostId;
    const host = this.data.players[hostId];
    const staleHost = !this.data.world_time || now - this.data.world_time > 3500;
    let world = this.data.world && typeof this.data.world === "object"
      ? (host?.background === true || staleHost
          ? {...this.data.world, paused: true}
          : this.data.world)
      : this.data.world;
    // The host authored the world and never reads it back.
    // From the first world a guest receives, the host simulates its car.
    if (!isHost && world && typeof world === 'object') p.world_seen = true;
    if (isHost) world = undefined;
    else if (world && typeof world === 'object' && this.data.cold) {
      if (p.cold_mode !== 'split') world = Object.assign({}, ...Object.values(this.data.cold), world);
      else {
        // Each section is resent until the participant reports its revision.
        const cold = {};
        p.cold_revs ??= {};
        for (const [section, revision] of Object.entries(this.data.cold_revs ?? {})) {
          if (p.cold_revs[section] === revision) continue;
          cold[section] = this.data.cold[section];
          p.cold_revs[section] = revision;
        }
        // Revisions describe what the server holds, not what the host claimed.
        world = {...world, cold_revs: {...(this.data.cold_revs ?? {})}, ...(Object.keys(cold).length ? {cold} : {})};
      }
    }
    // Raw drive inputs are only needed by the host, which simulates them.
    const players = Object.values(this.data.players).map(({ id, name, slot, car_model, state_time, state }) => ({ id, name, slot, car_model: car_model ?? slot, state_time: state_time ?? 0,
      state: state && !isHost && state.drive_inputs?.length ? {...state, drive_inputs: []} : state }));
    return { server_time: now, world_time: this.data.world_time ?? 0, stage: this.data.stage ?? 0, host: hostId, ...(world === undefined ? {} : {world}), accepted: p.seq,
      ...(isHost ? {cold_revs: this.data.cold_revs ?? {}} : {}),
      players, commands: isHost ? this.data.commands : [] };
  }
  // New clients report the cold sections they have applied; older clients
  // receive the slowly changing world inline with every snapshot.
  trackColdRevisions(p, body) {
    if (!Object.hasOwn(body, 'cold_revs')) return;
    p.cold_mode = 'split';
    p.cold_revs = {};
    const revisions = body.cold_revs && typeof body.cold_revs === 'object' && !Array.isArray(body.cold_revs) ? body.cold_revs : {};
    for (const [section, revision] of Object.entries(revisions).slice(0, COLD_SECTIONS)) {
      if (SECTION.test(section) && Number.isSafeInteger(revision)) p.cold_revs[section] = revision;
    }
  }
  heartbeat(token, now, background = false) {
    if (this.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
    const player = this.member(token);
    this.rateLimit(player, "heartbeat", now, 30, 60000);
    player.seen = now;
    if (player.id === this.data.host) player.background = background === true;
    return { alive: true };
  }
  leave(token) {
    const p = this.member(token);
    if (p.id === this.data.host) this.data.closed = true;
    delete this.data.players[p.id];
    this.data.commands = this.data.commands.filter(c => c.player !== p.id);
  }
}
