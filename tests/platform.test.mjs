import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source = name => readFile(new URL('../web/platform/'+name+'.js',import.meta.url),'utf8');
async function setup(adapter,extra={}) {
  const forwarded=[];
  const context={Request,Response,Headers,AbortSignal,URL,URLSearchParams,JSON,Object,location:{origin:'https://game.test',href:'https://game.test/',search:'?vk_user_id=123&vk_app_id=123&vk_ts=1&sign=test'},fetch:async (...args)=>{forwarded.push(args);return Response.json({ok:true});},...extra};
  context.window=context;
  runInNewContext(await source(adapter),context);
  runInNewContext(await source('transport'),context);
  return {context,forwarded};
}
test('real HTTP-shaped requests reach prototype adapter without network',async()=>{
  const {context:c,forwarded}=await setup('vk-prototype');
  const r=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'getProfile'})});
  assert.equal(r.status,200);
  assert.deepEqual(await r.json(),{result:{platform:'vk-prototype',nickname:'vk_prototype',verified:false}});
  assert.equal(forwarded.length,0);
  await c.fetch('/api/rooms',{method:'POST',body:'{}'});
  await c.fetch('https://other.test/__rally_platform',{method:'POST',body:'{}'});
  assert.equal(forwarded.length,2);
});
test('transport rejects unknown methods, invalid JSON and oversized input',async()=>{
 const {context:c}=await setup('standalone');
 for(const [body,status] of [['{"method":"buy"}',400],['{"method":"__proto__"}',400],['bad',503],['x'.repeat(4097),413]]) {
  assert.equal((await c.fetch('/__rally_platform',{method:'POST',body})).status,status);
 }
 assert.equal((await c.fetch('/__rally_platform')).status,405);
});
test('standalone profile stays anonymous and unrestricted',async()=>{
 const {context:c}=await setup('standalone');
 assert.equal((await c.RallyPlatform.getProfile()).platform,'standalone');
 assert.equal((await c.RallyPlatform.getEntitlements()).mode,'unrestricted');
});
test('VK initialization failure never creates a mock or anonymous profile',async()=>{
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>{throw new Error('init failed');}}});
 await assert.rejects(c.RallyPlatform.ready(),/init failed/);
 assert.equal((await c.fetch('/__rally_platform',{method:'POST',body:'{"method":"getProfile"}'})).status,503);
});
test('VK requires a server-verified profile rather than launch query identity',async()=>{
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:async()=>Response.json({profile:{platform:'vk',nickname:'fake',verified:false},entitlements:{skus:[]}})});
 await assert.rejects(c.RallyPlatform.ready(),/Некорректный/);
});
test('VK bootstrap uses init, signed URL params and Bridge profile before backend session',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async(method)=>{
  calls.push(method);
  if(method==='VKWebAppGetUserInfo') return {id:123,screen_name:'bridge.shortname'};
  return {};
 }},fetch:async(url,init)=>{
  calls.push(url);
  const body=JSON.parse(init.body);
  assert.equal(body.launch_params,'?vk_user_id=123&vk_app_id=123&vk_ts=1&sign=test');
  assert.deepEqual(body.bridge_profile,{id:123,screen_name:'bridge.shortname'});
  return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]},session:{token:'test-session',expires_at:Math.floor(Date.now()/1000)+3600}});
 }});
 await c.RallyPlatform.ready();
 assert.deepEqual(calls,['VKWebAppInit','VKWebAppGetUserInfo','/api/vk/session']);
 assert.equal((await c.RallyPlatform.getProfile()).nickname,'shortname');
});

test('VK bootstrap falls back to Bridge launch params when iframe query is missing',async()=>{
 const calls=[];
 const location={origin:'https://game.test',href:'https://game.test/vk/',search:''};
 const {context:c}=await setup('vk',{location,RallyBoot:{setStage(){}},vkBridge:{send:async(method)=>{
  calls.push(method);
  if(method==='VKWebAppGetLaunchParams') return {vk_user_id:321,vk_app_id:123,vk_ts:456,vk_platform:'desktop_web',sign:'bridge-sign'};
  if(method==='VKWebAppGetUserInfo') return {id:321,screen_name:'bridge.fan'};
  return {};
 }},fetch:async(url,init)=>{
  calls.push(url);
  const body=JSON.parse(init.body);
  const params=new URLSearchParams(body.launch_params);
  assert.equal(params.get('vk_user_id'),'321');
  assert.equal(params.get('vk_app_id'),'123');
  assert.equal(params.get('vk_ts'),'456');
  assert.equal(params.get('sign'),'bridge-sign');
  assert.deepEqual(body.bridge_profile,{id:321,screen_name:'bridge.fan'});
  return Response.json({profile:{platform:'vk',nickname:'bridge.fan',verified:true},entitlements:{skus:[]},session:{token:'test-session',expires_at:Math.floor(Date.now()/1000)+3600}});
 }});
 await c.RallyPlatform.ready();
 assert.deepEqual(calls,['VKWebAppInit','VKWebAppGetLaunchParams','VKWebAppGetUserInfo','/api/vk/session']);
});

test('VK attaches in-memory bearer only to same-origin room requests',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:async(input,init)=>{
  if(input==='/api/vk/session') return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]},session:{token:'private-session',expires_at:Math.floor(Date.now()/1000)+3600}});
  calls.push(new Request(input,init));return Response.json({ok:true});
 }});
 await c.RallyPlatform.ready();
 await c.fetch('/api/rooms',{method:'POST',body:'{"name":"ignored"}'});
 await c.fetch('https://other.test/api/rooms',{method:'POST',body:'{}'});
 assert.equal(calls[0].headers.get('Authorization'),'Bearer private-session');
 assert.equal(calls[1].headers.get('Authorization'),null);
 assert.equal(await calls[0].text(),'{"name":"ignored"}');
});

test('VK expired session blocks room access without sending a token',async()=>{
 let roomCalls=0;
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:async(input)=>{
  if(input==='/api/vk/session')return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]},session:{token:'expired',expires_at:1}});
  roomCalls++;return Response.json({});
 }});
 assert.equal((await c.fetch('/api/rooms',{method:'POST',body:'{}'})).status,401);
 assert.equal(roomCalls,0);
});

test('VK network errors retain network semantics instead of claiming session expiry',async()=>{
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:async(input)=>{
  if(input==='/api/vk/session')return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]},session:{token:'valid',expires_at:Math.floor(Date.now()/1000)+3600}});
  throw new Error('Network unavailable');
 }});
 await assert.rejects(c.fetch('/api/rooms',{method:'POST',body:'{}'}),/Network unavailable/);
});
