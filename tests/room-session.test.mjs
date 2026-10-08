import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
const source = readFileSync(new URL('../web/room-session.js', import.meta.url), 'utf8');
function setup() {
  const requests = [], events = {};
  let tick;
  const window = { fetch: async (input, init) => {
    requests.push({ input, init });
    return Response.json({ token: 'private', player: 'player', room: 'ABC123', host: true });
  }, addEventListener: (name, fn) => { events[name] = fn; } };
  const beacons = [];
  const document = { hidden: false, addEventListener: (name, fn) => { events[name] = fn; } };
  runInNewContext(source, { window, document, location: { href: 'https://game.test/', origin: 'https://game.test' }, URL, Blob,
    navigator: { sendBeacon: (url, body) => beacons.push({ url, body }) }, setInterval: fn => { tick = fn; } });
  return { window, document, requests, events, beacons, tick: () => tick() };
}
const settle = () => new Promise(resolve => setTimeout(resolve, 20));
test('room handshake enables background heartbeat and navigation leave', async () => {
  const s = setup();
  await s.tick(); assert.equal(s.requests.length, 0);
  await s.window.fetch('https://game.test/api/rooms', { method: 'POST' });
  await settle(); await s.tick();
  assert.equal(s.requests[1].input, '/api/rooms/ABC123/heartbeat');
  assert.equal(JSON.parse(s.requests[1].init.body).token, 'private');
  s.events.pagehide({ persisted: true }); assert.equal(s.beacons.length, 0);
  s.events.pagehide({ persisted: false }); assert.equal(s.beacons[0].url, '/api/rooms/ABC123/leave');
  await s.window.fetch('https://game.test/api/rooms/ABC123/leave', { method: 'POST' });
  const count = s.requests.length; await s.tick(); assert.equal(s.requests.length, count);
});
test('foreign origin responses cannot establish membership', async () => {
  const s = setup();
  await s.window.fetch('https://other.test/api/rooms');
  await settle(); await s.tick(); assert.equal(s.requests.length, 1);
});

test('VK heartbeat and leave use the current authorized transport', async () => {
  const s=setup();
  await s.window.fetch('https://game.test/api/rooms',{method:'POST'});
  await settle();
  const calls=[];
  s.window.RallyPlatform={target:'vk'};
  const previous=s.window.fetch;
  s.window.fetch=(input,init)=>{calls.push({input,init});return previous(input,init);};
  await s.tick();
  assert.equal(calls[0].input,'/api/rooms/ABC123/heartbeat');
  s.events.pagehide({persisted:false});
  assert.equal(calls[1].input,'/api/rooms/ABC123/leave');
  assert.equal(calls[1].init.keepalive,true);
  assert.equal(s.beacons.length,0);
});

test('visibility heartbeat marks host background and foreground without leaving the room', async () => {
  const s = setup();
  await s.window.fetch('https://game.test/api/rooms', { method: 'POST' });
  await settle();
  s.document.hidden = true;
  s.events.visibilitychange();
  assert.equal(JSON.parse(s.requests.at(-1).init.body).background, true);
  s.document.hidden = false;
  s.events.visibilitychange();
  assert.equal(JSON.parse(s.requests.at(-1).init.body).background, false);
  await s.tick();
  assert.equal(JSON.parse(s.requests.at(-1).init.body).background, false);
  assert.equal(s.beacons.length, 0);
});
