import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source = await readFile(new URL('../web/mobile-viewport.js', import.meta.url), 'utf8');
function setup({mobile = true, target = 'vk'} = {}) {
  let receive;
  const css = {paddingTop:'0px', paddingRight:'44px', paddingBottom:'21px', paddingLeft:'44px'};
  const context = {innerWidth:844, innerHeight:390, RallyDevice:{isMobile:() => mobile},
    getComputedStyle:() => css, document:{readyState:'complete',
      querySelector:() => ({content:target}), createElement:() => ({style:{}}), body:{appendChild(){}}}};
  context.window = context;
  runInNewContext(source, context);
  context.RallyViewport.attachVK({subscribe:fn => {receive = fn;}});
  return {context, css, send:(type, insets) => receive({detail:{type, data:{insets}}})};
}
test('VK reports only hardware insets without reserving native toolbar space', () => {
  const {context, send} = setup();
  send('VKWebAppUpdateConfig', {top:12, right:20, bottom:34, left:59});
  const rect = context.RallyViewport.snapshot();
  assert.deepEqual(JSON.parse(JSON.stringify(rect)), {width:844,height:390,top:12,right:44,bottom:34,left:59});
});
test('rotation and subsequent Bridge insets replace the old edges', () => {
  const {context, send, css} = setup();
  send('VKWebAppUpdateConfig', {left:59, bottom:34});
  context.innerWidth = 390; context.innerHeight = 844;
  css.paddingLeft = '0px'; css.paddingRight = '0px'; css.paddingTop = '47px';
  send('VKWebAppUpdateInsets', {top:47,left:0,right:0,bottom:21});
  assert.equal(context.RallyViewport.snapshot().left, 0);
  assert.equal(context.RallyViewport.snapshot().top, 47);
});
test('standalone/mobile and VK/desktop do not reserve native toolbar', () => {
  for (const options of [{target:'standalone'}, {mobile:false}]) {
    const {context} = setup(options);
    assert.equal(context.RallyViewport.isVKMobile(), false);
    assert.equal(context.RallyViewport.snapshot().top, 0);
  }
});
test('invalid Bridge edges cannot corrupt UI; visual viewport reserves obscured area', () => {
  const {context, send} = setup();
  send('VKWebAppUpdateInsets', {top:NaN,left:-10,right:'44',bottom:Infinity});
  context.visualViewport = {offsetTop:0,offsetLeft:0,width:844,height:250};
  const rect = context.RallyViewport.snapshot();
  assert.equal(rect.top, 0); assert.equal(rect.bottom, 140);
  assert.equal(rect.left, 44);
});

test('safety memo remains compatible with the mini web engine without JavaScript eval', async () => {
  const [engine, gate] = await Promise.all([
    readFile(new URL('../engine/custom.py', import.meta.url), 'utf8'),
    readFile(new URL('../game/scripts/stage_safety_gate.gd', import.meta.url), 'utf8'),
  ]);
  assert.match(engine, /javascript_eval\s*=\s*False/);
  assert.doesNotMatch(gate, /JavaScriptBridge\s*\./, 'browser data must use the viewport transport supported by our release template');
});
