const encoder = new TextEncoder();
export class AuthError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const encode = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const key = secret => crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
async function sign(value, secret) {
  return encode(await crypto.subtle.sign('HMAC', await key(secret), encoder.encode(value)));
}
async function verify(value, signature, secret) {
  if (!/^[A-Za-z0-9_-]{43}$/.test(signature || '')) return false;
  const bytes = Uint8Array.from(atob(signature.replace(/-/g, '+').replace(/_/g, '/') + '='), c => c.charCodeAt(0));
  return crypto.subtle.verify('HMAC', await key(secret), bytes, encoder.encode(value));
}
function configured(env) {
  if (!/^[1-9]\d*$/.test(env.VK_APP_ID || '') || !env.VK_APP_SECRET || !env.VK_SERVICE_TOKEN || !env.VK_SESSION_SECRET) {
    throw new AuthError(503, 'Авторизация VK не настроена.');
  }
}
export async function authenticateLaunch(raw, env, now = Date.now(), network = fetch) {
  configured(env);
  if (typeof raw !== 'string' || raw.length > 8192) throw new AuthError(400, 'Некорректные параметры запуска.');
  const params = new URLSearchParams(raw);
  for (const name of params.keys()) {
    if ((name.startsWith('vk_') || name === 'sign') && params.getAll(name).length !== 1) throw new AuthError(401, 'Повторяющиеся параметры запуска.');
  }
  const canonical = [...params].filter(([name]) => name.startsWith('vk_')).sort(([a], [b]) => a.localeCompare(b))
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`).join('&');
  if (!await verify(canonical, params.get('sign'), env.VK_APP_SECRET)) throw new AuthError(401, 'Неверная подпись запуска VK.');
  const user = params.get('vk_user_id');
  const timestamp = Number(params.get('vk_ts'));
  const seconds = Math.floor(now / 1000);
  if (params.get('vk_app_id') !== env.VK_APP_ID || !/^[1-9]\d*$/.test(user || '') || !Number.isSafeInteger(timestamp) || timestamp < seconds - 3600 || timestamp > seconds + 60) {
    throw new AuthError(401, 'Запуск VK устарел или принадлежит другому приложению.');
  }
  let data;
  try {
    const response = await network('https://api.vk.ru/method/users.get', {
      method: 'POST', body: new URLSearchParams({ user_ids: user, fields: 'screen_name', access_token: env.VK_SERVICE_TOKEN, v: '5.199' }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('VK unavailable');
    data = await response.json();
  } catch { throw new AuthError(502, 'Не удалось получить профиль VK. Попробуйте ещё раз.'); }
  const profile = data?.response?.[0];
  if (data?.error || String(profile?.id) !== user) throw new AuthError(502, 'VK не вернул профиль пользователя.');
  const nickname = /^[A-Za-z0-9_.]{1,64}$/.test(profile.screen_name || '') ? profile.screen_name : `vk${user}`;
  const expires = seconds + 3600;
  const payload = encode(encoder.encode(JSON.stringify({ app: env.VK_APP_ID, user, nickname, expires })));
  const token = `${payload}.${await sign(payload, env.VK_SESSION_SECRET)}`;
  return { profile: { platform: 'vk', platform_user_id: user, nickname, verified: true }, session: { token, expires_at: expires }, entitlements: { mode: 'unrestricted', skus: [] } };
}
export async function authenticateSession(request, env, now = Date.now()) {
  configured(env);
  const token = request.headers.get('Authorization')?.match(/^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/)?.[1];
  if (!token || token.length > 2048) throw new AuthError(401, 'Откройте игру заново через VK.');
  const [payload, signature] = token.split('.');
  if (!await verify(payload, signature, env.VK_SESSION_SECRET)) throw new AuthError(401, 'Неверная сессия VK.');
  let session;
  try { session = JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/'))); } catch { throw new AuthError(401, 'Неверная сессия VK.'); }
  if (session.app !== env.VK_APP_ID || !Number.isSafeInteger(session.expires) || session.expires <= Math.floor(now / 1000) || !/^[1-9]\d*$/.test(session.user || '') || typeof session.nickname !== 'string') throw new AuthError(401, 'Сессия VK истекла. Откройте игру заново.');
  return session;
}
