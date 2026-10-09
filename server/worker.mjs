import { enforceLimit, LimitError, limitResponse } from './rate-limits.mjs';
import { accountStore, preparePurchase, paymentCallback, PaymentError, PAYMENT_HANDLER_VERSION } from './payments-vk.mjs';
export { VkPayments } from './payments-vk.mjs';
import { AuthError, authenticateLaunch, authenticateSession } from './auth-vk.mjs';
import { validateRoomSelection } from './store.mjs';
import { RoomState, RoomError } from './room-core.mjs';
const json = (data, status = 200) => Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
const PUSH_INTERVAL = 40;
const socketUrl = (url, room) => `${url.protocol === 'https:' ? 'wss:' : 'ws:'}//${url.host}/api/rooms/${room}/socket`;
export class RallyRoom {
  constructor(ctx) {
    this.ctx = ctx;
    this.savedAt = 0;
    this.pushes = new Map();
    ctx.blockConcurrencyWhile(async () => { this.room = new RoomState(await ctx.storage.get('room')); });
  }
  async persist(now, force) {
    if (!force && now - this.savedAt <= 5000) return;
    await this.ctx.storage.put('room', this.room.data);
    await this.ctx.storage.setAlarm(now + 30000);
    this.savedAt = now;
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.endsWith('/socket')) {
      if (request.headers.get('Upgrade') !== 'websocket') return json({ error: 'Нужен WebSocket.' }, 426);
      const pair = new WebSocketPair();
      // Hibernation keeps idle rooms cheap; membership is proven by the first message.
      this.ctx.acceptWebSocket(pair[1]);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    try {
      const raw = await request.text();
      if (raw.length > 65536) throw new RoomError(413, 'Слишком большое сообщение.');
      let body;
      try { body = JSON.parse(raw); } catch { throw new RoomError(400, 'Некорректное сообщение.'); }
      if (!body || typeof body !== 'object') throw new RoomError(400, 'Некорректное сообщение.');
      const now = Date.now();
      this.room.expire(now);
      const action = url.pathname.split('/').at(-1);
      let result;
      if (action === 'create' || action === 'join') result = this.room.add(body.name, now, action === 'create', body);
      else if (action === 'heartbeat') result = this.room.heartbeat(body.token, now, body.background === true);
      else if (action === 'sync') { result = this.room.sync(body, now); this.fanOut(this.room.member(body.token).id); }
      else if (action === 'leave') { this.room.leave(body.token); result = { left: true }; }
      else return json({ error: 'Не найдено.' }, 404);
      await this.persist(now, !['sync', 'heartbeat'].includes(action));
      return json(result);
    } catch (error) {
      if (error instanceof RoomError) {
        const response = json({ error: error.message, ...(error.status === 429 ? {retry_after:error.retryAfter ?? 10} : {}) }, error.status);
        if (error.status === 429) response.headers.set("Retry-After", String(error.retryAfter ?? 10));
        return response;
      }
      console.error(error);
      return json({ error: 'Сервер комнаты временно недоступен.' }, 500);
    }
  }
  sockets(player) {
    return this.ctx.getWebSockets().filter(ws => ws.deserializeAttachment()?.player === player);
  }
  send(ws, message) {
    try { ws.send(JSON.stringify(message)); } catch {}
  }
  // Deliver a fresh view to a socket-connected participant without waiting
  // for its next request. Bursts of guest inputs are merged for the host.
  push(player, delay = 0) {
    if (this.pushes.has(player)) return;
    const deliver = () => {
      this.pushes.delete(player);
      const p = this.room.data.players[player];
      if (!p || this.room.data.closed) return;
      const now = Date.now();
      p.pushed_at = now;
      for (const ws of this.sockets(player)) this.send(ws, { type: 'push', ...this.room.view(p, now) });
    };
    if (delay <= 0) { deliver(); return; }
    this.pushes.set(player, setTimeout(deliver, delay));
  }
  fanOut(sender) {
    const host = this.room.data.host;
    if (sender === host) {
      for (const ws of this.ctx.getWebSockets()) {
        const player = ws.deserializeAttachment()?.player;
        if (player && player !== host) this.push(player);
      }
    } else if (this.sockets(host).length) {
      const since = Date.now() - (this.room.data.players[host]?.pushed_at ?? 0);
      this.push(host, Math.max(0, PUSH_INTERVAL - since));
    }
  }
  async webSocketMessage(ws, message) {
    let body;
    try {
      if (typeof message !== 'string' || message.length > 65536) throw new RoomError(413, 'Слишком большое сообщение.');
      try { body = JSON.parse(message); } catch { throw new RoomError(400, 'Некорректное сообщение.'); }
      if (!body || typeof body !== 'object') throw new RoomError(400, 'Некорректное сообщение.');
      const now = Date.now();
      this.room.expire(now);
      if (this.room.data.closed) throw new RoomError(410, 'Создатель вышел. Комната закрыта.');
      if (body.type === 'hello') {
        const p = this.room.member(body.token);
        this.room.trackColdRevisions(p, body);
        ws.serializeAttachment({ player: p.id, token: p.token });
        this.send(ws, { type: 'hello', id: body.id, player: p.id });
        return;
      }
      if (body.type !== 'sync') throw new RoomError(400, 'Некорректное сообщение.');
      const session = ws.deserializeAttachment();
      if (!session?.token) throw new RoomError(401, 'Участник не найден. Войди в комнату заново.');
      const result = this.room.sync({ ...body, token: session.token }, now);
      this.send(ws, { type: 'reply', id: body.id, ...result });
      this.fanOut(session.player);
      await this.persist(now, false);
    } catch (error) {
      const known = error instanceof RoomError;
      if (!known) console.error(error);
      const status = known ? error.status : 500;
      this.send(ws, { type: 'error', id: body?.id, status, error: known ? error.message : 'Сервер комнаты временно недоступен.', ...(status === 429 ? { retry_after: error.retryAfter ?? 10 } : {}) });
      if ([401, 404, 410].includes(status)) { try { ws.close(4000 + status, 'room'); } catch {} }
    }
  }
  async webSocketClose(ws, code) {
    try { ws.close(code === 1005 || code === 1006 ? 1000 : code, 'closed'); } catch {}
  }
  async webSocketError(ws) {
    try { ws.close(1011, 'error'); } catch {}
  }
  async alarm() {
    this.room.expire(Date.now());
    if (this.room.data.closed || !this.room.data.host) {
      for (const ws of this.ctx.getWebSockets()) { try { ws.close(4410, 'closed'); } catch {} }
      await this.ctx.storage.deleteAll();
    }
    else await this.ctx.storage.setAlarm(Date.now() + 30000);
  }
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/vk') {
      url.pathname = '/vk/';
      return Response.redirect(url.toString(), 308);
    }
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    const socket = url.pathname.match(/^\/api\/rooms\/([A-F0-9]{6})\/socket$/);
    if (socket && request.method === 'GET') {
      if (request.headers.get('Upgrade') !== 'websocket') return json({ error: 'Нужен WebSocket.' }, 426);
      const origin = request.headers.get('Origin');
      if (origin && origin !== url.origin) return json({ error: 'Недопустимый источник.' }, 403);
      try { await enforceLimit(env, 'API_RATE_LIMIT', 'ip:' + (request.headers.get('CF-Connecting-IP') || 'local')); }
      catch (error) { return limitResponse(error); }
      return env.ROOMS.get(env.ROOMS.idFromName(socket[1])).fetch(request);
    }
    if (request.method !== 'POST') return json({ error: 'Нужен POST.' }, 405);
    if (url.pathname === '/api/vk/payments/callback') {
      const reply = data => {
        const response = json(data);
        response.headers.set('X-Rally-Payments-Handler', PAYMENT_HANDLER_VERSION);
        return response;
      };
      try { return reply(await paymentCallback(await request.text(), env)); }
      catch (error) {
        const known = error instanceof PaymentError;
        console.warn('[RFM VK payments]', JSON.stringify({handler:PAYMENT_HANDLER_VERSION,error_code:known ? error.code : 1,message:known ? error.message : 'Платежи временно недоступны.'}));
        return reply({error:{error_code:known ? error.code : 1,error_msg:known ? error.message : 'Платежи временно недоступны.',critical:known ? error.critical : false}});
      }
    }
    try {
      const ip = request.headers.get('CF-Connecting-IP') || 'local';
      await enforceLimit(env, 'API_RATE_LIMIT', 'ip:' + ip);
      if (url.pathname === '/api/vk/session') await enforceLimit(env, 'AUTH_RATE_LIMIT', 'ip:' + ip);
      if (url.pathname === '/api/rooms' || /^\/api\/rooms\/[A-F0-9]{6}\/join$/.test(url.pathname)) {
        await enforceLimit(env, 'ROOM_ENTRY_RATE_LIMIT', 'ip:' + ip);
      }
    } catch (error) { return limitResponse(error); }
    const origin = request.headers.get('Origin');
    if (origin && origin !== url.origin) return json({ error: 'Недопустимый источник.' }, 403);
    if (Number(request.headers.get('Content-Length')) > 65536) return json({ error: 'Слишком большое сообщение.' }, 413);
    try {
      if (url.pathname === '/api/vk/session') {
        const raw = await request.text();
        if (raw.length > 16384) return json({ error: 'Слишком большое сообщение.' }, 413);
        let body;
        try { body = JSON.parse(raw); } catch { return json({ error: 'Некорректное сообщение.' }, 400); }
        const bootstrap = await authenticateLaunch(body?.launch_params, env);
        return json({...bootstrap,...await accountStore(env,bootstrap.profile.platform_user_id)});
      }
      if (url.pathname === '/api/vk/store' || url.pathname === '/api/vk/payments/prepare') {
        const session = await authenticateSession(request, env);
        await enforceLimit(env, url.pathname === '/api/vk/store' ? 'STORE_RATE_LIMIT' : 'PURCHASE_RATE_LIMIT', 'user:' + session.user);
        if (url.pathname === '/api/vk/store') return json(await accountStore(env,session.user));
        const raw = await request.text();
        if (raw.length > 1024) return json({error:'Слишком большое сообщение.'},413);
        let body;
        try { body = JSON.parse(raw); } catch { return json({error:'Некорректное сообщение.'},400); }
        return json(await preparePurchase(env,session.user,body?.sku));
      }
      // Anonymous and authenticated players share the same room namespace.
      // An explicitly supplied session must never silently downgrade to anonymous.
      if (request.headers.has('Authorization') || request.headers.get('X-Rally-Platform') === 'vk') {
        const session = await authenticateSession(request, env);
        if (url.pathname === '/api/rooms' || /^\/api\/rooms\/[A-F0-9]{6}\/join$/.test(url.pathname)) {
          await enforceLimit(env, 'ROOM_ENTRY_RATE_LIMIT', 'user:' + session.user);
          const raw = await request.text();
          if (raw.length > 1024) return json({ error: 'Слишком большое сообщение.' }, 413);
          let body;
          try { body = JSON.parse(raw); } catch { return json({ error: 'Некорректное сообщение.' }, 400); }
          if (!body || typeof body !== 'object' || Array.isArray(body)) return json({ error: 'Некорректное сообщение.' }, 400);
          const denied = validateRoomSelection(body, url.pathname === '/api/rooms', (await accountStore(env,session.user)).entitlements);
          if (denied) return json({error:denied}, 403);
          request = new Request(request, { body: JSON.stringify({ ...body, car_model: body.car_model ?? 0, name: session.nickname }) });
        }
      }
    } catch (error) {
      if (error instanceof LimitError) return limitResponse(error);
      if (error instanceof PaymentError) return json({error:error.message},error.critical ? 403 : 503);
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
        return json(response.ok ? { ...data, room: id, socket: socketUrl(url, id) } : { ...data, room: id }, response.status);
      }
      return json({ error: 'Не удалось создать комнату. Попробуй ещё раз.' }, 503);
    }
    const route = url.pathname.match(/^\/api\/rooms\/([A-F0-9]{6})\/(join|sync|leave|heartbeat)$/);
    if (!route) return json({ error: 'Неверный ID комнаты: нужны 6 символов.' }, 404);
    const response = await env.ROOMS.get(env.ROOMS.idFromName(route[1])).fetch(request);
    if (route[2] !== 'join' || !response.ok) return response;
    return json({ ...await response.json(), socket: socketUrl(url, route[1]) });
  },
};
