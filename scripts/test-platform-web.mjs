import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {root} from './godot.mjs';
const target = process.argv[2] ?? 'dist-vk-prototype';
if (!['dist','dist-vk-prototype'].includes(target)) throw new Error('Only standalone/prototype artifacts may use this local smoke test');
let platformNetworkRequests=0;
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/__rally_platform'){platformNetworkRequests++;res.writeHead(500).end();return;}
 try {
  let body=await readFile(join(root,target,path==='/'?'index.html':path.slice(1)));
  if(path==='/')body=Buffer.from(body.toString().replace('RallyDevice.configure(GODOT_CONFIG);','GODOT_CONFIG.args.unshift("res://scripts/platform_probe.tscn"); RallyDevice.configure(GODOT_CONFIG);'));
  res.writeHead(200,{'Content-Type':path.endsWith('.js')?'application/javascript':path==='/'?'text/html':path.endsWith('.svg')?'image/svg+xml':'application/octet-stream'}).end(body);
 } catch {res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 for(const mobile of [false,true]){
  const context=await browser.newContext(mobile?{viewport:{width:844,height:390},isMobile:true,hasTouch:true}:{viewport:{width:1280,height:720}});
  const page=await context.newPage();let profile;let failure;const logs=[];
  page.on('console',m=>{const t=m.text();logs.push(t);console.log('[platform]',t);if(t.includes('[RFM Platform] profile '))profile=JSON.parse(t.split('[RFM Platform] profile ')[1]);if(/SCRIPT ERROR|FATAL:|RuntimeError:|ERROR: Cannot open file|ERROR: Failed loading scene/.test(t))failure=t;});
  page.on('pageerror',e=>failure=String(e));
  page.on('crash',()=>failure='Browser renderer crashed');
  await page.goto('http://127.0.0.1:'+server.address().port);
  const deadline=Date.now()+90000;
  while(!profile&&!failure&&Date.now()<deadline)await page.waitForTimeout(250);
  assert.ok(!failure,failure);
  assert.ok(profile,'Godot profile roundtrip timed out: '+logs.slice(-20).join('\n'));
  assert.equal(profile.platform,target==='dist'?'standalone':'vk-prototype');
  assert.equal(profile.verified,false);
  assert.equal(platformNetworkRequests,0,'Browser-local transport leaked to server');
  await page.locator('#status').waitFor({state:'detached',timeout:10000});
  console.log('PLATFORM_WEB_PASS',target,mobile?'mobile':'desktop',profile.nickname);
  await context.close();
 }
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
