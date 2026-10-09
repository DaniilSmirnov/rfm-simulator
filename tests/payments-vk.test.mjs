import { test } from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, webcrypto } from 'node:crypto';
import { accountStore, paymentCallback, paymentCatalog, VkPayments, PAYMENT_HANDLER_VERSION } from '../server/payments-vk.mjs';
import worker from '../server/worker.mjs';
import {catalog} from '../server/store.mjs';
const paidSkus = catalog.filter(p=>p.enabled && !p.free).map(p=>p.sku);
import { authenticateLaunch } from '../server/auth-vk.mjs';
globalThis.crypto ||= webcrypto;
export function signedCallback(fields, secret = 'test-secret') {
  const values = {app_id:'54809523',user_id:'42',...fields};
  const raw = Object.keys(values).sort().map(k=>`${k}=${values[k]}`).join('');
  return new URLSearchParams({...values,sig:createHash('md5').update(raw+secret).digest('hex')}).toString();
}
const order = {notification_type:'order_status_change_test',order_id:'701',item_id:'stage_02',item_price:'1',status:'chargeable'};
function setup(legacyRecords = []) {
  const legacy = new Map(legacyRecords);
  const db = new DatabaseSync(':memory:');
  const storage = {
    list:async ({prefix,startAfter,limit})=>new Map([...legacy].filter(([k])=>k.startsWith(prefix) && (!startAfter || k > startAfter)).sort().slice(0,limit)),
    sql:{exec:(query,...params)=>db.prepare(query).all(...params)},
    transactionSync:fn=>{db.exec('BEGIN');try {const r=fn();db.exec('COMMIT');return r;}catch(e){db.exec('ROLLBACK');throw e;}}
  };
  const data = {get size(){return db.prepare('SELECT COUNT(*) AS n FROM payment_orders').get().n;}};
  let object = new VkPayments({storage});
  const env = {VK_APP_ID:'54809523',VK_APP_SECRET:'test-secret',VK_PAYMENTS_MODE:'test',VK_PAYMENTS_TEST_USERS:'42, 43',VK_STAGE_02_TEST_PRICE:'1',PAYMENTS:{idFromName:x=>x,get:()=>({fetch:r=>object.fetch(r)})}};
  return {env,data,db,legacy,storage,restart:()=>{object=new VkPayments({storage});}};
}
test('only configured testers see one test product; disabled and real mode stay closed',async()=>{
  const {env}=setup();
  assert.deepEqual(paymentCatalog(env,'42').filter(p=>p.purchase_enabled).map(p=>p.sku),paidSkus);
  for(const user of ['44','bad'])assert.ok(paymentCatalog(env,user).every(p=>!p.purchase_enabled));
  for(const mode of ['disabled','unknown']) assert.ok(paymentCatalog({...env,VK_PAYMENTS_MODE:mode},'42').every(p=>!p.purchase_enabled));
  assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
});
test('open test access exposes winter purchase to valid VK IDs and keeps live notifications closed',async()=>{
 const {env}=setup();env.VK_PAYMENTS_TEST_USERS=' * ';
 for(const user of ['42','44','100500']) {
  assert.deepEqual(paymentCatalog(env,user).filter(p=>p.purchase_enabled).map(p=>p.sku),paidSkus);
  assert.deepEqual((await accountStore(env,user)).entitlements.skus,[]);
 }
 for(const user of ['bad','0','-42','42.5'])assert.ok(paymentCatalog(env,user).every(p=>!p.purchase_enabled));
 for(const mode of ['disabled','unknown'])assert.ok(paymentCatalog({...env,VK_PAYMENTS_MODE:mode},'44').every(p=>!p.purchase_enabled));
 await assert.rejects(paymentCallback(signedCallback({...order,user_id:'44',notification_type:'order_status_change'}),env));
 await paymentCallback(signedCallback({...order,user_id:'44'}),env);
 assert.deepEqual((await accountStore(env,'44')).entitlements.skus,['stage_02']);
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
});
test('deployed configuration enables every paid product at its real price',()=>{
 const config=JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
 assert.equal(config.vars.VK_PAYMENTS_MODE,'production');
 assert.equal(config.vars.VK_STAGE_02_TEST_PRICE,undefined);
 const products=paymentCatalog({...config.vars,PAYMENTS:{}},'100500').filter(p=>p.purchase_enabled);
 assert.equal(products.length,paidSkus.length);assert.equal(products[0].sku,'stage_02');
 assert.equal(products[0].payment_mode,'production');
 for(const p of products)assert.equal(p.price,p.type==='car'?3:20);
});
test('signed item lookup has stable SKU item ID and does not grant content',async()=>{
 const {env,data}=setup();
 const lookup=await paymentCallback(signedCallback({notification_type:'get_item_test',item:'stage_02'}),env);
 assert.equal(lookup.response.item_id,'stage_02');assert.equal(lookup.response.price,1);assert.equal(data.size,0);
 await assert.rejects(paymentCallback(signedCallback({notification_type:'get_item_test',item:'car_01'}),env));
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
 assert.equal(data.size,1);
 await assert.rejects(paymentCallback(signedCallback({...order,user_id:'43'}),env));
 env.VK_STAGE_02_TEST_PRICE='2';
 assert.deepEqual(await paymentCallback(signedCallback(order),env),receipt,'old receipt is replayed even after price change');
 await assert.rejects(paymentCallback(signedCallback({...order,order_id:'702'}),env));
 assert.deepEqual((await accountStore({...env,VK_PAYMENTS_MODE:'disabled'},'42')).entitlements.skus,[]);
});
test('storage failure never acknowledges the order and callback stays retriable',async()=>{
 const storage={sql:{exec:()=>{throw Error('storage unavailable');}}};
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
 assert.equal((await api('/api/vk/payments/prepare',{sku:'car_01'})).status,403);
 assert.equal((await api('/api/vk/store',{},'fake')).status,401);
 await paymentCallback(signedCallback(order),env);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0})).status,200);
 assert.equal((await api('/api/rooms',{stage:1,car_model:3})).status,403);
 const store=await (await api('/api/vk/store')).json();assert.deepEqual(store.entitlements.skus,['stage_02']);
 assert.equal((await (await api('/api/vk/payments/prepare',{sku:'stage_02'})).json()).owned,true);
});


