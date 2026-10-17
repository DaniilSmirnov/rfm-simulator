import {test} from 'node:test';
import assert from 'node:assert/strict';
import {enforceLimit, LimitError, limitResponse} from '../server/rate-limits.mjs';
import worker, {RallyRoom} from '../server/worker.mjs';
import {RoomState, protocol} from '../server/room-core.mjs';
import {authenticateLaunch} from '../server/auth-vk.mjs';
import {createHmac} from 'node:crypto';

test('configured limits fail closed on absent, broken or malformed bindings', async () => {
  for (const binding of [undefined,{limit:async()=>{throw Error('secret detail');}},{limit:async()=>({})}]) {
    await assert.rejects(enforceLimit({RATE_LIMIT_ENABLED:'true',TEST:binding},'TEST','user:42'),e=>e.status===503);
  }
  await assert.rejects(enforceLimit({TEST:{limit:async()=>({success:false})}},'TEST','user:42'),e=>e.status===429);
  const response = limitResponse(new LimitError(429));
  assert.equal(response.status,429);
  assert.equal(response.headers.get('Retry-After'),'60');
  assert.equal((await response.json()).retry_after,60);
});

test('login and room entry are limited before expensive work, using edge IP rather than submitted identity', async () => {
  for (const [path,binding] of [['/api/vk/session','AUTH_RATE_LIMIT'],['/api/rooms','ROOM_ENTRY_RATE_LIMIT'],['/api/rooms/ABCDEF/join','ROOM_ENTRY_RATE_LIMIT']]) {
    let key;
    const env = {API_RATE_LIMIT:{limit:async()=>({success:true})},[binding]:{limit:async args=>{key=args.key;return {success:false};}}};
    const result = await worker.fetch(new Request('https://game.test'+path,{method:'POST',headers:{'CF-Connecting-IP':'192.0.2.1'},body:'invalid'}),env);
    assert.equal(result.status,429);
    assert.equal(key,'ip:192.0.2.1');
  }
});

test('sync allows normal 10 Hz traffic and isolates participants, then recovers and retains state on restore', () => {
  const room = new RoomState();
  const host = room.add('Host',0,true);
  const guest = room.add('Guest',0);
  const state = {pos:[0,0,0],car:[0,0,0],heading:0,yaw:0,pitch:0,in_car:false};
  for(let i=0;i<150;i++) room.sync({token:host.token,state},i*50);
  assert.throws(()=>room.sync({token:host.token,state},8000),e=>e.status===429);
  room.sync({token:guest.token,state},8000);
  const restored = new RoomState(structuredClone(room.data));
  assert.throws(()=>restored.sync({token:host.token,state},9000),e=>e.status===429);
  restored.sync({token:host.token,state},10000);
  assert.throws(()=>restored.sync({token:'fake',state},10000),e=>e.status===401);
  for(let i=0;i<100;i++) restored.sync({token:host.token,state},11000+i*100);
});

test('heartbeat flood cannot consume sync allowance or prevent leaving', () => {
  const room = new RoomState();
  const host = room.add('Host',0,true);
  for(let i=0;i<30;i++) room.heartbeat(host.token,1000);
  assert.throws(()=>room.heartbeat(host.token,1000),e=>e.status===429);
  room.leave(host.token);
  assert.equal(room.data.closed,true);
});

test('payment callback keeps VK signature and error protocol without consuming client limit', async () => {
  const result = await worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',body:'bad'}),{API_RATE_LIMIT:{limit:()=>{throw Error('must not call');}}});
  assert.equal(result.status,200);
  assert.ok((await result.json()).error);
});

test('store and purchase use verified account ID even when launch sessions are renewed', async () => {
  const env = {VK_APP_ID:'123',VK_APP_SECRET:'test'};
  const params = {vk_app_id:'123',vk_ts:String(Math.floor(Date.now()/1000)),vk_user_id:'42'};
  const canonical = Object.keys(params).sort().map(k=>`${k}=${encodeURIComponent(params[k])}`).join('&');
  const sign = createHmac('sha256','test').update(canonical).digest('base64url');
  const {session} = await authenticateLaunch(new URLSearchParams({...params,sign}).toString(),env);
  for(const [path,binding] of [['store','STORE_RATE_LIMIT'],['payments/prepare','PURCHASE_RATE_LIMIT']]) {
    let key;
    env[binding] = {limit:async args=>{key=args.key;return {success:false};}};
    const response = await worker.fetch(new Request('https://game.test/api/vk/'+path,{method:'POST',headers:{Authorization:'Bearer '+session.token},body:'{}'}),env);
    assert.equal(response.status,429);
    assert.equal(key,'user:42');
  }
});

