// Real WebRTC check of web/voice-chat.js: three Chromium pages with a fake
// microphone form a room, the test relays signaling like the room server does,
// and the receivers' inbound audio energy shows push-to-talk gating.
import playwright from 'playwright';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import assert from 'node:assert/strict';
import {setTimeout as wait} from 'node:timers/promises';

const {chromium} = playwright;
const source = await readFile(new URL('../web/voice-chat.js', import.meta.url), 'utf8');
// getUserMedia needs a secure context: serve the page from 127.0.0.1.
const server = createServer((_request, response) => {
 response.writeHead(200, {'content-type': 'text/html'});
 response.end('<!doctype html><title>voice</title><body></body>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE, args: [
 '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required',
 '--disable-features=WebRtcHideLocalIpsWithMdns', '--allow-loopback-in-peer-connection',
]});
const ids = ['a', 'b', 'c'];
const pages = {};

async function relay(rounds = 1) {
 for (let i = 0; i < rounds; i++) {
  for (const id of ids) {
   const out = JSON.parse(await pages[id].evaluate(() => RallyVoice.tick('[]')));
   for (const envelope of out.signals) await pages[envelope.to].evaluate(([from, data]) => RallyVoice.onSignal(from, data), [id, envelope.data]);
  }
  await wait(50);
 }
}

// What a member's radio actually plays here: RMS after the radio filters and
// volume, read from an analyser tapped onto that peer's output gain.
async function heard(page, from, ms = 1500) {
 await page.evaluate(from => {
  const audio = RallyVoice.state.peers.get(from).audio;
  if (!audio.probe) {
   audio.probe = audio.gain.context.createAnalyser();
   audio.probe.fftSize = 2048;
   audio.gain.connect(audio.probe);
   audio.peak = 0;
   const samples = new Float32Array(audio.probe.fftSize);
   audio.timer = setInterval(() => {
    audio.probe.getFloatTimeDomainData(samples);
    let sum = 0;
    for (const v of samples) sum += v * v;
    audio.peak = Math.max(audio.peak, Math.sqrt(sum / samples.length));
   }, 20);
  }
  audio.peak = 0;
 }, from);
 await relay(Math.ceil(ms / 100));
 return page.evaluate(from => RallyVoice.state.peers.get(from).audio.peak, from);
}

try {
 for (const id of ids) {
  const context = await browser.newContext({permissions: ['microphone']});
  pages[id] = await context.newPage();
  await pages[id].goto(origin);
  await pages[id].addScriptTag({content: source});
  await pages[id].evaluate(([id, ids]) => { RallyVoice.syncMembers(ids); return RallyVoice.join({localId: id, session: `voice-test-${id}`, iceServers: []}); }, [id, ids]);
 }
 const deadline = Date.now() + 20000;
 while (Date.now() < deadline) {
  await relay();
  const counts = await Promise.all(ids.map(id => pages[id].evaluate(() => JSON.parse(RallyVoice.tick('[]')).connected)));
  if (counts.every(n => n === ids.length - 1)) break;
 }
 for (const id of ids) assert.equal(await pages[id].evaluate(() => [...RallyVoice.state.peers.values()].filter(p => p.connected && p.audio).length), 2, `${id} connects and plays both others`);
 assert.ok(await heard(pages.b, 'a') < 1e-3, 'nothing is heard before anyone presses the key');
 await pages.a.evaluate(() => RallyVoice.setPtt(true));
 const ready = Date.now() + 5000;
 while (await pages.a.evaluate(() => RallyVoice.state.mic) !== 'ready' && Date.now() < ready) await wait(50);
 assert.equal(await pages.a.evaluate(() => RallyVoice.state.mic), 'ready', 'the first press opens the microphone');
 await relay(5);
 const loud = await heard(pages.b, 'a');
 assert.ok(loud > 0.01, `b hears a while the key is held (${loud})`);
 assert.ok(await heard(pages.c, 'a') > 0.01, 'c hears a too');
 assert.ok(await heard(pages.a, 'b') < 1e-3, 'a does not hear b, who is silent');
 await pages.a.evaluate(() => RallyVoice.setPtt(false));
 await relay(5);
 assert.ok(await heard(pages.b, 'a') < 1e-3, 'releasing the key silences a');
 const gain = distance => pages.b.evaluate(async distance => {
  RallyVoice.update([{id: 'a', distance, talking: true}]);
  await new Promise(resolve => setTimeout(resolve, 400));
  return RallyVoice.state.peers.get('a').audio.gain.gain.value;
 }, distance);
 const near = await gain(5), far = await gain(600);
 assert.ok(near > 0.9 && far < 0.2, `distance lowers the volume (${near} -> ${far})`);
 // Leaving: c says bye, and the server's next roster no longer lists c.
 await pages.c.evaluate(() => RallyVoice.leave());
 for (const id of ['a', 'b']) await pages[id].evaluate(() => RallyVoice.syncMembers(['a', 'b']));
 await relay(3);
 for (const id of ['a', 'b']) assert.equal(await pages[id].evaluate(() => RallyVoice.state.peers.has('c')), false, `${id} drops c after its bye`);
 console.log('Voice radio: mesh of three, push-to-talk gating, distance levels and leaving passed');
} finally {
 await browser.close();
 server.close();
}
