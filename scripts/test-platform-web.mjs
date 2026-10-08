import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {createHmac} from 'node:crypto';
import {authenticateLaunch, authenticateSession} from '../server/auth-vk.mjs';
import {root} from './godot.mjs';
const target = process.argv[2] ?? 'dist-vk-prototype';
if (!['dist','dist-vk','dist/vk','dist-vk-prototype'].includes(target)) throw new Error('Unknown platform artifact');
// Synthetic signed launch and VK API fixture: never used in deployable code.
const isVk = target === 'dist-vk' || target === 'dist/vk';
const mount = target === 'dist/vk' ? '/vk/' : '/';
const testEnv = {VK_APP_ID:'123', VK_APP_SECRET:'test-only-launch-secret', VK_SERVICE_TOKEN:'test-only-service-token', VK_SESSION_SECRET:'test-only-session-secret'};
function signedLaunch() {
 const params={vk_app_id:'123',vk_user_id:'42',vk_ts:String(Math.floor(Date.now()/1000)),vk_platform:'desktop_web'};
 const canonical=Object.keys(params).sort().map(key=>`${key}=${encodeURIComponent(params[key])}`).join('&');
 return new URLSearchParams({...params,sign:createHmac('sha256',testEnv.VK_APP_SECRET).update(canonical).digest('base64url')}).toString();
}
let authorizedRoomRequests=0;
let platformNetworkRequests=0;
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(isVk && path==='/api/vk/session') {
  try {
   let raw='';for await(const chunk of req)raw+=chunk;
   const data=await authenticateLaunch(JSON.parse(raw).launch_params,testEnv,Date.now(),async()=>Response.json({response:[{id:42,screen_name:'wasm_vk_fan'}]}));
   res.writeHead(200,{'Content-Type':'application/json'}).end(JSON.stringify(data));
  } catch(error) {res.writeHead(error.status||500).end();}
  return;
 }
 if(isVk && path==='/api/rooms') {
  try {
   await authenticateSession(new Request('http://localhost/api/rooms',{headers:req.headers}),testEnv);
   authorizedRoomRequests++;res.writeHead(200,{'Content-Type':'application/json'}).end('{}');
  } catch(error) {res.writeHead(error.status||500).end();}
  return;
 }
 if(path==='/__rally_platform'){platformNetworkRequests++;res.writeHead(500).end();return;}
 const assetPath = path.startsWith(mount) ? path.slice(mount.length) : null;
 if (assetPath === null) {res.writeHead(404).end();return;}
 try {
  let body=await readFile(join(root,target,assetPath||'index.html'));
  if(!assetPath)body=Buffer.from(body.toString().replace('RallyDevice.configure(GODOT_CONFIG);','GODOT_CONFIG.args.unshift("res://scripts/platform_probe.tscn"); RallyDevice.configure(GODOT_CONFIG);'));
  res.writeHead(200,{'Content-Type':path.endsWith('.js')?'application/javascript':!assetPath?'text/html':path.endsWith('.svg')?'image/svg+xml':'application/octet-stream'}).end(body);
 } catch {res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 for(const mobile of [false,true]){
  const context=await browser.newContext(mobile?{viewport:{width:844,height:390},isMobile:true,hasTouch:true}:{viewport:{width:1280,height:720}});
  const page=await context.newPage();let profile;let access;let failure;const logs=[];
  page.on('console',m=>{const t=m.text();logs.push(t);console.log('[platform]',t);if(t.includes('[RFM Platform] profile '))profile=JSON.parse(t.split('[RFM Platform] profile ')[1]);if(t.includes('[RFM Platform] access '))access=JSON.parse(t.split('[RFM Platform] access ')[1]);if(/SCRIPT ERROR|FATAL:|RuntimeError:|ERROR: Cannot open file|ERROR: Failed loading scene/.test(t))failure=t;});
  page.on('pageerror',e=>failure=String(e));
  page.on('crash',()=>failure='Browser renderer crashed');
  if(isVk) await page.route('**/vk-bridge.js',route=>route.fulfill({contentType:'application/javascript',body:'window.vkBridge={subscribe:fn=>window.testVKConfig=fn,send:async method=>{if(method!=="VKWebAppInit")throw Error("Unexpected bridge method");return {result:true};}};'}));
  await page.goto('http://127.0.0.1:'+server.address().port+mount+(isVk?'?'+signedLaunch():''));
  const deadline=Date.now()+90000;
  while((!profile||!access)&&!failure&&Date.now()<deadline)await page.waitForTimeout(250);
  assert.ok(!failure,failure);
  assert.ok(profile,'Godot profile roundtrip timed out: '+logs.slice(-20).join('\n'));
  assert.equal(profile.platform,target==='dist'?'standalone':isVk?'vk':'vk-prototype');
  assert.equal(profile.verified,isVk);
  assert.deepEqual(access,{mode:isVk?'restricted':'unrestricted',stage_1:true,stage_2:!isVk,car_3:true,car_4:!isVk});
  if(isVk) {
   assert.equal(profile.nickname,'wasm_vk_fan');
   assert.equal(await page.evaluate(async()=> (await fetch('/api/rooms',{method:'POST',body:'{}'})).status),200);
   assert.equal(authorizedRoomRequests,mobile?2:1);
  }
  assert.equal(platformNetworkRequests,0,'Browser-local transport leaked to server');
  assert.equal(await page.locator('#rally-fullscreen').count(),1);
  if(isVk&&mobile) {
   await page.evaluate(()=>window.testVKConfig({detail:{type:'VKWebAppUpdateConfig',data:{insets:{top:0,left:44,right:44,bottom:21}}}}));
   const safe=await page.evaluate(()=>window.RallyViewport.snapshot());
   assert.equal(safe.top,0);assert.equal(safe.left,44);assert.equal(safe.bottom,21);
   await page.setViewportSize({width:390,height:844});
   assert.equal(await page.locator('#rally-rotate button').count(),0);
   await page.setViewportSize({width:844,height:390});
  }
  await page.locator('#status').waitFor({state:'detached',timeout:10000});
  console.log('PLATFORM_WEB_PASS',target,mobile?'mobile':'desktop',profile.nickname);
  await context.close();
 }
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