test('VK reported get_item_test payload succeeds at the Worker callback without granting rights',async()=>{
 const {env,data}=setup();env.VK_PAYMENTS_TEST_USERS='*';
 const fields={app_id:'54809523',item:'stage_02',lang:'ru_RU',notification_type:'get_item_test',order_id:'2366798',receiver_id:'87478742',user_id:'87478742'};
 const response=await worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:signedCallback(fields)}),env);
 assert.equal(response.status,200);
 assert.equal(response.headers.get('X-Rally-Payments-Handler'),PAYMENT_HANDLER_VERSION);
 assert.deepEqual(await response.json(),{response:{item_id:'stage_02',title:'Зимний Турини (тест)',photo_url:'',price:1}});
 assert.equal(data.size,0);
});
test('unsupported signed callback reports actual type and deployment marker without interpreting live as test',async()=>{
 const {env}=setup();
 for(const type of ['order_status_change','get_item_test_test','test_get_item','unrecognized']) {
  const response=await worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',body:signedCallback({notification_type:type,item:'stage_02'})}),env);
  const body=await response.json();assert.equal(body.error.error_code,20);assert.equal(body.error.critical,true);
  assert.ok(body.error.error_msg.includes('notification_type='+JSON.stringify(type)));
  assert.ok(body.error.error_msg.includes(PAYMENT_HANDLER_VERSION));
  assert.ok(!body.error.error_msg.includes(env.VK_APP_SECRET));
  assert.equal(response.headers.get('X-Rally-Payments-Handler'),PAYMENT_HANDLER_VERSION);
 }
});

 test('signed get_item metadata supports the reported mismatch but never grants or enables live orders',async()=>{
  const {env,data}=setup();env.VK_PAYMENTS_TEST_USERS='*';
  const fields={app_id:'54809523',item:'stage_02',lang:'ru_RU',notification_type:'get_item',order_id:'2366806',receiver_id:'87478742',user_id:'87478742'};
  const callback=raw=>worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',body:raw}),env);
  const response=await callback(signedCallback(fields));
  assert.deepEqual(await response.json(),{response:{item_id:'stage_02',title:'Зимний Турини (тест)',photo_url:'',price:1}});
  assert.equal(data.size,0);
  const invalid=[signedCallback(fields,'wrong'),signedCallback({...fields,app_id:'9'}),signedCallback({...fields,item:'car_01'}),signedCallback({...fields,receiver_id:'43'}),signedCallback({...order,user_id:fields.user_id,notification_type:'order_status_change'})];
  for(const raw of invalid) assert.ok((await (await callback(raw)).json()).error);
  for(const mode of ['disabled','unknown']) await assert.rejects(paymentCallback(signedCallback(fields),{...env,VK_PAYMENTS_MODE:mode}));
  await assert.rejects(paymentCallback(signedCallback(fields),{...env,VK_PAYMENTS_TEST_USERS:'42'}));
  const tampered=signedCallback({...fields,notification_type:'get_item_test'}).replace('notification_type=get_item_test','notification_type=get_item');
  assert.equal((await (await callback(tampered)).json()).error.error_code,10);
  assert.equal(data.size,0);
 });

