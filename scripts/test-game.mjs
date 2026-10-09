import {spawnSync} from 'node:child_process';
import {readdir, mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {getGodot, root} from './godot.mjs';
import {groups,nodeSuites,groupDescriptions,slowTests,verifyRegistry} from './test-catalog.mjs';

const project=join(root,'game');
const argv=process.argv.slice(2);
const flag=name=>argv.find(a=>a.startsWith(name+'='))?.split('=')[1];
const shard=flag('--shard')||'all';
const only=flag('--only');
const listOnly=argv.includes('--list');
if (!['all',...Object.keys(groups)].includes(shard)) throw Error('Unknown test shard: '+shard);
const registry=verifyRegistry(await readdir(join(project,'tests')));
if (listOnly){
 console.log(JSON.stringify({registry,description:groupDescriptions,groups,nodeSuites},null,2));
 process.exit(0);
}
if (only && !Object.values(groups).some(files=>files.includes(only))) throw Error('Unknown test: '+only);

const selected=only ? [only] : (shard==='all' ? Object.values(groups).flat() : groups[shard]);
const activeShards=only ? [] : (shard==='all'?Object.keys(groups):[shard]);
const godot=await getGodot();
const results=[];
const execute=(name,command,args,timeoutMs)=>{
 const started=Date.now();
 const result=spawnSync(command,args,{
  cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe'],
  timeout:timeoutMs,maxBuffer:16*1024*1024,env:process.env,
 });
 const elapsedMs=Date.now()-started;
 const pass=!result.error && result.status===0;
 const combined=((result.stdout||'')+'\n'+(result.stderr||'')).trim();
 // Output is required for diagnosing a failed assertion. Successful scripts
 // show their summary without flooding CI with thousands of scene-building logs.
 const tailLines=combined.split('\n');
 const summary=pass ? tailLines.filter(x=>/RESULT|PASS:|# pass |# fail |tests [0-9]|ROOM_ORIGIN/.test(x)).slice(-12)
   : tailLines.slice(-70);
 console.log('\n'+(pass?'PASS':'FAIL')+' ['+name+'] '+(elapsedMs/1000).toFixed(1)+'s'+
  (result.error?' '+result.error.code:'')+(result.signal?' '+result.signal:''));
 if(summary.length)console.log(summary.join('\n').slice(-8000));
 results.push({name,pass,elapsedMs,exitCode:result.status,signal:result.signal||null,
  error:result.error?.message||null});
 return pass;
};

const importOK=execute('Godot editor import',godot,['--headless','--editor','--path',project,'--import'],120_000);
if(!importOK) {
 console.error('Godot import failed; functional tests cannot run reliably');
} else {
 // Tests use baked village assets. Bake them per isolated CI workspace before
 // running independent shards; never mutate an imported project concurrently.
 const bakeOK=execute('Village baked asset preparation',godot,
  ['--headless','--path',project,'--script','res://tools/bake_village.gd'],120_000);
 if(bakeOK){
  for(const group of activeShards)for(const args of nodeSuites[group]){
   const command=process.execPath;
   execute('Node '+group+' '+args.join(' '),command,args.map(a=>
    a.endsWith('.mjs')?join(root,a):a),120_000);
  }
  for(const filename of selected){
   execute('Godot '+filename,godot,
    ['--headless','--path',project,'--script','res://tests/'+filename],
    slowTests.has(filename)?180_000:90_000);
  }
 }
}
const outdir=join(root,'.cache','test-results');
await mkdir(outdir,{recursive:true});
const filename=only?'only-'+only.replace(/\.gd$/,''):shard;
const report={shard,selected: selected.length,registry,generated_at:new Date().toISOString(),results,
 passed:results.filter(t=>t.pass).length,failed:results.filter(t=>!t.pass).length};
await writeFile(join(outdir,filename+'.json'),JSON.stringify(report,null,2)+'\n');
console.log('TEST SHARD '+shard+': '+report.passed+' passed, '+report.failed+' failed. Report: .cache/test-results/'+filename+'.json');
if(report.failed)process.exitCode=1;
