// How a guest's direct link to the host ended (game/scripts/net/link_report.gd).
// The Worker writes each report to its log as one "[RFM link]" line, with the
// country and the network (ASN) Cloudflare saw the request from. Workers Logs
// keep them, so "how often does a link fail, where, and does a relay help"
// is a log query. Nothing identifies the player beyond the room code.
const RESULTS = new Set(['linked', 'failed', 'lost']);
const TYPES = new Set(['host', 'srflx', 'prflx', 'relay']);
const PLATFORMS = new Set(['web', 'macos', 'windows', 'linux', 'android', 'ios', 'other']);
const ROOM = /^[A-F0-9]{6}$/;
const WORD = /^[a-z_]{1,24}$/;

const types = list => Array.isArray(list) ? [...new Set(list.filter(t => TYPES.has(t)))].sort() : [];
const number = (value, max) => Number.isFinite(Number(value)) ? Math.min(max, Math.max(0, Math.round(Number(value) * 10) / 10)) : 0;

// The sanitized report, or null when it is not one.
export function linkReport(raw, cf = {}) {
  let body;
  try { body = JSON.parse(raw); } catch { return null; }
  if (!body || typeof body !== 'object' || Array.isArray(body) || !RESULTS.has(body.result)) return null;
  const pair = typeof body.pair === 'string' ? body.pair.split('/') : [];
  return {
    result: body.result,
    reason: WORD.test(body.reason ?? '') ? body.reason : '',
    room: ROOM.test(body.room ?? '') ? body.room : '',
    role: body.role === 'host' ? 'host' : 'guest',
    platform: PLATFORMS.has(body.platform) ? body.platform : 'other',
    waited: number(body.waited, 600),
    attempts: number(body.attempts, 20),
    relays: number(body.relays, 32),
    local: types(body.local),
    remote: types(body.remote),
    pair: pair.length === 2 && TYPES.has(pair[0]) && TYPES.has(pair[1]) ? pair.join('/') : '',
    country: String(cf?.country ?? ''),
    asn: Number(cf?.asn ?? 0),
    network: String(cf?.asOrganization ?? '').slice(0, 64),
    colo: String(cf?.colo ?? ''),
  };
}
