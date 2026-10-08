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
test('VK bootstrap uses init and signed URL params before backend session',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async(method)=>{calls.push(method);return {};}},fetch:async(url,init)=>{
  calls.push(url);
  const body=JSON.parse(init.body);
  assert.equal(body.launch_params,'?vk_user_id=123&vk_app_id=123&vk_ts=1&sign=test');
  assert.deepEqual(Object.keys(body),['launch_params']);
  return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]},session:{token:'test-session',expires_at:Math.floor(Date.now()/1000)+3600}});
 }});
 await c.RallyPlatform.ready();
 assert.deepEqual(calls,['VKWebAppInit','/api/vk/session']);
 assert.equal((await c.RallyPlatform.getProfile()).nickname,'shortname');
});

test('VK bootstrap falls back to Bridge launch params when iframe query is missing',async()=>{
 const calls=[];
 const location={origin:'https://game.test',href:'https://game.test/vk/',search:''};
 const {context:c}=await setup('vk',{location,RallyBoot:{setStage(){}},vkBridge:{send:async(method)=>{
  calls.push(method);
  if(method==='VKWebAppGetLaunchParams') return {vk_user_id:321,vk_app_id:123,vk_ts:456,vk_platform:'desktop_web',sign:'bridge-sign'};
  return {};
 }},fetch:async(url,init)=>{
  calls.push(url);
  const body=JSON.parse(init.body);
  const params=new URLSearchParams(body.launch_params);
  assert.equal(params.get('vk_user_id'),'321');
  assert.equal(params.get('vk_app_id'),'123');
  assert.equal(params.get('vk_ts'),'456');
  assert.equal(params.get('sign'),'bridge-sign');
  return Response.json({profile:{platform:'vk',nickname:'bridge.fan',verified:true},entitlements:{skus:[]},session:{token:'test-session',expires_at:Math.floor(Date.now()/1000)+3600}});
 }});
 await c.RallyPlatform.ready();
 assert.deepEqual(calls,['VKWebAppInit','VKWebAppGetLaunchParams','/api/vk/session']);
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

test('bootstrap delivers server catalog and restricted rights through engine transport',async()=>{
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:async()=>Response.json({profile:{platform:'vk',nickname:'fan',verified:true},entitlements:{mode:'unrestricted',skus:[]},catalog:[{sku:'stage_01',type:'stage',content_id:0,free:true,enabled:true}],session:{token:'s',expires_at:Date.now()/1000+3600}})});
 const result=await (await c.fetch('/__rally_platform',{method:'POST',body:'{"method":"getBootstrap"}'})).json();
 assert.equal(result.result.entitlements.mode,'restricted');
 assert.equal(result.result.catalog[0].sku,'stage_01');
 assert.deepEqual(result.result.entitlements.skus,[]);
});

test('isolated mock prototype remains unrestricted without claiming verified ownership',async()=>{
 const {context:c}=await setup('vk-prototype');
 const data=await (await c.fetch('/__rally_platform',{method:'POST',body:'{"method":"getBootstrap"}'})).json();
 assert.equal(data.result.profile.verified,false);
 assert.equal(data.result.entitlements.mode,'unrestricted');
 assert.deepEqual(data.result.entitlements.skus,[]);
 assert.deepEqual(data.result.catalog,[]);
});

test('safe viewport transport is local, independent of authorization, and same-origin only', async () => {
 const safe={width:844,height:390,top:88,left:44,right:44,bottom:21};
 const {context:c,forwarded}=await setup('standalone',{RallyViewport:{snapshot:()=>safe}});
 assert.deepEqual(await (await c.fetch('/__rally_viewport')).json(),safe);
 assert.equal((await c.fetch('/__rally_viewport',{method:'POST'})).status,405);
 await c.fetch('https://other.test/__rally_viewport');
 assert.equal(forwarded.length,1);
 delete c.RallyViewport;
 assert.equal((await c.fetch('/__rally_viewport')).status,503);
 assert.equal(forwarded.length,1);
});

