// Native and browser radios in one room: a headless Godot client using the
// native/voice extension (game/tests/voice_interop_client.gd) and two Chromium
// pages running web/voice-chat.js with a fake microphone. The test relays
// signaling like the room server. Members "0" < "a" < "b": the browser "0"
// calls the native "a", and the native "a" calls the browser "b", so both
// offer directions are covered, and audio is checked both ways.
import playwright from 'playwright';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createServer as createTcpServer} from 'node:net';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {setTimeout as wait} from 'node:timers/promises';
import {getGodot, root} from './godot.mjs';

const {chromium} = playwright;
const source = await readFile(new URL('../web/voice-chat.js', import.meta.url), 'utf8');
const members = ['0', 'a', 'b'];
const http = createServer((_q, r) => { r.writeHead(200, {'content-type': 'text/html'}); r.end('<!doctype html><title>voice</title><body></body>'); });
await new Promise(resolve => http.listen(0, '127.0.0.1', resolve));

let socket = null, lineBuffer = '', lastReport = null;
const inbox = [];
const tcp = createTcpServer(s => {
 socket = s;
 s.setEncoding('utf8');
 s.on('data', chunk => {
  lineBuffer += chunk;
  let i;
  while ((i = lineBuffer.indexOf('\n')) >= 0) {
   const message = JSON.parse(lineBuffer.slice(0, i));
   lineBuffer = lineBuffer.slice(i + 1);
   if (message.type === 'report') lastReport = message; else inbox.push(message);
  }
 });
});
await new Promise(resolve => tcp.listen(0, '127.0.0.1', resolve));
const toNative = message => socket?.write(JSON.stringify(message) + '\n');

const godot = await getGodot();
const logs = [];
const native = spawn(godot, ['--headless', '--path', 'game', '--script', 'res://tests/voice_interop_client.gd', '--',
 `--port=${tcp.address().port}`, '--id=a', `--members=${members.join(',')}`], {cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
for (const stream of [native.stdout, native.stderr]) stream.on('data', d => logs.push(String(d)));
let exited = null;
native.on('exit', code => { exited = code; });

const browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE, args: [
 '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required',
 // libjuice does not resolve Chrome's mDNS host candidates.
 '--disable-features=WebRtcHideLocalIpsWithMdns', '--allow-loopback-in-peer-connection',
]});
const pages = {};

async function relay() {
 for (const message of inbox.splice(0)) {
  if (message.type === 'signal') await pages[message.to]?.evaluate(([from, data]) => RallyVoice.onSignal(from, data), ['a', message.data]);
 }
 for (const id of ['0', 'b']) {
  const out = JSON.parse(await pages[id].evaluate(() => RallyVoice.tick('[]')));
  for (const envelope of out.signals) {
   if (envelope.to === 'a') toNative({type: 'signal', from: id, data: envelope.data});
   else await pages[envelope.to].evaluate(([from, data]) => RallyVoice.onSignal(from, data), [id, envelope.data]);
  }
 }
}

async function report() {
 lastReport = null;
 toNative({type: 'report'});
 const deadline = Date.now() + 5000;
 while (!lastReport && Date.now() < deadline) { await relay(); await wait(20); }
 assert.ok(lastReport, 'the native client reports');
 return lastReport;
}

// Browser-side playback of one member, measured after the radio filters.
async function heardInBrowser(page, from, ms) {
 await page.evaluate(from => {
  const audio = RallyVoice.state.peers.get(from)?.audio;
  if (!audio) return;
  if (!audio.probe) {
   audio.probe = audio.gain.context.createAnalyser();
   audio.probe.fftSize = 2048;
   audio.gain.connect(audio.probe);
   const samples = new Float32Array(audio.probe.fftSize);
   audio.timer = setInterval(() => {
    audio.probe.getFloatTimeDomainData(samples);
    let sum = 0;
    for (const v of samples) sum += v * v;
    audio.peak = Math.max(audio.peak || 0, Math.sqrt(sum / samples.length));
   }, 20);
  }
  audio.peak = 0;
 }, from);
 const end = Date.now() + ms;
 while (Date.now() < end) { await relay(); await wait(50); }
 return page.evaluate(from => RallyVoice.state.peers.get(from)?.audio?.peak ?? -1, from);
}

