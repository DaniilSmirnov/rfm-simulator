import {chromium} from 'playwright';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {root} from './godot.mjs';
import {createServer} from 'node:http';
const server=createServer(async (req,res)=>{
 const name=new URL(req.url,'http://localhost').pathname.slice(1)||'index.html';
 try {
  let body=await readFile(join(root,'dist',name));
  if(name==='index.html')body=Buffer.from(body.toString().replace('RallyDevice.configure(GODOT_CONFIG);','GODOT_CONFIG.args.push("--disable-render-loop", "--", "--smoke-test"); RallyDevice.configure(GODOT_CONFIG);'));
  res.writeHead(200,{'Content-Type':name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.svg')?'image/svg+xml':'application/octet-stream'});res.end(body);
 }catch {res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 for(const mobile of [false,true]) {
  const context=await browser.newContext(mobile?{viewport:{width:844,height:390},isMobile:true,hasTouch:true,userAgent:'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36'}:{viewport:{width:1280,height:720}});
  const page=await context.newPage();
  const logs=[];let ready=false;let failure='';
  page.on('console',m=>{const text=m.text();logs.push(text);console.log('[startup]',mobile,text);if(text.includes('[RFM] Запуск завершён'))ready=true;});
  page.on('pageerror',e=>failure=e.stack||String(e));
  page.on('crash',()=>failure='Browser renderer crashed');
  await page.goto('http://127.0.0.1:'+server.address().port);
  const until=Date.now()+90000;
  while(!ready&&!failure&&Date.now()<until)await page.waitForTimeout(250);
  if(failure||!ready)throw new Error(failure||'Full game startup timed out\n'+logs.slice(-30).join('\n'));
  await page.locator('#status').waitFor({state:'detached',timeout:10000});
  // Full-scene initialization runs here; Web rendering and physics have their own test.
  await page.waitForTimeout(1500);
  if(failure)throw new Error(failure);
  console.log('FULL_GAME_STARTUP_PASS',mobile?'mobile':'desktop');
  await context.close();
 }
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