async function purchaseSetup(status, confirmed = false, sku = 'stage_02') {
 let owned = false, calls = [], orderCalls = 0;
 const store = () => ({entitlements:{mode:'restricted',skus:owned?[sku]:[]},catalog:[{sku,purchase_enabled:true,payment_mode:'test',price:1}]});
 const {context:c}=await setup('vk',{setTimeout,clearTimeout,RallyBoot:{setStage(){}},vkBridge:{send:async(method,params)=>{
   if(method==='VKWebAppShowOrderBox') {orderCalls++;assert.deepEqual(JSON.parse(JSON.stringify(params)),{type:'item',item:sku});owned=confirmed;if(status==='throw')throw Error('mobile bridge error');return {status};}
   return {};
 }},fetch:async(input,init)=>{
   if(input==='/api/vk/session')return Response.json({profile:{platform:'vk',nickname:'fan',verified:true},session:{token:'private',expires_at:Date.now()/1000+3600},...store()});
   const request = new Request(input,init);calls.push(request);
   assert.equal(request.headers.get('Authorization'),'Bearer private');
   if(new URL(request.url).pathname.endsWith('/prepare'))return Response.json({...store(),item:sku,owned});
   return Response.json(store());
 }});
 await c.RallyPlatform.ready();
 return {c,calls,count:()=>orderCalls};
}
test('purchase cancellation does not grant and every order reconciles with server',async()=>{
 const {c,calls}=await purchaseSetup('cancel');
 const response=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'buy',sku:'stage_02'})});
 const {result}=await response.json();assert.equal(result.status,'cancel');assert.deepEqual(result.entitlements.skus,[]);
 assert.deepEqual(calls.map(r=>new URL(r.url).pathname),['/api/vk/payments/prepare','/api/vk/store']);
});
test('server confirmation wins over mobile Bridge failure; owned purchases do not open order box',async()=>{
 const {c,count}=await purchaseSetup('throw',true);
 assert.equal((await c.RallyPlatform.buy('stage_02')).status,'owned');
 assert.equal((await c.RallyPlatform.buy('stage_02')).status,'owned');
 assert.equal(count(),1);
 const response=await c.fetch('/__rally_platform',{method:'POST',body:'{"method":"refreshStore"}'});
 assert.deepEqual((await response.json()).result.entitlements.skus,['stage_02']);
});
test('Bridge success alone stays pending; malformed and concurrent orders are blocked',async()=>{
 const {c,count}=await purchaseSetup('success',false);
 await assert.rejects(c.RallyPlatform.buy('car_04'),/недоступен/);
 const pending=c.RallyPlatform.buy('stage_02');
 await assert.rejects(c.RallyPlatform.buy('stage_02'),/уже выполняется/);
 const result=await pending;assert.equal(result.status,'pending');assert.deepEqual(Array.from(result.entitlements.skus),[]);assert.equal(count(),1);
});

test('additional car and stage SKU reach VK and reconcile their own rights',async()=>{
 for(const sku of ['car_04','car_10','stage_03']) {
  const {c,count}=await purchaseSetup('success',true,sku);
  const result=await c.RallyPlatform.buy(sku);
  assert.equal(result.status,'owned');assert.equal(result.purchased_sku,sku);
  assert.deepEqual(JSON.parse(JSON.stringify(result.entitlements.skus)),[sku]);
  assert.equal(count(),1);
 }
});

