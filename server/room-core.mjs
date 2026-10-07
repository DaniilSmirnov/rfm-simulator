export const MAX_PLAYERS = 8;
const COMMANDS = new Set(['table', 'chairs', 'grill', 'flag', 'eat', 'rally', 'random_spot', 'collect', 'mount_mushroom', 'eat_mushroom', 'eat_berries', 'pack', 'trunk', 'take_gear', 'return_gear', 'firewood', 'cauldron', 'plov_cook', 'eat_plov']);
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
    if (Object.keys(this.data.players).length >= MAX_PLAYERS) throw new RoomError(409, 'Комната заполнена: максимум 8 игроков.');
    const used = new Set(Object.values(this.data.players).map(p => p.slot));
    let slot = 0;
    while (used.has(slot)) slot++;
    const car_model = Number.isSafeInteger(options.car_model) && options.car_model >= 0 && options.car_model < 10 ? options.car_model : slot;
    if (host) this.data.stage = Number.isSafeInteger(options.stage) ? Math.max(0, Math.min(2, options.stage)) : 0;
    const id = crypto.randomUUID();
    const p = { id, slot, car_model, token: crypto.randomUUID(), name: String(name || 'Овощ').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 24) || 'Овощ', seen: now, state: null, seq: 0 };
    this.data.players[id] = p;
    if (host) this.data.host = id;
    return { player: id, token: p.token, host, name: p.name, slot, car_model, stage: this.data.stage ?? 0 };
  }
  sync(body, now) {
    if (this.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
    const p = this.member(body.token);
    const s = body.state;
    if (!s || !vec(s.pos) || !vec(s.car) || !number(s.heading) || !number(s.yaw) || !number(s.pitch) || typeof s.in_car !== 'boolean') throw new RoomError(400, 'Некорректное состояние игрока.');
    const drive_inputs = (Array.isArray(s.drive_inputs) ? s.drive_inputs.slice(0, 96) : []).filter(c =>
      Number.isSafeInteger(c?.seq) && c.seq > 0 && Number.isSafeInteger(c.ticks) && c.ticks >= 1 && c.ticks <= 12
      && Number.isFinite(c.throttle) && Math.abs(c.throttle) <= 1 && Number.isFinite(c.steer) && Math.abs(c.steer) <= 1 && typeof c.brake === 'boolean')
      .map(({seq,ticks,throttle,steer,brake,recover}) => ({seq,ticks,throttle,steer,brake, ...(recover === true ? {recover: true} : {})}));
    p.state = { drive_enabled: s.drive_enabled === true, drive_inputs, pos: s.pos, car: s.car, heading: s.heading, tilt: vec(s.tilt) ? s.tilt : [0, s.heading, 0], yaw: s.yaw, pitch: s.pitch, in_car: s.in_car, tow: s.tow === true && !s.in_car, push: vec(s.push) ? s.push.map((n, i) => i === 1 ? 0 : Math.max(-1, Math.min(1, n))) : [0, 0, 0], speed: number(s.speed) ? Math.max(-50, Math.min(50, s.speed)) : 0, beers: Number.isSafeInteger(s.beers) ? Math.max(0, Math.min(100000, s.beers)) : 0, trees: Array.isArray(s.trees) ? s.trees.slice(0, 8).filter(t => Number.isSafeInteger(t?.id) && t.id >= 0 && t.id < 20000 && vec(t.dir)).map(t => ({ id: t.id, dir: t.dir })) : [], lamps: Array.isArray(s.lamps) ? s.lamps.slice(0, 8).filter(t => Number.isSafeInteger(t?.id) && t.id >= 0 && t.id < 512 && vec(t.dir)).map(t => ({ id: t.id, dir: t.dir })) : [], seated: s.seated === true && !s.in_car, running: s.running === true && !s.in_car && s.seated !== true, airborne: s.airborne === true && !s.in_car && s.seated !== true, food_kind: ['meat', 'mushroom', 'berries', 'plov'].includes(s.food_kind) ? s.food_kind : 'meat', eat: Number.isFinite(s.eat) ? Math.max(-1, Math.min(3.6, s.eat)) : -1, beer: Math.max(-1, Math.min(3.3, Number(s.beer) || 0)) };
    p.seen = now;
    p.state_time = now;
    if (p.id === this.data.host) {
      if (body.world && typeof body.world === 'object' && !Array.isArray(body.world)) { this.data.world = body.world; this.data.world_time = now; }
      const ack = new Set(Array.isArray(body.ack) ? body.ack.slice(0, 64) : []);
      this.data.commands = this.data.commands.filter(c => !ack.has(c.id));
    } else {
      for (const c of (Array.isArray(body.commands) ? body.commands.slice(0, 8) : [])) {
        if (!Number.isSafeInteger(c.seq) || c.seq <= p.seq || !COMMANDS.has(c.action)) continue;
        if (this.data.commands.length >= 64) throw new RoomError(429, 'Подожди выполнения предыдущих действий.');
        const placement = {};
        if (c.placement && vec(c.placement.pos) && number(c.placement.yaw) && Math.hypot(...c.placement.pos.map((v, i) => v - p.state.pos[i])) <= 5) {
          placement.pos = c.placement.pos;
          placement.yaw = c.placement.yaw;
        }
        if (Number.isSafeInteger(c.placement?.resource_id) && c.placement.resource_id >= 0 && c.placement.resource_id < 10000) placement.resource_id = c.placement.resource_id;
        if (Number.isSafeInteger(c.placement?.source) && c.placement.source >= -1 && c.placement.source < 100) placement.source = c.placement.source;
        this.data.commands.push({ id: `${p.id}:${c.seq}`, player: p.id, action: c.action, state: p.state, placement });
        p.seq = c.seq;
      }
    }
    return { server_time: now, world_time: this.data.world_time ?? 0, stage: this.data.stage ?? 0, host: this.data.host, world: this.data.world, accepted: p.seq,
      players: Object.values(this.data.players).map(({ id, name, slot, car_model, state_time, state }) => ({ id, name, slot, car_model: car_model ?? slot, state_time: state_time ?? 0, state })),
      commands: p.id === this.data.host ? this.data.commands : [] };
  }
  heartbeat(token, now) {
    if (this.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
    this.member(token).seen = now;
    return { alive: true };
  }
  leave(token) {
    const p = this.member(token);
    if (p.id === this.data.host) this.data.closed = true;
    delete this.data.players[p.id];
    this.data.commands = this.data.commands.filter(c => c.player !== p.id);
  }
}
