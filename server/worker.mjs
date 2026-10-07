import { AuthError, authenticateLaunch, authenticateSession } from './auth-vk.mjs';
import { RoomState, RoomError } from './room-core.mjs';
const json = (data, status = 200) => Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
export class RallyRoom {
  constructor(ctx) {
    this.ctx = ctx;
    this.savedAt = 0;
    ctx.blockConcurrencyWhile(async () => { this.room = new RoomState(await ctx.storage.get('room')); });
  }
  async fetch(request) {
    try {
      const raw = await request.text();
      if (raw.length > 65536) throw new RoomError(413, 'Слишком большое сообщение.');
      let body;
      try { body = JSON.parse(raw); } catch { throw new RoomError(400, 'Некорректное сообщение.'); }
      if (!body || typeof body !== 'object') throw new RoomError(400, 'Некорректное сообщение.');
      const now = Date.now();
      this.room.expire(now);
      const action = new URL(request.url).pathname.split('/').at(-1);
      let result;
      if (action === 'create' || action === 'join') result = this.room.add(body.name, now, action === 'create', body);
      else if (action === 'heartbeat') result = this.room.heartbeat(body.token, now);
      else if (action === 'sync') result = this.room.sync(body, now);
      else if (action === 'leave') { this.room.leave(body.token); result = { left: true }; }
      else return json({ error: 'Не найдено.' }, 404);
      if (!['sync', 'heartbeat'].includes(action) || now - this.savedAt > 5000) {
        await this.ctx.storage.put('room', this.room.data);
        await this.ctx.storage.setAlarm(now + 30000);
        this.savedAt = now;
      }
      return json(result);
    } catch (error) {
      if (error instanceof RoomError) return json({ error: error.message }, error.status);
      console.error(error);
      return json({ error: 'Сервер комнаты временно недоступен.' }, 500);
    }
  }
  async alarm() {
    this.room.expire(Date.now());
    if (this.room.data.closed || !this.room.data.host) await this.ctx.storage.deleteAll();
    else await this.ctx.storage.setAlarm(Date.now() + 30000);
  }
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    if (request.method !== 'POST') return json({ error: 'Нужен POST.' }, 405);
    const origin = request.headers.get('Origin');
    if (origin && origin !== url.origin) return json({ error: 'Недопустимый источник.' }, 403);
    if (Number(request.headers.get('Content-Length')) > 65536) return json({ error: 'Слишком большое сообщение.' }, 413);
    if (url.pathname.startsWith('/api/vk/') && env.PLATFORM !== 'vk') return json({ error: 'Не найдено.' }, 404);
    try {
      if (url.pathname === '/api/vk/session') {
        const raw = await request.text();
        if (raw.length > 16384) return json({ error: 'Слишком большое сообщение.' }, 413);
        let body;
        try { body = JSON.parse(raw); } catch { return json({ error: 'Некорректное сообщение.' }, 400); }
        return json(await authenticateLaunch(body?.launch_params, env));
      }
      if (env.PLATFORM === 'vk') {
        const session = await authenticateSession(request, env);
        if (url.pathname === '/api/rooms' || /^\/api\/rooms\/[A-F0-9]{6}\/join$/.test(url.pathname)) {
          const raw = await request.text();
          if (raw.length > 1024) return json({ error: 'Слишком большое сообщение.' }, 413);
          let body;
          try { body = JSON.parse(raw); } catch { return json({ error: 'Некорректное сообщение.' }, 400); }
          if (!body || typeof body !== 'object' || Array.isArray(body)) return json({ error: 'Некорректное сообщение.' }, 400);
          request = new Request(request, { body: JSON.stringify({ ...body, name: session.nickname }) });
        }
      }
    } catch (error) {
      if (error instanceof AuthError) return json({ error: error.message }, error.status);
      return json({ error: 'Авторизация временно недоступна.' }, 503);
    }
    if (url.pathname === '/api/rooms') {
      const raw = await request.text();
      if (raw.length > 1024) return json({ error: 'Слишком длинное имя.' }, 413);
      for (let attempt = 0; attempt < 4; attempt++) {
        const id = [...crypto.getRandomValues(new Uint8Array(3))].map(n => n.toString(16).padStart(2, '0')).join('').toUpperCase();
        const room = env.ROOMS.get(env.ROOMS.idFromName(id));
        const response = await room.fetch(new Request(`${url.origin}/create`, { method: 'POST', body: raw }));
        if (response.status === 409) continue;
        const data = await response.json();
        return json({ ...data, room: id }, response.status);
      }
      return json({ error: 'Не удалось создать комнату. Попробуй ещё раз.' }, 503);
    }
    const route = url.pathname.match(/^\/api\/rooms\/([A-F0-9]{6})\/(join|sync|leave|heartbeat)$/);
    if (!route) return json({ error: 'Неверный ID комнаты: нужны 6 символов.' }, 404);
    return env.ROOMS.get(env.ROOMS.idFromName(route[1])).fetch(request);
  },
};
