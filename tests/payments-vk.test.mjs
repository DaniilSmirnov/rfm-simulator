import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { accountStore, paymentCallback, paymentCatalog, VkPayments } from '../server/payments-vk.mjs';
import worker from '../server/worker.mjs';
import { authenticateLaunch } from '../server/auth-vk.mjs';
globalThis.crypto ||= webcrypto;
export function signedCallback(fields, secret = 'test-secret') {
  const values = {app_id:'54809523',user_id:'42',...fields};
  const raw = Object.keys(values).sort().map(k=>`${k}=${values[k]}`).join('');
  return new URLSearchParams({...values,sig:createHash('md5').update(raw+secret).digest('hex')}).toString();
}
const order = {notification_type:'order_status_change_test',order_id:'701',item_id:'2',amount:'1',status:'chargeable'};
function setup() {
  const data = new Map();
  const storage = {get:async k=>structuredClone(data.get(k)),put:async(k,v)=>data.set(k,structuredClone(v)),transaction:async fn=>{
    const backup = structuredClone(data);
    try {return await fn(storage);} catch (e) {data.clear();for(const [k,v] of backup)data.set(k,v);throw e;}
  }};
  let object = new VkPayments({storage});
  const env = {VK_APP_ID:'54809523',VK_APP_SECRET:'test-secret',VK_PAYMENTS_MODE:'test',VK_PAYMENTS_TEST_USERS:'42, 43',VK_STAGE_02_TEST_PRICE:'1',PAYMENTS:{idFromName:x=>x,get:()=>({fetch:r=>object.fetch(r)})}};
  return {env,data,restart:()=>{object=new VkPayments({storage});}};
}
test('only configured testers see one test product; disabled and real mode stay closed',async()=>{
  const {env}=setup();
  assert.deepEqual(paymentCatalog(env,'42').filter(p=>p.purchase_enabled).map(p=>p.sku),['stage_02']);
  for(const user of ['44','bad'])assert.ok(paymentCatalog(env,user).every(p=>!p.purchase_enabled));
  for(const mode of ['disabled','production']) assert.ok(paymentCatalog({...env,VK_PAYMENTS_MODE:mode},'42').every(p=>!p.purchase_enabled));
  assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
});
test('signed item lookup has numeric stable item ID and does not grant content',async()=>{
 const {env,data}=setup();
 const lookup=await paymentCallback(signedCallback({notification_type:'get_item_test',item:'stage_02'}),env);
 assert.equal(lookup.response.item_id,2);assert.equal(lookup.response.price,1);assert.equal(data.size,0);
 await assert.rejects(paymentCallback(signedCallback({notification_type:'get_item_test',item:'car_04'}),env));
});
test('callback forgery, duplicate fields, other app/user, live mode, gifts and bad orders never grant',async()=>{
 const {env,data}=setup();
 const invalid=[signedCallback(order,'wrong'),signedCallback(order)+'&user_id=42',signedCallback({...order,app_id:'9'}),signedCallback({...order,user_id:'44'}),signedCallback({...order,notification_type:'order_status_change'}),signedCallback({...order,receiver_id:'43'}),signedCallback({...order,item_id:'3'}),signedCallback({...order,amount:'2'}),signedCallback({...order,status:'cancelled'}),signedCallback({...order,order_id:'9007199254740993'})];
 for(const raw of invalid) await assert.rejects(paymentCallback(raw,env));
 assert.equal(data.size,0);
});
test('atomic idempotent receipt and ownership survive recreation; changing owner conflicts',async()=>{
 const {env,data,restart}=setup();
 const receipt=await paymentCallback(signedCallback(order),env);
 assert.deepEqual(receipt,{response:{order_id:701,app_order_id:701}});
 restart();
 assert.deepEqual(await paymentCallback(signedCallback(order),env),receipt);
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
 assert.deepEqual((await accountStore(env,'43')).entitlements.skus,[]);
 assert.equal(data.size,3);
 await assert.rejects(paymentCallback(signedCallback({...order,user_id:'43'}),env));
 env.VK_STAGE_02_TEST_PRICE='2';
 assert.deepEqual(await paymentCallback(signedCallback(order),env),receipt,'old receipt is replayed even after price change');
 await assert.rejects(paymentCallback(signedCallback({...order,order_id:'702'}),env));
 assert.deepEqual((await accountStore({...env,VK_PAYMENTS_MODE:'disabled'},'42')).entitlements.skus,[]);
});
test('storage failure never acknowledges the order and callback stays retriable',async()=>{
 const storage={get:async()=>undefined,transaction:async()=>{throw Error('storage unavailable');}};
 const {env}=setup();const object=new VkPayments({storage});env.PAYMENTS.get=()=>object;
 const response=await worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',body:signedCallback(order)}),env);
 const body=await response.json();assert.equal(body.error.critical,false);assert.equal(body.error.error_code,1);
});
async function session(env) {
 const params=new URLSearchParams({vk_app_id:env.VK_APP_ID,vk_user_id:'42',vk_ts:String(Math.floor(Date.now()/1000))});
 const canonical=[...params].sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>`${k}=${encodeURIComponent(v)}`).join('&');
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.VK_APP_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 params.set('sign',Buffer.from(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(canonical))).toString('base64url'));
 return authenticateLaunch(params.toString(),env);
}
test('Worker restores account rights on login and gates rooms using server ownership',async()=>{
 const {env}=setup();env.ROOMS={idFromName:x=>x,get:()=>({fetch:async r=>Response.json({stage:JSON.parse(await r.text()).stage})})};
 const login=await session(env);
 const api=(path,body={},token=login.session.token)=>worker.fetch(new Request('https://game.test'+path,{method:'POST',headers:{Authorization:'Bearer '+token},body:JSON.stringify(body)}),env);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0})).status,403);
 assert.equal((await api('/api/vk/payments/prepare',{sku:'stage_02'})).status,200);
 assert.equal((await api('/api/vk/payments/prepare',{sku:'car_04'})).status,403);
 assert.equal((await api('/api/vk/store',{},'fake')).status,401);
 await paymentCallback(signedCallback(order),env);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0})).status,200);
 assert.equal((await api('/api/rooms',{stage:1,car_model:3})).status,403);
 const store=await (await api('/api/vk/store')).json();assert.deepEqual(store.entitlements.skus,['stage_02']);
 assert.equal((await (await api('/api/vk/payments/prepare',{sku:'stage_02'})).json()).owned,true);
});