async function heardInNative(from, ms) {
 toNative({type: 'reset_peak'});
 const end = Date.now() + ms;
 while (Date.now() < end) { await relay(); await wait(50); }
 return (await report()).peak[from] ?? -1;
}

try {
 for (const id of ['0', 'b']) {
  const context = await browser.newContext({permissions: ['microphone']});
  pages[id] = await context.newPage();
  await pages[id].goto(`http://127.0.0.1:${http.address().port}`);
  await pages[id].addScriptTag({content: source});
  await pages[id].evaluate(([id, members]) => { RallyVoice.syncMembers(members); return RallyVoice.join({localId: id, session: `browser-${id}-session`, iceServers: []}); }, [id, members]);
 }
 const deadline = Date.now() + 30000;
 while (!socket && Date.now() < deadline && exited === null) await wait(50);
 assert.ok(socket, 'the native client connects to the test: ' + logs.join(''));
 let state = null;
 while (Date.now() < deadline) {
  await relay();
  const counts = await Promise.all(['0', 'b'].map(id => pages[id].evaluate(() => JSON.parse(RallyVoice.tick('[]')).connected)));
  state = await report();
  if (state.connected === 2 && counts.every(n => n === 2)) break;
  await wait(100);
 }
 assert.equal(state?.connected, 2, `native links to both browsers: ${JSON.stringify(state)}`);
 for (const id of ['0', 'b']) assert.equal(await pages[id].evaluate(() => [...RallyVoice.state.peers.values()].filter(p => p.connected).length), 2, `${id} is linked with both`);

 assert.ok(await heardInNative('0', 1500) < 0.002, 'native hears nothing before the browser presses the key');
 await pages['0'].evaluate(() => RallyVoice.setPtt(true));
 const ready = Date.now() + 5000;
 while (await pages['0'].evaluate(() => RallyVoice.state.mic) !== 'ready' && Date.now() < ready) await wait(50);
 const fromBrowser = await heardInNative('0', 2500);
 assert.ok(fromBrowser > 0.01, `native hears the browser that called it (${fromBrowser})`);
 await pages['0'].evaluate(() => RallyVoice.setPtt(false));
 await heardInNative('0', 800);
 assert.ok(await heardInNative('0', 1200) < 0.002, 'releasing the browser key silences it on native');

 assert.ok(await heardInBrowser(pages.b, 'a', 1200) < 0.002, 'browser hears nothing before native transmits');
 toNative({type: 'tone', on: true});
 const fromNativeB = await heardInBrowser(pages.b, 'a', 2000);
 const fromNative0 = await heardInBrowser(pages['0'], 'a', 1500);
 assert.ok(fromNativeB > 0.02, `the browser native called hears it (${fromNativeB})`);
 assert.ok(fromNative0 > 0.02, `the browser that called native hears it (${fromNative0})`);
 toNative({type: 'tone', on: false});
 await heardInBrowser(pages.b, 'a', 800);
 assert.ok(await heardInBrowser(pages.b, 'a', 1200) < 0.002, 'releasing the native key silences it in the browser');

 toNative({type: 'quit'});
 const quitBy = Date.now() + 10000;
 while (exited === null && Date.now() < quitBy) { await relay(); await wait(50); }
 await relay();
 for (const id of ['0', 'b']) assert.equal(await pages[id].evaluate(() => RallyVoice.state.peers.has('a')), false, `${id} drops native after its bye`);
 console.log('Voice interop: native <-> Chromium in both offer directions, audio both ways, push-to-talk gating and bye passed');
} catch (error) {
 console.error(logs.join('').split('\n').slice(-40).join('\n'));
 throw error;
} finally {
 if (exited === null) native.kill();
 await browser.close();
 http.close();
 tcp.close();
}
