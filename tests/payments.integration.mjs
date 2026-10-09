// Synthetic VK messages against a real local workerd and persistent SQLite DO.
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { once } from 'node:events';
import { setTimeout as wait } from 'node:timers/promises';
import { createHmac, createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { root } from '../scripts/godot.mjs';
const secret='integration-test-payment-secret';
const origin='http://127.0.0.1:8792';
await mkdir(join(root,'.cache'),{recursive:true});
const persistence=await mkdtemp(join(root,'.cache','payments-test-'));
let processHandle, logs='';
async function start() {
 processHandle=spawn(process.execPath,['node_modules/wrangler/bin/wrangler.js','dev','--local','--ip','127.0.0.1','--port','8792','--persist-to',persistence,'--show-interactive-dev-session=false','--var',`VK_APP_SECRET:${secret}`,'--var','VK_PAYMENTS_MODE:test','--var','VK_PAYMENTS_TEST_USERS:42','--var','VK_STAGE_02_TEST_PRICE:1'],{cwd:root,env:{...process.env,WRANGLER_SEND_METRICS:'false',VK_APP_SECRET:secret},stdio:['ignore','pipe','pipe']});
 processHandle.stdout.on('data',b=>logs=(logs+b).slice(-8000));processHandle.stderr.on('data',b=>logs=(logs+b).slice(-8000));
 for(let i=0;i<60;i++) {
  if(processHandle.exitCode!==null)throw Error('Worker stopped: '+logs);
  try {if((await fetch(origin)).ok)return;}catch{}
  await wait(500);
 }
 throw Error('Worker did not start: '+logs);
}
async function stop() {
 if(!processHandle)return;
 const stopped=once(processHandle,'exit').catch(()=>{});processHandle.kill('SIGTERM');
 await Promise.race([stopped,wait(2000)]);if(processHandle.exitCode===null)processHandle.kill('SIGKILL');
 await Promise.race([stopped,wait(2000)]);processHandle=null;
}
async function api(path,body={},token) {
 const response=await fetch(origin+path,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
 return {status:response.status,data:await response.json()};
}
async function login(user='42') {
 const p={vk_app_id:'54809523',vk_user_id:user,vk_ts:String(Math.floor(Date.now()/1000))};
 const raw=Object.keys(p).sort().map(k=>`${k}=${encodeURIComponent(p[k])}`).join('&');
 const query=new URLSearchParams({...p,sign:createHmac('sha256',secret).update(raw).digest('base64url')}).toString();
 const result=await api('/api/vk/session',{launch_params:query});assert.equal(result.status,200);return result.data;
}
async function callback(fields, signingSecret=secret) {
 const p={app_id:'54809523',user_id:'42',...fields};
 const canonical=Object.keys(p).sort().map(k=>`${k}=${p[k]}`).join('');
 const body=new URLSearchParams({...p,sig:createHash('md5').update(canonical+signingSecret).digest('hex')});
 return (await fetch(origin+'/api/vk/payments/callback',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body})).json();
}
const order={notification_type:'order_status_change_test',order_id:'9001',item_id:'stage_02',item_price:'1',status:'chargeable'};
try {
 await start();
 let session=await login();assert.deepEqual(session.entitlements.skus,[]);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0},session.session.token)).status,403);
 assert.equal((await api('/api/rooms',{stage:3,car_model:0},session.session.token)).status,403,'new canyon must be locked on first login');
 assert.equal((await api('/api/vk/payments/prepare',{sku:'stage_02'},session.session.token)).status,200);
 assert.equal((await callback({notification_type:'get_item_test',item:'stage_02'})).response.price,1);
 assert.equal((await callback(order,'forged')).error.error_code,10);
 assert.equal((await callback({...order,notification_type:'order_status_change'})).error.critical,true);
 assert.equal((await callback({...order,amount:'2'})).error.critical,true);
 const expected={response:{order_id:9001,app_order_id:9001}};
 const receipts=await Promise.all(Array.from({length:8},()=>callback(order)));
 for(const receipt of receipts)assert.deepEqual(receipt,expected);
 assert.deepEqual((await api('/api/vk/store',{},session.session.token)).data.entitlements.skus,['stage_02']);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0},session.session.token)).status,200);
 await stop();await start();
 session=await login();assert.deepEqual(session.entitlements.skus,['stage_02']);
 assert.deepEqual(await callback(order),expected);
 assert.deepEqual((await login('43')).entitlements.skus,[]);
 assert.equal((await callback({...order,user_id:'43',order_id:'9002'})).error.critical,true);
 assert.equal((await api('/api/rooms',{stage:1,car_model:0},session.session.token)).status,200);
 // The same signed VK callback flow also sells stage_04 (Red Canyon).
 for(const [i,sku] of ['stage_03','stage_04','car_04'].entries()) {
  assert.equal((await api('/api/vk/payments/prepare',{sku},session.session.token)).status,200);
  const receipt=await callback({...order,order_id:String(9100+i),item_id:sku,item:sku});
  assert.equal(receipt.response.order_id,9100+i);
 }
 session=await login();
 assert.deepEqual(session.entitlements.skus,['car_04','stage_02','stage_03','stage_04']);
 assert.equal((await api('/api/rooms',{stage:2,car_model:3},session.session.token)).status,200);
 assert.equal((await api('/api/rooms',{stage:3,car_model:3},session.session.token)).status,200,'confirmed canyon purchase permits hosting');
 console.log('PASS: real SQLite-backed payment DO; concurrent duplicate callbacks, restart, login recovery and server room gating');
} finally {await stop();await rm(persistence,{recursive:true,force:true});}