test('actual VK test order grants once with SKU and item_price and rejects inconsistent data',async()=>{
 const {env,data,restart}=setup();env.VK_PAYMENTS_TEST_USERS='*';
 const fields={app_id:'54809523',date:'1791447068',item:'stage_02',item_id:'stage_02',item_photo_url:'',item_price:'1',item_title:'Зимний Турини (тест)',notification_type:'order_status_change_test',order_id:'2366819',receiver_id:'87478742',status:'chargeable',user_id:'87478742'};
 const callback=async p=>(await worker.fetch(new Request('https://game.test/api/vk/payments/callback',{method:'POST',body:signedCallback(p)}),env)).json();
 const receipt={response:{order_id:2366819,app_order_id:2366819}};
 assert.deepEqual(await callback(fields),receipt);
 restart();assert.deepEqual(await callback(fields),receipt);
 assert.deepEqual((await accountStore(env,fields.user_id)).entitlements.skus,['stage_02']);
 assert.equal(data.size,1);
 for(const patch of [{item:'car_04'},{item_id:'car_04'},{item_price:'2'},{item_price:''},{item_price:'1.0'},{item_price:'-1'},{item_price:undefined},{amount:'2'},{notification_type:'order_status_change'},{receiver_id:'42'}]) {
  const p={...fields,...patch,order_id:'2366820'};
  for(const key of Object.keys(p)) if(p[key]===undefined) delete p[key];
  assert.ok((await callback(p)).error);
 }
 assert.equal(data.size,1);
});
test('legacy numeric item and amount remain compatible with SKU callbacks',async()=>{
 const {env}=setup();
 const legacy={notification_type:'order_status_change_test',order_id:'701',item_id:'2',amount:'1',status:'chargeable'};
 const receipt=await paymentCallback(signedCallback(legacy),env);
 assert.deepEqual(await paymentCallback(signedCallback(order),env),receipt);
});

test('legacy receipts migrate once; orphan rights never grant and SQL deletion survives restart',async()=>{
 const {env,db,restart}=setup([['orders:test:701',{user:'42',sku:'stage_02',amount:1,receipt:{order_id:701,app_order_id:701},created_at:1}],['entitlements:test:43',['stage_02']]]);
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
 assert.deepEqual((await accountStore(env,'43')).entitlements.skus,[]);
 db.prepare('DELETE FROM payment_orders WHERE user_id = ?').run('42');
 restart();
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
});

test('SQL edits control ownership and another confirmed order preserves access',async()=>{
 const {env,db}=setup();
 await paymentCallback(signedCallback(order),env);
 await paymentCallback(signedCallback({...order,order_id:'702'}),env);
 db.prepare('DELETE FROM payment_orders WHERE order_id = ?').run('701');
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
 db.prepare('UPDATE payment_orders SET user_id = ? WHERE order_id = ?').run('43','702');
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
 assert.deepEqual((await accountStore(env,'43')).entitlements.skus,['stage_02']);
});
test('invalid legacy receipt blocks migration rather than granting phantom ownership',async()=>{
 const {env}=setup([['orders:test:701',{user:'42',sku:'stage_02',amount:1,receipt:{order_id:700,app_order_id:701},created_at:1}]]);
 await assert.rejects(accountStore(env,'42'));
});

