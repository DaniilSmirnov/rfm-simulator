// The room's direct link between a native and a browser build: a headless
// Godot client using direct_native.gd (game/tests/direct_interop_client.gd)
// and a Chromium page with the channel Godot's Web WebRTC opens (negotiated
// id 1, unordered, no retransmits). Both offer directions are covered:
// browser guest -> native host and native guest -> browser host. Each side
// sends a packet when its channel opens and echoes what it receives.
import playwright from 'playwright';
import {createServer} from 'node:http';
import {createServer as createTcpServer} from 'node:net';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {setTimeout as wait} from 'node:timers/promises';
import {getGodot, root} from './godot.mjs';

const {chromium} = playwright;
const http = createServer((_q, r) => { r.writeHead(200, {'content-type': 'text/html'}); r.end('<!doctype html><title>direct</title><body></body>'); });
await new Promise(resolve => http.listen(0, '127.0.0.1', resolve));

let socket = null, lineBuffer = '', lastReport = null;
const inbox = [];
const tcp = createTcpServer(s => {
 socket = s;
 s.setEncoding('utf8');
 // The native client quits without closing the connection cleanly.
 s.on('error', () => {});
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
// The page offers right away; nothing may be written before the native client
// has connected, or the offer is lost (a slow runner starts Godot later).
const pending = [];
const toNative = message => {
 pending.push(JSON.stringify(message) + '\n');
 if (socket) socket.write(pending.splice(0).join(''));
};

const godot = await getGodot();
const logs = [];
const native = spawn(godot, ['--headless', '--path', 'game', '--script', 'res://tests/direct_interop_client.gd', '--', `--port=${tcp.address().port}`], {cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
for (const stream of [native.stdout, native.stderr]) stream.on('data', d => logs.push(String(d)));
let exited = null;
native.on('exit', code => { exited = code; });

const browser = await chromium.launch({headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE, args: [
 // libjuice does not resolve Chrome's mDNS host candidates.
 '--disable-features=WebRtcHideLocalIpsWithMdns', '--allow-loopback-in-peer-connection',
]});

try {
 const page = await browser.newPage();
 await page.goto(`http://127.0.0.1:${http.address().port}`);
 // "host" on the native side is answered by the page's guest, and the reverse.
 await page.evaluate(() => {
  window.links = {};
  window.outbox = [];
  for (const name of ['host', 'guest']) {
   const pc = new RTCPeerConnection({iceServers: []});
   const channel = pc.createDataChannel('fast', {negotiated: true, id: 1, ordered: false, maxRetransmits: 0});
   channel.binaryType = 'arraybuffer';
   const link = {pc, channel, received: []};
   channel.onopen = () => channel.send(new TextEncoder().encode('browser-' + name));
   channel.onmessage = event => {
    const text = new TextDecoder().decode(event.data);
    link.received.push(text);
    if (!text.startsWith('echo:')) channel.send(new TextEncoder().encode('echo:' + text));
   };
   pc.onicecandidate = event => {
    if (event.candidate) outbox.push({link: name, kind: 'candidate', mid: event.candidate.sdpMid, index: event.candidate.sdpMLineIndex ?? 0, candidate: event.candidate.candidate});
   };
   links[name] = link;
  }
  // The page's side of the native "host" link is a guest: it offers.
  return links.host.pc.createOffer().then(offer => links.host.pc.setLocalDescription(offer)).then(() => outbox.push({link: 'host', kind: 'offer', sdp: links.host.pc.localDescription.sdp}));
 });
 const connectBy = Date.now() + 30000;
 while (!socket && exited === null && Date.now() < connectBy) await wait(50);
 assert.ok(socket, 'the native client connects to the test: ' + logs.join(''));
 const deadline = Date.now() + 30000;
 const done = () => lastReport && lastReport.open.length === 2 && ['host', 'guest'].every(name => lastReport.received[name].includes('browser-' + name) && lastReport.received[name].includes('echo:native-' + name));
 let pageState = null;
 while (Date.now() < deadline && exited === null) {
  for (const message of await page.evaluate(() => outbox.splice(0))) toNative({type: 'signal', ...message});
  for (const message of inbox.splice(0)) {
   await page.evaluate(async message => {
    const pc = links[message.link].pc;
    if (message.kind === 'candidate') await pc.addIceCandidate({candidate: message.candidate, sdpMid: message.mid, sdpMLineIndex: message.index});
    else {
     await pc.setRemoteDescription({type: message.kind, sdp: message.sdp});
     if (message.kind === 'offer') {
      await pc.setLocalDescription(await pc.createAnswer());
      outbox.push({link: message.link, kind: 'answer', sdp: pc.localDescription.sdp});
     }
    }
   }, message);
  }
  pageState = await page.evaluate(() => Object.fromEntries(Object.entries(links).map(([name, link]) => [name, {state: link.pc.connectionState, channel: link.channel.readyState, received: link.received}])));
  if (done() && ['host', 'guest'].every(name => pageState[name].received.includes('native-' + name) && pageState[name].received.includes('echo:browser-' + name))) break;
  await wait(50);
 }
 assert.deepEqual(lastReport?.open?.sort(), ['guest', 'host'], `both native channels open: native=${JSON.stringify(lastReport)} page=${JSON.stringify(pageState)}`);
 for (const name of ['host', 'guest']) {
  assert.ok(lastReport.received[name].includes('browser-' + name) && lastReport.received[name].includes('echo:native-' + name), `native ${name} receives and gets its echo: ${JSON.stringify(lastReport.received)}`);
  assert.ok(pageState[name].received.includes('native-' + name) && pageState[name].received.includes('echo:browser-' + name), `browser side of ${name} receives and gets its echo: ${JSON.stringify(pageState)}`);
 }
 toNative({type: 'quit'});
 const quitBy = Date.now() + 10000;
 while (exited === null && Date.now() < quitBy) await wait(50);
 assert.equal(exited, 0, 'the native client closes its links and quits');
 console.log('Direct link interop: native <-> Chromium data channel in both offer directions, packets both ways');
} catch (error) {
 const tail = logs.join('').split('\n').slice(-40).join('\n');
 console.error(tail);
 if (process.env.GITHUB_ACTIONS) {
  const text = `${error.message}\n${tail}`.slice(-6000);
  console.log(`::error title=direct link interop::${text.replace(/%/g, '%25').replace(/\r/g, '').replace(/\n/g, '%0A')}`);
 }
 throw error;
} finally {
 if (exited === null) native.kill();
 await browser.close();
 http.close();
 tcp.close();
}
