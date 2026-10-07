import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { authenticateLaunch, authenticateSession } from '../server/auth-vk.mjs';
import worker from '../server/worker.mjs';
const now = 1780000000000;
const env = { PLATFORM:'vk', VK_APP_ID:'123', VK_APP_SECRET:'test-launch-secret', VK_SERVICE_TOKEN:'test-service-token', VK_SESSION_SECRET:'different-session-secret' };
function launch(changes = {}) {
  const params = { vk_user_id:'42', vk_app_id:'123', vk_ts:String(now/1000), vk_language:'ru', vk_access_token_settings:'friends,status', vk_ref:'space + unicode Ё', ...changes };
  const canonical = Object.keys(params).sort().map(name => `${name}=${encodeURIComponent(params[name])}`).join('&');
  const sign = createHmac('sha256',env.VK_APP_SECRET).update(canonical).digest('base64url');
  return new URLSearchParams({...params, sign}).toString();
}
const network = async (url, init) => {
  assert.equal(url, 'https://api.vk.ru/method/users.get');
  assert.equal(init.body.get('user_ids'), '42');
  assert.equal(init.body.get('fields'), 'screen_name');
  assert.equal(init.body.get('access_token'), env.VK_SERVICE_TOKEN);
  return Response.json({response:[{id:42,screen_name:'rally.fan',first_name:'Never',last_name:'Use'}]});
};
const request = token => new Request('https://game.test/api/rooms',{method:'POST',headers:token ? {Authorization:`Bearer ${token}`} : {},body:'{}'});
test('signed launch resolves server shortname and issues expiring verifiable session',async()=>{
  const data = await authenticateLaunch(launch()+'&unsigned=ignored',env,now,network);
  assert.deepEqual(data.profile,{platform:'vk',platform_user_id:'42',nickname:'rally.fan',verified:true});
  assert.equal(data.session.expires_at,now/1000+3600);
  assert.equal((await authenticateSession(request(data.session.token),env,now)).user,'42');
  assert.equal(data.entitlements.mode,'unrestricted');
  assert.ok(!JSON.stringify(data).includes('Never'));
});
test('invalid identity, signature, duplicate params and stale/future launches never call VK',async()=>{
  let calls=0;
  const blocked=()=>{calls++;throw Error('unexpected network');};
  for(const raw of [launch().replace('vk_user_id=42','vk_user_id=43'),launch()+'&vk_user_id=42',launch()+'&sign=x',launch({vk_app_id:'999'}),launch({vk_user_id:'0'}),launch({vk_ts:String(now/1000-3601)}),launch({vk_ts:String(now/1000+61)}),launch({vk_ts:'bad'}),'vk_user_id=42&sign=bad']) {
    await assert.rejects(authenticateLaunch(raw,env,now,blocked),error=>error.status===401);
  }
  assert.equal(calls,0);
});
test('sessions reject missing, tampered, expired and other-app tokens',async()=>{
  const data=await authenticateLaunch(launch(),env,now,network);
  const token=data.session.token;
  for(const [value,config,time] of [[null,env,now],[token.slice(0,-2)+'xx',env,now],[token,env,now+3600000],[token,{...env,VK_APP_ID:'456'},now],[token,{...env,VK_SESSION_SECRET:'rotated'},now]]) {
    await assert.rejects(authenticateSession(request(value),config,time),error=>error.status===401);
  }
});
test('missing config and malformed input fail closed',async()=>{
  await assert.rejects(authenticateLaunch(launch(),{},now,network),error=>error.status===503);
  for(const raw of [null,{},'x'.repeat(8193)]) await assert.rejects(authenticateLaunch(raw,env,now,network),error=>error.status===400);
});
test('VK failures and mismatched profile are rejected; missing shortname uses technical ID',async()=>{
  for(const result of [{error:{error_code:5}}, {response:[{id:43,screen_name:'other'}]},null]) {
    await assert.rejects(authenticateLaunch(launch(),env,now,async()=>Response.json(result)),error=>error.status===502);
  }
  await assert.rejects(authenticateLaunch(launch(),env,now,async()=>{throw Error('down');}),error=>error.status===502);
  const data=await authenticateLaunch(launch(),env,now,async()=>Response.json({response:[{id:42,first_name:'Do not use'}]}));
  assert.equal(data.profile.nickname,'vk42');
});
test('Worker gates VK room routes and overwrites client nickname, standalone stays anonymous',async()=>{
  assert.equal((await worker.fetch(request(),env)).status,401);
  assert.equal((await worker.fetch(new Request('https://game.test/api/vk/session',{method:'POST',body:'{}'}),{PLATFORM:'standalone'})).status,404);
  assert.equal((await worker.fetch(new Request('https://game.test/api/vk/session',{method:'POST',body:'bad'}),env)).status,400);
  const realNow=Date.now();
  const currentLaunch=launch({vk_ts:String(Math.floor(realNow/1000))});
  const data=await authenticateLaunch(currentLaunch,env,realNow,network);
  let body;
  const rooms={idFromName:id=>id,get:()=>({fetch:async req=>{body=await req.json();return Response.json({token:'room-token',player:'p'});}})};
  const create=new Request('https://game.test/api/rooms',{method:'POST',headers:{Authorization:`Bearer ${data.session.token}`},body:JSON.stringify({name:'spoofed',stage:1})});
  assert.equal((await worker.fetch(create,{...env,ROOMS:rooms})).status,200);
  assert.equal(body.name,'rally.fan');
  assert.equal(body.stage,1);
  assert.equal((await worker.fetch(new Request('https://game.test/api/rooms/ABCDEF/join',{method:'POST',body:'{"name":"Guest"}'}),{ROOMS:rooms})).status,200);
  assert.equal(body.name,'Guest');
});
