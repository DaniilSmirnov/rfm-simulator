import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source = name => readFile(new URL('../web/platform/'+name+'.js',import.meta.url),'utf8');
async function setup(adapter,extra={}) {
  const forwarded=[];
  const context={Request,Response,URL,JSON,Object,location:{origin:'https://game.test',href:'https://game.test/',search:'?vk_user_id=123&sign=test'},fetch:async (...args)=>{forwarded.push(args);return Response.json({ok:true});},...extra};
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
test('VK bootstrap uses init before sending raw launch params to backend',async()=>{
 const calls=[];
 const {context:c}=await setup('vk',{RallyBoot:{setStage(){}},vkBridge:{send:async(method)=>{calls.push(method);}},fetch:async(url,init)=>{
  calls.push(url);
  assert.equal(JSON.parse(init.body).launch_params,'?vk_user_id=123&sign=test');
  return Response.json({profile:{platform:'vk',nickname:'shortname',verified:true},entitlements:{skus:[]}});
 }});
 await c.RallyPlatform.ready();
 assert.deepEqual(calls,['VKWebAppInit','/api/vk/session']);
 assert.equal((await c.RallyPlatform.getProfile()).nickname,'shortname');
});