test('each paid catalog product has matching metadata, independent ownership and replay',async()=>{
 const {env}=setup();
 for(const [i,sku] of paidSkus.entries()) {
  const metadata=await paymentCallback(signedCallback({notification_type:'get_item_test',item:sku}),env);
  assert.equal(metadata.response.item_id,sku);assert.equal(metadata.response.price,1);
  const fields={notification_type:'order_status_change_test',order_id:String(800+i),item:sku,item_id:sku,item_price:'1',status:'chargeable'};
  const receipt=await paymentCallback(signedCallback(fields),env);
  assert.deepEqual(await paymentCallback(signedCallback(fields),env),receipt);
  assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[...paidSkus.slice(0,i+1)].sort());
  assert.deepEqual((await accountStore(env,'43')).entitlements.skus,[]);
 }
 for(const sku of ['unknown','stage_01','car_01']) await assert.rejects(paymentCallback(signedCallback({notification_type:'order_status_change_test',order_id:'999',item_id:sku,item_price:'1',status:'chargeable'}),env));
});

test('production purchases every paid SKU at catalog price; test rights never grant real content',async()=>{
 const {env,restart}=setup();await paymentCallback(signedCallback(order),env);
 env.VK_PAYMENTS_MODE='production';
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
 const products=paymentCatalog(env,'44').filter(p=>p.purchase_enabled);
 assert.equal(products.length,9);
 await assert.rejects(paymentCallback(signedCallback(order),env));
 for(const [i,p] of products.entries()){
  const price=p.type==='car'?3:20;
  assert.equal(p.price,price);
  assert.equal((await paymentCallback(signedCallback({notification_type:'get_item',item:p.sku,user_id:'44'}),env)).response.price,price);
  const fields={...order,notification_type:'order_status_change',order_id:String(800+i),user_id:'44',item_id:p.sku,item_price:String(price)};
  await assert.rejects(paymentCallback(signedCallback({...fields,item_price:'1'}),env));
  await assert.rejects(paymentCallback(signedCallback({...fields,receiver_id:'42'}),env));
  await assert.rejects(paymentCallback(signedCallback(fields,'forged'),env));
  const receipt=await paymentCallback(signedCallback(fields),env);
  assert.deepEqual(await paymentCallback(signedCallback(fields),env),receipt);
  await assert.rejects(paymentCallback(signedCallback({...fields,user_id:'42'}),env));
 }
 restart();
 assert.deepEqual((await accountStore(env,'44')).entitlements.skus,products.map(p=>p.sku).sort());
 env.VK_PAYMENTS_MODE='test';
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
 assert.deepEqual((await accountStore(env,'43')).entitlements.skus,[]);
});
test('old SQLite schema migrates without losing test orders or mixing production',async()=>{
 const {env,db,restart}=setup();
 await paymentCallback(signedCallback(order),env);
 db.exec("DROP INDEX payment_orders_owner; ALTER TABLE payment_orders RENAME TO orders_new; CREATE TABLE payment_orders(mode TEXT NOT NULL CHECK(mode = 'test'),order_id TEXT NOT NULL,user_id TEXT NOT NULL,sku TEXT NOT NULL,amount INTEGER NOT NULL,app_order_id INTEGER NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(mode,order_id)); INSERT INTO payment_orders SELECT * FROM orders_new; DROP TABLE orders_new;");
 restart();assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
 env.VK_PAYMENTS_MODE='production';
 assert.deepEqual((await accountStore(env,'42')).entitlements.skus,[]);
 await paymentCallback(signedCallback({...order,notification_type:'order_status_change',item_id:'car_04',item_price:'3'}),env);
 restart();assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['car_04']);
 env.VK_PAYMENTS_MODE='test';assert.deepEqual((await accountStore(env,'42')).entitlements.skus,['stage_02']);
});
