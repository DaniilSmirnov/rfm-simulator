import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
for(const [directory,adapter] of [['dist','standalone'],['dist-vk','vk'],['dist-vk-prototype','vk-prototype']]){
 const files=await readdir(directory,{recursive:true});
 const html=await readFile(directory+'/index.html','utf8');
 const pack=await readFile(directory+'/index.pck');
 assert.ok(pack.includes(Buffer.from('platform_probe')),directory+' is missing the exported platform probe scene');
 assert.deepEqual(files.filter(name=>name.startsWith('platform/')).sort(),['platform/'+adapter+'.js','platform/transport.js'].sort());
 assert.equal(files.includes('vk-bridge.js'),adapter==='vk');
 assert.ok(html.includes('src="platform/'+adapter+'.js"'));
 assert.equal(html.includes('src="vk-bridge.js"'),adapter==='vk');
 assert.ok(html.includes('RallyPlatform.ready()'));
 assert.ok(html.indexOf('platform/transport.js')<html.indexOf('src="index.js"'));
 console.log('BUILD_ISOLATION_PASS',directory);
}
