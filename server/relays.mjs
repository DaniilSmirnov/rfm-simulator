// TURN relays for direct links (game/scripts/net/direct_link.gd, the radio).
// The relays are our own coturn servers (server/turn/), not Cloudflare: a
// player whose network blocks a direct link still reaches the host through
// one. There may be several, anywhere; the room server only hands out
// short-lived passwords for them and knows nothing else about them.
//
// Configuration (Worker vars/secrets, or the same names in any other host):
//   TURN_SERVERS  JSON array, one entry per relay:
//                 {"id": "msk-1", "urls": ["stun:msk1.example.ru:3478",
//                  "turn:msk1.example.ru:3478?transport=udp",
//                  "turns:msk1.example.ru:443?transport=tcp"],
//                  "countries": ["RU", "BY"], "weight": 2, "secret": "TURN_SECRET_MSK"}
//                 countries: players from these countries get it first
//                 (none: a relay for everyone); weight: order among equals
//                 (default 1, 0 switches the relay off); secret: the name of
//                 the variable with this relay's shared secret
//                 (default TURN_SECRET).
//   TURN_SECRET   the shared secret of coturn's static-auth-secret.
//   TURN_PICK     how many relays one player gets (default 3).
//   TURN_TTL      password lifetime in seconds (default 12 h).
//
// Passwords follow coturn's "TURN REST API" (use-auth-secret): the username is
// "<expiry unix time>:<player>", the password is base64(HMAC-SHA1(secret,
// username)). coturn checks them itself, so the relays need no database and
// no connection to the room server.
const DEFAULT_PICK = 3;
const DEFAULT_TTL = 12 * 3600;
const MAX_RELAYS = 32;
const URL_PATTERN = /^(stun|turns?):[A-Za-z0-9.\-[\]:]+(\?transport=(udp|tcp))?$/;

// The valid relays of TURN_SERVERS; a broken entry is skipped, a broken list
// gives none (the game still links over STUN).
export function relayList(raw) {
  let list;
  try { list = typeof raw === 'string' ? JSON.parse(raw) : raw; } catch { return []; }
  if (!Array.isArray(list)) return [];
  const relays = [];
  for (const entry of list.slice(0, MAX_RELAYS)) {
    if (!entry || typeof entry !== 'object' || !Array.isArray(entry.urls)) continue;
    const urls = entry.urls.filter(url => typeof url === 'string' && URL_PATTERN.test(url));
    const weight = entry.weight === undefined ? 1 : Number(entry.weight);
    if (!urls.length || !(weight > 0)) continue;
    relays.push({
      id: String(entry.id ?? urls[0]),
      urls,
      countries: Array.isArray(entry.countries) ? entry.countries.map(c => String(c).toUpperCase()) : [],
      weight,
      secret: typeof entry.secret === 'string' && /^[A-Z0-9_]+$/.test(entry.secret) ? entry.secret : 'TURN_SECRET',
    });
  }
  return relays;
}

// Which relays a player from `country` gets: the ones for that country first,
// then the ones for everyone, heavier first; never relays meant only for other
// countries. Equal weights are shuffled by `random` so players spread out.
export function pickRelays(relays, country, count = DEFAULT_PICK, random = Math.random) {
  const code = String(country || '').toUpperCase();
  const rank = relay => relay.countries.includes(code) ? 0 : relay.countries.length === 0 ? 1 : 2;
  return relays
    .filter(relay => rank(relay) < 2)
    .map(relay => ({ relay, key: [rank(relay), -relay.weight, random()] }))
    .sort((a, b) => a.key[0] - b.key[0] || a.key[1] - b.key[1] || a.key[2] - b.key[2])
    .slice(0, Math.max(0, count))
    .map(item => item.relay);
}

export async function turnPassword(secret, username) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(username)));
  return btoa(String.fromCharCode(...mac));
}

// ICE servers for one player, in the RTCPeerConnection format:
// [{urls: [...], username, credential}]. Empty when no relay is configured,
// or when a relay's secret is missing (that relay is left out).
export async function relayIce(env, player, country, now = Date.now(), random = Math.random) {
  if (!env?.TURN_SERVERS) return [];
  const count = Number(env.TURN_PICK ?? DEFAULT_PICK);
  const ttl = Number(env.TURN_TTL ?? DEFAULT_TTL);
  const id = String(player || 'guest').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 32) || 'guest';
  const username = `${Math.floor(now / 1000) + (ttl > 0 ? ttl : DEFAULT_TTL)}:${id}`;
  const ice = [];
  for (const relay of pickRelays(relayList(env.TURN_SERVERS), country, Number.isFinite(count) ? count : DEFAULT_PICK, random)) {
    const secret = env[relay.secret];
    if (typeof secret !== 'string' || secret === '') continue;
    ice.push({ urls: relay.urls, username, credential: await turnPassword(secret, username) });
  }
  return ice;
}
