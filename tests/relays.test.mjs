import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {relayList, pickRelays, relayIce, turnPassword} from '../server/relays.mjs';
import {linkReport} from '../server/link-report.mjs';
import worker from '../server/worker.mjs';

const RELAYS = [
  {id: 'msk', urls: ['turn:msk.example.ru:3478?transport=udp', 'turns:msk.example.ru:443?transport=tcp'], countries: ['ru'], weight: 2},
  {id: 'spb', urls: ['turn:spb.example.ru:3478'], countries: ['RU'], secret: 'TURN_SECRET_SPB'},
  {id: 'fra', urls: ['turn:fra.example.org:3478']},
  {id: 'kz', urls: ['turn:kz.example.kz:3478'], countries: ['KZ']},
  {id: 'off', urls: ['turn:off.example.org:3478'], weight: 0},
  {id: 'bad', urls: ['http://example.org', 'turn:host with space']},
];

test('the relay list keeps valid relays only and survives a broken setting', () => {
  assert.deepEqual(relayList(JSON.stringify(RELAYS)).map(r => r.id), ['msk', 'spb', 'fra', 'kz']);
  assert.deepEqual(relayList(RELAYS)[0].urls, RELAYS[0].urls);
  assert.equal(relayList(RELAYS)[0].secret, 'TURN_SECRET');
  assert.equal(relayList(RELAYS)[1].secret, 'TURN_SECRET_SPB');
  for (const raw of ['', 'not json', '{}', '[1, null, "x"]', undefined]) assert.deepEqual(relayList(raw), []);
});

test('a player gets the relays of their country first, then the shared ones, never another country\'s', () => {
  const relays = relayList(RELAYS);
  assert.deepEqual(pickRelays(relays, 'RU', 3, () => 0).map(r => r.id), ['msk', 'spb', 'fra']);
  assert.deepEqual(pickRelays(relays, 'kz', 3).map(r => r.id), ['kz', 'fra']);
  assert.deepEqual(pickRelays(relays, 'DE', 3).map(r => r.id), ['fra']);
  assert.deepEqual(pickRelays(relays, '', 3).map(r => r.id), ['fra']);
  assert.deepEqual(pickRelays(relays, 'RU', 1).map(r => r.id), ['msk']);
  // Equal weights are spread between players.
  const two = relayList([{id: 'a', urls: ['turn:a.example:3478']}, {id: 'b', urls: ['turn:b.example:3478']}]);
  assert.equal(pickRelays(two, 'RU', 1, () => 0)[0].id, 'a');
  let n = 0;
  assert.equal(pickRelays(two, 'RU', 1, () => n++ === 0 ? 0.9 : 0.1)[0].id, 'b');
});

test('passwords follow coturn use-auth-secret: base64 HMAC-SHA1 of "<expiry>:<player>"', async () => {
  const expected = createHmac('sha1', 'top secret').update('1700000000:ab12').digest('base64');
  assert.equal(await turnPassword('top secret', '1700000000:ab12'), expected);
  const env = {TURN_SERVERS: JSON.stringify(RELAYS), TURN_SECRET: 's1', TURN_SECRET_SPB: 's2', TURN_TTL: '3600'};
  const ice = await relayIce(env, 'p-1"<x>', 'RU', 1_700_000_000_000, () => 0);
  assert.equal(ice.length, 3);
  for (const server of ice) assert.equal(server.username, '1700003600:p-1x');
  assert.deepEqual(ice[0].urls, RELAYS[0].urls);
  assert.equal(ice[0].credential, createHmac('sha1', 's1').update('1700003600:p-1x').digest('base64'));
  assert.equal(ice[1].credential, createHmac('sha1', 's2').update('1700003600:p-1x').digest('base64'));
  // A relay whose secret is missing is left out; nothing configured, nothing given.
  assert.deepEqual((await relayIce({...env, TURN_SECRET_SPB: undefined}, 'p', 'RU', 0, () => 0)).map(s => s.urls[0]), [RELAYS[0].urls[0], RELAYS[2].urls[0]]);
  assert.deepEqual(await relayIce({}, 'p', 'RU'), []);
  assert.equal((await relayIce({...env, TURN_PICK: '1'}, 'p', 'RU')).length, 1);
});

const rooms = reply => ({idFromName: name => name, get: () => ({fetch: async () => Response.json(reply)})});

test('create and join replies carry the relays with passwords for that player', async () => {
  const env = {TURN_SERVERS: JSON.stringify(RELAYS), TURN_SECRET: 's1', ROOMS: rooms({player: 'ab12', token: 't', host: false})};
  const request = path => Object.assign(new Request('https://game.test' + path, {method: 'POST', body: '{"name":"x"}'}), {cf: {country: 'KZ'}});
  for (const path of ['/api/rooms', '/api/rooms/ABC123/join']) {
    const reply = await (await worker.fetch(request(path), env)).json();
    assert.deepEqual(reply.ice.map(s => s.urls[0]), ['turn:kz.example.kz:3478', 'turn:fra.example.org:3478'], path);
    assert.match(reply.ice[0].username, /^\d+:ab12$/);
  }
  const plain = await (await worker.fetch(request('/api/rooms/ABC123/join'), {ROOMS: env.ROOMS})).json();
  assert.deepEqual(plain.ice, []);
});

test('link reports are sanitized and logged with the network they came from', async () => {
  const report = linkReport(JSON.stringify({result: 'failed', reason: 'blocked', room: 'ABC123', role: 'guest', platform: 'android', waited: 20.04, attempts: 3, relays: 2,
    local: ['host', 'srflx', 'srflx', 'evil'], remote: ['relay'], pair: 'relay/host', extra: 'dropped'}), {country: 'RU', asn: 8359, asOrganization: 'MTS PJSC', colo: 'ARN'});
  assert.deepEqual(report, {result: 'failed', reason: 'blocked', room: 'ABC123', role: 'guest', platform: 'android', waited: 20, attempts: 3, relays: 2,
    local: ['host', 'srflx'], remote: ['relay'], pair: 'relay/host', country: 'RU', asn: 8359, network: 'MTS PJSC', colo: 'ARN'});
  assert.equal(linkReport('{"result":"weird"}'), null);
  assert.equal(linkReport('nope'), null);
  const odd = linkReport(JSON.stringify({result: 'lost', reason: 'Drop Table', room: 'zz', pair: 'a/b', platform: 'amiga', waited: 1e9}));
  assert.deepEqual([odd.reason, odd.room, odd.pair, odd.platform, odd.waited], ['', '', '', 'other', 600]);

  const logged = [];
  const log = console.log;
  console.log = (...args) => logged.push(args.join(' '));
  try {
    const ok = await worker.fetch(Object.assign(new Request('https://game.test/api/telemetry/link', {method: 'POST', body: JSON.stringify({result: 'linked', room: 'ABC123'})}), {cf: {country: 'RU'}}), {});
    assert.equal(ok.status, 200);
    const bad = await worker.fetch(new Request('https://game.test/api/telemetry/link', {method: 'POST', body: 'x'}), {});
    assert.equal(bad.status, 400);
    const big = await worker.fetch(new Request('https://game.test/api/telemetry/link', {method: 'POST', body: 'x'.repeat(5000)}), {});
    assert.equal(big.status, 413);
  } finally { console.log = log; }
  assert.equal(logged.length, 1);
  assert.match(logged[0], /^\[RFM link\] \{"result":"linked".*"country":"RU"/);
});