test('VK request invitation selects one friend and passes the exact room in requestKey',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async(method,params)=>{
  calls.push([method,params]);
  if(method==='VKWebAppGetFriends') return {users:[{id:4567}]};
  if(method==='VKWebAppShowRequestBox') return {success:true,requestKey:params.requestKey};
  return {};
 }},fetch:async input=>{
   if(input==='/api/vk/session') return Response.json({profile:{platform:'vk',nickname:'fan',verified:true},entitlements:{skus:[]},session:{token:'verified',expires_at:Math.floor(Date.now()/1000)+3600}});
   return Response.json({});
 }});
 await c.RallyPlatform.ready();
 const response=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'inviteFriend',room_id:'a1B2c3'})});
 assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{result:{status:'sent'}});
 assert.deepEqual(calls.map(x=>x[0]),['VKWebAppInit','VKWebAppGetFriends','VKWebAppShowRequestBox']);
 assert.deepEqual(JSON.parse(JSON.stringify(calls[1][1])),{multi:false});
 assert.equal(calls[2][1].uid,4567);
 assert.equal(calls[2][1].requestKey,'rfm_room_A1B2C3');
});
test('VK invitation launch keys route only correctly formatted room ids',async()=>{
 const fakeServer=async()=>Response.json({profile:{platform:'vk',nickname:'fan',verified:true},entitlements:{skus:[]},session:{token:'verified',expires_at:Math.floor(Date.now()/1000)+3600}});
 for(const [suffix,expectRoom] of [
  ['request_key=rfm_room_AB12EF','AB12EF'],
  ['vk_request_key=rfm_room_123abc','123ABC'],
  ['request_key=rfm_room_INVALID',''],
  ['request_key=rfm_room_012345%26evil%3D1',''],
  ['request_key=not_a_room',''],
 ]) {
   const search='?vk_user_id=123&vk_app_id=123&vk_ts=1&sign=test&'+suffix;
   const loc={origin:'https://game.test',href:'https://game.test/vk/'+search,search};
   const {context:c}=await setup('vk',{location:loc,RallyBoot:{setStage(){}},vkBridge:{send:async()=>({})},fetch:fakeServer});
   const data=await c.RallyPlatform.getBootstrap();
   assert.equal(data.invite_room,expectRoom,suffix);
 }
});
test('VK launch parameters from Bridge also restore invitation room',async()=>{
 const loc={origin:'https://game.test',href:'https://game.test/vk/',search:''};
 const {context:c}=await setup('vk',{location:loc,RallyBoot:{setStage(){}},vkBridge:{send:async method=>method==='VKWebAppGetLaunchParams'
   ? {vk_user_id:123,vk_app_id:123,vk_ts:1,sign:'test',request_key:'rfm_room_AABB22'} : {}},
   fetch:async()=>Response.json({profile:{platform:'vk',nickname:'fan',verified:true},entitlements:{skus:[]},session:{token:'verified',expires_at:Math.floor(Date.now()/1000)+3600}})});
 const bootstrap=await c.RallyPlatform.getBootstrap();
 assert.equal(bootstrap.invite_room,'AABB22');
});
test('only VK production can send room invitations',async()=>{
 for(const adapter of ['standalone','vk-prototype']){
  const {context:c}=await setup(adapter);
  const resp=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'inviteFriend',room_id:'ABC123'})});
  assert.equal(resp.status,400,adapter);
 }
});
test('VK invalid room ids and dismissed picker do not send requests',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async method=>{
   calls.push(method);
   if(method==='VKWebAppGetFriends') return {users:[]};
   return {};
  }},fetch:async()=>Response.json({profile:{platform:'vk',nickname:'fan',verified:true},entitlements:{skus:[]},session:{token:'verified',expires_at:Math.floor(Date.now()/1000)+3600}})});
 await c.RallyPlatform.ready();
 const invalid=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'inviteFriend',room_id:'BAD!!'})});
 assert.equal(invalid.status,503);
 const cancelled=await c.fetch('/__rally_platform',{method:'POST',body:JSON.stringify({method:'inviteFriend',room_id:'ABC123'})});
 assert.equal(cancelled.status,200);
 assert.deepEqual(await cancelled.json(),{result:{status:'cancel'}});
 assert.deepEqual(calls,['VKWebAppInit','VKWebAppGetFriends']);
});
