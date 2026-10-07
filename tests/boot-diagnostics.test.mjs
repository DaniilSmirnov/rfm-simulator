import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {gzipSync} from 'node:zlib';
const wasm = Uint8Array.from([0,97,115,109,1,0,0,0]);
async function loader(body, status=200) {
 const context={URL,Response,Headers,Uint8Array,ReadableStream,DecompressionStream,document:{baseURI:'https://game.test/'},fetch:async()=>new Response(body,{status}),RallyBoot:{setStage(){}}};
 runInNewContext(await readFile(new URL('../web/mini-loader.js',import.meta.url),'utf8')+';globalThis.loader=RallyMini;',context);
 return context.loader;
}
test('WASM loader accepts raw gzip and transparently decoded bytes',async()=>{
 for(const body of [gzipSync(wasm),wasm]) {
  const response=await (await loader(body)).fetch('index.wasm');
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[...wasm]);
  assert.equal(response.headers.get('Content-Type'),'application/wasm');
 }
});
test('loader reports failing asset/status and rejects HTML or damaged gzip',async()=>{
 await assert.rejects((await loader('missing',404)).fetch('index.wasm'),/HTTP 404.*index.wasm.gz/);
 await assert.rejects((await loader('<html>error</html>')).fetch('index.wasm'),/Некорректный файл WebAssembly/);
 await assert.rejects((await loader(Uint8Array.from([31,139,0,0]))).fetch('index.wasm'),/Повреждён gzip/);
});
test('loader detects a signature split into single-byte chunks',async()=>{
 const stream=new ReadableStream({start(c){for(const b of wasm)c.enqueue(Uint8Array.of(b));c.close();}});
 const response=await(await loader(stream)).fetch('index.wasm');
 assert.deepEqual([...new Uint8Array(await response.arrayBuffer())],[...wasm]);
});
test('boot report preserves stage, version and engine errors with bounded history',async()=>{
 const nodes={};
 for(const id of ['status-stage','status-progress','status-label','status-notice','status-details','status-log','status-retry','status-copy','status'])nodes[id]={hidden:false,textContent:'',addEventListener(){},remove(){this.removed=true;}};
 const context={performance:{now:()=>100},navigator:{userAgent:'test-browser'},document:{getElementById:id=>nodes[id]},window:{addEventListener(){}},console:{log(){},error(){}}};
 runInNewContext(await readFile(new URL('../web/boot-diagnostics.js',import.meta.url),'utf8'),context);
 const boot=context.RallyBoot;
 boot.install('test-version');boot.setStage('Запуск сцены');
 for(let i=0;i<100;i++)boot.print('message '+i);
 boot.printError('Godot fatal allocation error');
 boot.fail(new Error('RuntimeError: unreachable'));
 assert.match(nodes['status-notice'].textContent,/аварийно остановился/);
 assert.match(nodes['status-log'].textContent,/test-version.*\nЭтап: Запуск сцены/);
 assert.match(nodes['status-log'].textContent,/Godot fatal allocation error/);
 assert.ok(nodes['status-log'].textContent.split('\n').length<50);
 boot.ready();assert.equal(nodes.status.removed,undefined);
});
