export const MAX_PLAYERS = 8;
const COMMANDS = new Set(['table', 'chairs', 'grill', 'eat', 'rally', 'random_spot']);
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
  add(name, now, host = false) {
    if (!host && (!this.data.host || this.data.closed)) throw new RoomError(404, 'Комната не найдена или закрыта.');
    if (host && this.data.host) throw new RoomError(409, 'Этот ID занят.');
    if (Object.keys(this.data.players).length >= MAX_PLAYERS) throw new RoomError(409, 'Комната заполнена: максимум 8 игроков.');
    const used = new Set(Object.values(this.data.players).map(p => p.slot));
    let slot = 0;
    while (used.has(slot)) slot++;
    const id = crypto.randomUUID();
    const p = { id, slot, token: crypto.randomUUID(), name: String(name || 'Овощ').replace(/[\u0000-\u001f]/g, '').trim().slice(0, 24) || 'Овощ', seen: now, state: null, seq: 0 };
    this.data.players[id] = p;
    if (host) this.data.host = id;
    return { player: id, token: p.token, host, name: p.name, slot };
  }
  sync(body, now) {
    if (this.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
    const p = this.member(body.token);
    const s = body.state;
    if (!s || !vec(s.pos) || !vec(s.car) || !number(s.heading) || !number(s.yaw) || !number(s.pitch) || typeof s.in_car !== 'boolean') throw new RoomError(400, 'Некорректное состояние игрока.');
    p.state = { pos: s.pos, car: s.car, heading: s.heading, tilt: vec(s.tilt) ? s.tilt : [0, s.heading, 0], yaw: s.yaw, pitch: s.pitch, in_car: s.in_car, tow: s.tow === true, beer: Math.max(-1, Math.min(3.3, Number(s.beer) || 0)) };
    p.seen = now;
    if (p.id === this.data.host) {
      if (body.world && typeof body.world === 'object' && !Array.isArray(body.world)) this.data.world = body.world;
      const ack = new Set(Array.isArray(body.ack) ? body.ack.slice(0, 64) : []);
      this.data.commands = this.data.commands.filter(c => !ack.has(c.id));
    } else {
      for (const c of (Array.isArray(body.commands) ? body.commands.slice(0, 8) : [])) {
        if (!Number.isSafeInteger(c.seq) || c.seq <= p.seq || !COMMANDS.has(c.action)) continue;
        if (this.data.commands.length >= 64) throw new RoomError(429, 'Подожди выполнения предыдущих действий.');
        this.data.commands.push({ id: `${p.id}:${c.seq}`, player: p.id, action: c.action, state: p.state });
        p.seq = c.seq;
      }
    }
    return { host: this.data.host, world: this.data.world, accepted: p.seq,
      players: Object.values(this.data.players).map(({ id, name, state }) => ({ id, name, state })),
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
