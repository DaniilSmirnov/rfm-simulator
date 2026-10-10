import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source=await readFile(new URL('../web/room-input.js',import.meta.url),'utf8');
function setup(target='vk') {
 const nodes=[];
 const document={activeElement:null,querySelector:()=>({content:target}),getElementById:id=>nodes.find(n=>n.id===id)};
 document.createElement=tag=>{
  const n={tag,style:{},events:{},children:[],value:'',setAttribute(){},appendChild(c){this.children.push(c)},addEventListener(k,fn){this.events[k]=fn},focus(){document.activeElement=this},blur(){document.activeElement=null},select(){},getBoundingClientRect(){return {left:0,top:0,width:844,height:390}}};
  nodes.push(n);return n;
 };
 document.head=document.createElement('head');document.body=document.createElement('body');
 document.createElement('canvas').id='canvas';
 const window={addEventListener(){},visualViewport:{height:390,addEventListener(){}}};
 runInNewContext(source,{window,document});
 return {document,window,nodes,hit:nodes.find(n=>n.id==='room-input-hit'),editor:nodes.find(n=>n.id==='room-input-editor'),input:nodes.find(n=>n.tag==='input')};
}
test('native click synchronously focuses editor and pending commit survives stale engine polls',()=>{
 const {window,document,hit,editor,input}=setup();
 const state={visible:true,text:'',revision:0,rect:[.4,.3,.4,.12]};
 window.RallyRoomInput.sync(state);hit.events.click();
 assert.equal(document.activeElement,input);assert.equal(editor.hidden,false);
 input.value='ab!c123';input.events.input();assert.equal(input.value,'ABC123');
 editor.events.submit({preventDefault(){}});
 assert.equal(editor.hidden,true);
 assert.deepEqual(JSON.parse(JSON.stringify(window.RallyRoomInput.sync(state))),{text:'ABC123',revision:1});
 window.RallyRoomInput.sync({...state,text:'ABC123',revision:1});
 hit.events.click();input.value='DEF456';
 editor.children[2].events.click();
 assert.equal(window.RallyRoomInput.sync({...state,text:'ABC123',revision:1}).text,'ABC123');
 hit.events.click();window.RallyRoomInput.sync({...state,visible:false});
 assert.equal(editor.hidden,true);assert.equal(hit.hidden,true);
});
test('standalone never receives native VK room overlay',()=>{
 const {window,hit}=setup('standalone');assert.equal(window.RallyRoomInput,undefined);assert.equal(hit,undefined);
});