const request = (path, body, headers = {}) => new Request('https://game.test'+path,{method:'POST',body,headers,duplex:'half'});
const room = () => { const r = new RallyRoom({blockConcurrencyWhile:()=>{}, storage:{put:async()=>{},getAlarm:async()=>null,setAlarm:async()=>{}},getWebSockets:()=>[]}); r.room = new RoomState(); return r; };
const padded = (limit, character) => { const prefix = JSON.stringify({name:'Host',padding:''}); const count = Math.floor((limit-prefix.length)/Buffer.byteLength(character)); return prefix.slice(0,-2)+character.repeat(count)+'x'.repeat(limit-prefix.length-count*Buffer.byteLength(character))+'"}'; };

test('room HTTP and WebSocket limits count UTF-8 bytes at ASCII, Cyrillic and emoji boundaries',async()=>{
  for (const character of ['x','я','😀']) {
    const raw = padded(protocol.max_message_bytes,character);
    assert.equal(Buffer.byteLength(raw),protocol.max_message_bytes);
    assert.equal((await room().fetch(request('/create',raw))).status,200);
    assert.equal((await room().fetch(request('/create',raw+' '))).status,413);
    const sent=[];
    await room().webSocketMessage({send:value=>sent.push(JSON.parse(value))},raw+' ');
    assert.equal(sent[0].status,413);
  }
});

test('room creation cancels oversized streams with missing or false Content-Length',async()=>{
  for (const headers of [{},{'Content-Length':'1'},{'Content-Length':'999999'}]) {
    let pulled=0, cancelled=false;
    const body = new ReadableStream({pull(controller){pulled++; controller.enqueue(new Uint8Array(512)); if(pulled===100)controller.close();},cancel(){cancelled=true;}});
    const response=await worker.fetch(request('/api/rooms',body,headers),{});
    assert.equal(response.status,413);
    assert.equal(cancelled,true);
    assert.ok(pulled<=4,`read ${pulled} chunks`);
  }
});

test('session and callback enforce byte limits while preserving callback error protocol',async()=>{
  assert.equal((await worker.fetch(request('/api/vk/session','я'.repeat(8193)),{})).status,413);
  const response=await worker.fetch(request('/api/vk/payments/callback','я'.repeat(8193)),{VK_APP_ID:'123',VK_APP_SECRET:'test'});
  assert.equal(response.status,200);
  assert.deepEqual((await response.json()).error,{error_code:20,error_msg:'Слишком большое уведомление.',critical:true});
});

test('direct signal limit counts serialized UTF-8 bytes',()=>{
  const r=new RoomState(); const h=r.add('Host',0,true); const g=r.add('Guest',0);
  const data={sdp:'я'.repeat(Math.floor(protocol.direct.max_signal_bytes/2))};
  assert.throws(()=>r.signal(h.token,g.player,data,1),error=>error.status===400);
});

test('room creation accepts byte boundary across split UTF-8 chunks and rejects one more byte',async()=>{
  const env={ROOMS:{idFromName:id=>id,get:()=>({fetch:async req=>{assert.equal(Buffer.byteLength(await req.text()),1024); return Response.json({token:'ok'});}})}};
  for (const character of ['x','я','😀']) {
    const raw=padded(1024,character);
    const bytes=new TextEncoder().encode(raw);
    let offset=0;
    const body=new ReadableStream({pull(controller){if(offset===bytes.length){controller.close();return;}controller.enqueue(bytes.subarray(offset,++offset));}});
    assert.equal((await worker.fetch(request('/api/rooms',body),env)).status,200);
    assert.equal((await worker.fetch(request('/api/rooms',raw+' '),env)).status,413);
  }
});
