import {chromium} from 'playwright';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {root} from './godot.mjs';
const browser=await chromium.launch({headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 for(const mobile of [false,true]) {
  const context=await browser.newContext(mobile?{viewport:{width:844,height:390},isMobile:true,hasTouch:true,userAgent:'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36'}:{viewport:{width:1280,height:720}});
  const page=await context.newPage();
  const logs=[];let ready=false;let failure='';
  page.on('console',m=>{const text=m.text();logs.push(text);console.log('[startup]',mobile,text);if(text.includes('[RFM] Запуск завершён'))ready=true;});
  page.on('pageerror',e=>failure=e.stack||String(e));
  page.on('crash',()=>failure='Browser renderer crashed');
  await page.route('https://game.test/**',async route=>{
   const path=new URL(route.request().url()).pathname;
   if(path.startsWith('/api/')){await route.fulfill({status:200,body:'{}',contentType:'application/json'});return;}
   const name=path==='/'?'index.html':path.slice(1);
   try {
    let body=await readFile(join(root,'dist',name));
    if(name==='index.html')body=Buffer.from(body.toString().replace('RallyDevice.configure(GODOT_CONFIG);','GODOT_CONFIG.args.push("--", "--smoke-test"); RallyDevice.configure(GODOT_CONFIG);'));
    await route.fulfill({status:200,body,contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.html')?'text/html':name.endsWith('.svg')?'image/svg+xml':'application/octet-stream'});
   }catch{await route.fulfill({status:404,body:'Missing '+name});}
  });
  await page.goto('https://game.test/');
  const until=Date.now()+90000;
  while(!ready&&!failure&&Date.now()<until)await page.waitForTimeout(250);
  if(failure||!ready)throw new Error(failure||'Full game startup timed out\n'+logs.slice(-30).join('\n'));
  await page.locator('#status').waitFor({state:'detached',timeout:10000});
  await page.keyboard.down('w');await page.waitForTimeout(1500);await page.keyboard.up('w');
  if(failure)throw new Error(failure);
  await page.screenshot({path:join(root,'web-startup-'+(mobile?'mobile':'desktop')+'.png')});
  console.log('FULL_GAME_STARTUP_PASS',mobile?'mobile':'desktop');
  await context.close();
 }
}finally{await browser.close();}
