import {test} from 'node:test';
import assert from 'node:assert/strict';
import {catalog,canUseContent,canUseStage,validateRoomSelection,vkEntitlements} from '../server/store.mjs';
test('catalog has stable unique SKUs; VK has one free stage and three free cars',()=>{
 assert.equal(new Set(catalog.map(p=>p.sku)).size,catalog.length);
 assert.equal(catalog.length,14);
 for(let i=0;i<4;i++) assert.equal(canUseContent('stage',i),i===0);
 for(let i=0;i<10;i++) assert.equal(canUseContent('car',i),i<3);
 assert.ok(catalog.every(p=>p.purchase_enabled === !p.free));
 for(const p of catalog.filter(p=>!p.free)) assert.equal(p.price,p.type==='car'?3:20);
});
test('future verified entitlement grants only the exact known SKU',()=>{
 const rights={mode:'restricted',skus:['car_04','stage_02','unknown']};
 assert.equal(canUseContent('car',3,rights),true);
 assert.equal(canUseContent('car',4,rights),false);
 assert.equal(canUseContent('car',99,rights),false);
 assert.equal(canUseStage(1,rights),true);
});
test('borrowed stage does not grant permanent ownership or a personal car',()=>{
 const rights=vkEntitlements();
 assert.equal(canUseStage(2,rights,true),true);
 assert.equal(canUseStage(2,rights),false);
 assert.deepEqual(rights.skus,[]);
 assert.match(validateRoomSelection({car_model:3},false),/машина/);
 for(const car of [-1,1.5,'0',10]) assert.match(validateRoomSelection({car_model:car},true),/машина/);
});

test('Red Canyon requires its own paid entitlement to host in VK; guests can join',()=>{
 const redCanyon=catalog.find(p=>p.sku==='stage_04');
 assert.deepEqual(
  {type:redCanyon.type,content_id:redCanyon.content_id,free:redCanyon.free,enabled:redCanyon.enabled,purchase_enabled:redCanyon.purchase_enabled,price:redCanyon.price},
  {type:'stage',content_id:3,free:false,enabled:true,purchase_enabled:true,price:20});
 const unpaid=vkEntitlements();
 assert.equal(canUseContent('stage',3,unpaid),false);
 assert.equal(canUseStage(3,unpaid),false);
 assert.match(validateRoomSelection({stage:3,car_model:0},true,unpaid),/спецучасток/);
 assert.equal(validateRoomSelection({stage:3,car_model:0},false,unpaid),null,'guest can borrow the host stage');
 assert.equal(canUseStage(3,unpaid,true),true);
 assert.equal(canUseContent('stage',3,{mode:'restricted',skus:['stage_02']}),false,'winter ownership does not unlock canyon');
 const owner={mode:'restricted',skus:['stage_04']};
 assert.equal(canUseContent('stage',3,owner),true);
 assert.equal(validateRoomSelection({stage:3,car_model:0},true,owner),null);
 assert.equal(canUseContent('stage',1,owner),false);
 assert.equal(canUseContent('stage',2,owner),false);
});
