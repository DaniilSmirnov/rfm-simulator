import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { connect as tcpConnect } from 'node:net';
import { readFile, writeFile, cp, mkdir } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { setTimeout as wait } from 'node:timers/promises';
import assert from 'node:assert/strict';
import { getGodot, root, run } from './godot.mjs';

const web = process.argv.includes('--web');
// --socket runs the room over WebSocket with 150 ms added each way; the default
// pins HTTP polling so injected HTTP losses stay meaningful.
const socketMode = process.argv.includes('--socket');
const transportArgs = socketMode ? [] : ['--room-transport=http'];
const SOCKET_DELAY = 150;
const workerPort = 8793;
const processes = [];
let browserFactory;
const browsers = [];
let relay;
let errors = [];
const samples = {};
const tokenRoles = new Map();
const controls = { host: {id:0,action:'pause'}, guest: {id:0,action:'pause'} };
const latest = role => samples[role]?.at(-1);
const logs = [];
function observe(role, line) {
  if (line.includes('NETWORK_SAMPLE ')) {
    const sample = JSON.parse(line.slice(line.indexOf('NETWORK_SAMPLE ') + 15));
    (samples[role] ??= []).push(sample);
  } else if (/SCRIPT ERROR|Parse Error|RuntimeError|unreachable|NETWORK_FAIL|ERROR:/.test(line)) errors.push(line);
  logs.push(`[${role}] ${line}`);
  if (!line.includes('NETWORK_SAMPLE ') && role !== 'worker') console.log(`[${role}] ${line}`);
}
function launch(args, role) {
  const child = spawn(args[0], args.slice(1), {cwd:root,env:{...process.env,WRANGLER_SEND_METRICS:'false'},stdio:['ignore','pipe','pipe']});
  processes.push(child);
  for(const stream of [child.stdout,child.stderr]) {
    let buffer = '';
    stream.on('data', bytes => {buffer += bytes; let i; while ((i=buffer.indexOf('\n'))>=0) {observe(role,buffer.slice(0,i));buffer=buffer.slice(i+1);} });
  }
  return child;
}
async function until(predicate, title, timeout=60000) {
  const deadline = Date.now()+timeout;
  while (Date.now()<deadline) {
    if(errors.length) throw Error(errors.join('\n'));
    if(await predicate()) return;
    await wait(100);
  }
  throw Error(`${title} timed out; host=${JSON.stringify(latest('host'))}; guest=${JSON.stringify(latest('guest'))}`);
}
function command(role, action) {controls[role] = {id:controls[role].id+1,action};}
let syncs=0, dropped=0;
const output = join(root,'.cache/network-web');
const proxy = createServer(async(req,res)=> {
  try {
    const url = new URL(req.url,'http://localhost');
    let role = url.searchParams.get("role") ?? (url.pathname.startsWith("/guest/") ? "guest" : "host");
    const path = url.pathname.replace(/^\/(host|guest)/,'');
    if(path==='/test/control') {res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(controls[role]));return;}
    if(path.startsWith('/api/')) {
      let body='';for await(const chunk of req)body+=chunk;
      role = tokenRoles.get(JSON.parse(body).token) ?? role;
      const slow = role==='guest' && path.endsWith('/sync');
      if(slow) {
        syncs++;
        await wait(100 + (syncs%3)*50);
        if(syncs===5 || syncs===9) {dropped++;res.writeHead(503,{'Content-Type':'application/json'});res.end('{"error":"Test packet loss"}');return;}
      }
      const response = await fetch(`http://127.0.0.1:${workerPort}${path}`,{method:req.method,headers:{'Content-Type':'application/json'},body});
      const payload=await response.text();
      let reply=payload;
      if(response.ok && (path === "/api/rooms" || path.endsWith("/join"))) {
        const data=JSON.parse(payload);
        tokenRoles.set(data.token,path === "/api/rooms" ? "host" : "guest");
        // Route sockets through this proxy so they share its origin and latency.
        if(data.socket)data.socket=data.socket.replace(/^ws:\/\/[^/]+/,`ws://127.0.0.1:${proxy.address().port}`);
        reply=JSON.stringify(data);
      }
      if(slow)await wait(150);
      res.writeHead(response.status,{'Content-Type':'application/json'});res.end(reply);return;
    }
    if(!web || url.pathname.includes('..')) {res.writeHead(404).end();return;}
    const name=url.pathname==='/' ? 'index.html' : url.pathname.slice(1);
    let bytes=await readFile(join(output,name));
    if(name==='index.html') {
      const args=['--','--smoke-test',`--network-role=${url.searchParams.get('role')??'host'}`,`--room-server=http://127.0.0.1:${proxy.address().port}`,...transportArgs];
      if(url.searchParams.has('room'))args.push(`--network-room=${url.searchParams.get('room')}`);
      bytes=Buffer.from(bytes.toString().replace('RallyDevice.configure(GODOT_CONFIG);',`RallyDevice.configure(GODOT_CONFIG); GODOT_CONFIG.args = ${JSON.stringify(args)}.concat(RallyDevice.isMobile() ? ["--mobile-controls"] : []);`));
    }
    res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'text/javascript','.svg':'image/svg+xml','.png':'image/png'}[extname(name)]??'application/octet-stream'});res.end(bytes);
  } catch(error) {res.writeHead(500).end(String(error));}
});
proxy.on('upgrade',(req,client,head)=> {
  const upstream=tcpConnect(workerPort,'127.0.0.1',()=> {
    const headers=Object.entries(req.headers).map(([k,v])=>`${k}: ${k==='host'?`127.0.0.1:${workerPort}`:k==='origin'?`http://127.0.0.1:${workerPort}`:v}`);
    upstream.write(`${req.method} ${req.url} HTTP/1.1\r\n${headers.join('\r\n')}\r\n\r\n`);
    if(head.length)upstream.write(head);
    const delayed=(from,to)=>from.on('data',chunk=>setTimeout(()=>{if(!to.destroyed)to.write(chunk);},SOCKET_DELAY/2));
    delayed(client,upstream);delayed(upstream,client);
  });
  const close=()=>{client.destroy();upstream.destroy();};
  upstream.on('error',close);client.on('error',close);upstream.on('close',close);client.on('close',close);
});
try {
  if(process.argv.includes('--relay')) {
    const {RoomState}=await import('../server/room-core.mjs');
    const rooms=new Map();
    relay=createServer(async(req,res)=> {
      try {
        if(req.url==='/'){res.end('ready');return;}
        let raw='';for await(const b of req)raw+=b;
        const body=JSON.parse(raw);let reply;
        if(req.url==='/api/rooms') {
          const id=String(rooms.size+1).padStart(6,'0');const room=new RoomState();rooms.set(id,room);
          reply={...room.add(body.name,Date.now(),true,body),room:id};
        } else {
          const [,id,action]=req.url.match(/rooms\/([A-F0-9]{6})\/(join|sync|leave|heartbeat)/);
          const room=rooms.get(id);const now=Date.now();
          reply=action==='join'?room.add(body.name,now,false,body):action==='sync'?room.sync(body,now):action==='heartbeat'?room.heartbeat(body.token,now):room.leave(body.token);
        }
        res.setHeader('Content-Type','application/json');res.end(JSON.stringify(reply??{}));
      }catch(error){res.writeHead(error.status??500,{'Content-Type':'application/json'});res.end(JSON.stringify({error:error.message}));}
    });
    await new Promise(resolve=>relay.listen(workerPort,'127.0.0.1',resolve));
  } else launch([process.execPath,'node_modules/wrangler/bin/wrangler.js','dev','--local','--ip','127.0.0.1','--port',String(workerPort),'--show-interactive-dev-session=false'],'worker');
  await until(async()=>{try{return (await fetch(`http://127.0.0.1:${workerPort}`)).ok;}catch{return false;}},'worker start');
  await new Promise(resolve=>proxy.listen(0,'127.0.0.1',resolve));
  const origin=`http://127.0.0.1:${proxy.address().port}`;
  const godot=await getGodot();
  if(!web)run(godot,["--headless","--editor","--path",join(root,"game"),"--import","--quit"]);
  if(web) {
    const project=join(root,'.cache/export-project');
    const raw=join(root,'.cache/network-raw');
    await mkdir(raw,{recursive:true});await cp(join(root,'dist'),output,{recursive:true});
    await cp(join(root,'game/tests/network_client.gd'),join(project,'scripts/network_client.gd'));
    await writeFile(join(project,'network_client.tscn'),'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/network_client.gd" id="1"]\n[node name="NetworkClient" type="Node"]\nscript = ExtResource("1")\n');
    const config=join(project,'project.godot');const original=await readFile(config,'utf8');
    try {await writeFile(config,original.replace('run/main_scene="res://main.tscn"','run/main_scene="res://network_client.tscn"'));run(godot,['--headless','--path',project,'--export-release','Web',join(raw,'index.html')]);} finally{await writeFile(config,original);}
    await cp(join(raw,'index.pck'),join(output,'index.pck'));
    const {stat}=await import('node:fs/promises');const size=(await stat(join(output,'index.pck'))).size;
    const html=join(output,'index.html');await writeFile(html,(await readFile(html,'utf8')).replace(/"index\.pck":\s*\d+/g,`"index.pck":${size}`));
    const {chromium}=await import('playwright');
    browserFactory=()=>chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  }
  async function client(role,room='') {
    if(web) {
      const browser=await browserFactory();browsers.push(browser);
      const context=await browser.newContext({viewport:{width:844,height:390},...(role==='guest'?{isMobile:true,hasTouch:true}: {})});
      const page=await context.newPage();page.on('console',m=>observe(role,m.text()));page.on('pageerror',e=>errors.push(String(e)));page.on('crash',()=>errors.push(role+' renderer crashed'));
      await page.goto(`${origin}/?role=${role}${room?'&room='+room:''}`,{waitUntil:'domcontentloaded'});
      return page;
    }
    launch([godot,'--headless','--path','game','--max-fps','60','res://tests/network_client.tscn','--','--smoke-test',`--network-role=${role}`,`--room-server=${origin}/${role}`, ...transportArgs, ...(room?[`--network-room=${room}`]:[])],role);
  }
  await client('host');await until(()=>latest('host')?.connected,'host connects',web?120000:60000);
  await client('guest',latest('host').room);await until(()=>latest('guest')?.active,'prediction handshake',web?120000:60000);
  if(socketMode)await until(()=>['host','guest'].every(role=>logs.some(line=>line.startsWith(`[${role}] ROOM_SOCKET open`))),'both clients on WebSocket',web?60000:30000);
  command('host','resume');command('guest','forward');
  const start=latest('guest').pos;
  await until(()=>latest('guest').speed>1 && latest('guest').pending>0,'responsive prediction before acknowledgement',15000);
  await until(()=>Math.hypot(...latest('guest').pos.map((x,i)=>x-start[i]))>3,'driving with 250–350ms RTT',20000);
  command('guest','brake');await until(()=>Math.abs(latest('guest').speed)<0.1,'braking');
  command('guest','pause');
  await until(()=>latest('guest').pending===0 && latest('guest').seq>0 && latest('guest').ack===latest('guest').seq,'all resent inputs acknowledged');
  const authoritative=Object.values(latest('host').driving)[0];
  assert.ok(authoritative,'host owns guest solver');
  assert.ok(Math.hypot(...latest('guest').pos.map((x,i)=>x-authoritative.pos[i]))<0.05,'client converges to host');
  if(!socketMode) {
    await until(()=>dropped===2,'two injected HTTP failures');
    assert.ok(dropped===2,'two real HTTP failures exercised');
  }
  assert.equal(latest('guest').dead,false);
  command('host','pause');await until(()=>latest('guest').world_paused,'host pause replicated');
  const seq=latest('guest').seq;await wait(500);assert.equal(latest('guest').seq,seq,'paused world produces no commands');
  command('host','resume');await until(()=>!latest('guest').world_paused,'host resume replicated');
  command('guest','recover');await until(()=>latest('guest').ack>seq && latest('guest').pending===0,'recovery acknowledged');
  command('guest','exit');await until(()=>!latest('guest').in_car,'exit car');
  command('guest','enter');await until(()=>latest('guest').in_car,'enter car');
  const previousPlayer=latest('guest').player;
  command('guest','rejoin');
  await until(()=>latest('guest')?.player!==previousPlayer && latest('guest')?.active,'fresh session after leave and rejoin',web?120000:60000);
  command('guest','pause');
  await until(()=>latest('guest').pending===0 && !Object.hasOwn(latest('host').driving,previousPlayer),'departed solver removed and fresh input queue acknowledged');
  assert.equal(latest('guest').condition,100);
  assert.equal(errors.length,0);
  if(web)assert.equal(latest("guest").safe_area_ready,true,"mobile Web client reads safe area through browser-local transport");
  if(socketMode)assert.ok(!logs.some(line=>line.includes('ROOM_SOCKET disabled')),'WebSocket stayed in use');
  console.log(`PASS: ${web?'two Chromium clients (mobile guest)':'two Godot clients'}: ${socketMode?'WebSocket with 150ms RTT':'delayed HTTP, 2 lost responses'}, prediction, braking, convergence, pause/resume, recovery, exit/re-entry, leave/rejoin`);
} catch (error) {
  console.error(logs.filter(x => !x.includes('NETWORK_SAMPLE ')).slice(-100).join('\n'));
  if(process.env.GITHUB_ACTIONS) {
    const text=[String(error?.message??error).slice(0,2000),...logs.filter(x=>!x.includes('NETWORK_SAMPLE ')).slice(-30)].join('\n').slice(-6000);
    console.log(`::error title=Multiplayer ${web?'web':'native'}${socketMode?' socket':''}::`+text.replace(/%/g,'%25').replace(/\r/g,'%0D').replace(/\n/g,'%0A'));
  }
  throw error;
} finally {
  await writeFile(join(root,'network-test.log'),logs.join('\n'));
  await Promise.allSettled(browsers.map(browser=>browser.close()));
  for(const child of processes)child.kill('SIGTERM');
  await new Promise(resolve=>proxy.close(resolve));
  if(relay)await new Promise(resolve=>relay.close(resolve));
}
