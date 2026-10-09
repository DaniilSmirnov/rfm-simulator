import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
test('browser resumes the same engine context after tab return and touch, without recreating it', async () => {
  const events = new Map();
  const visibility = new Map();
  let creations = 0;
  class Context {
    constructor() { this.state = 'suspended'; this.resumes = 0; creations++; }
    addEventListener() {}
    async resume() { this.resumes++; this.state = 'running'; }
    async suspend() { this.state = 'suspended'; }
  }
  const document = {hidden:false, addEventListener:(name, fn) => visibility.set(name, fn)};
  const sandbox = {AudioContext:Context, document, window:{addEventListener:(name,fn)=>events.set(name,fn)}};
  runInNewContext(readFileSync(new URL('../web/audio-recovery.js',import.meta.url),'utf8'),sandbox);
  const ctx = new sandbox.AudioContext();
  assert.ok(ctx instanceof Context);
  await events.get('pointerdown')();
  assert.equal(ctx.resumes,1);
  ctx.state = 'interrupted';
  document.hidden = true;
  await visibility.get('visibilitychange')();
  assert.equal(ctx.resumes,1);
  document.hidden = false;
  await visibility.get('visibilitychange')();
  assert.equal(ctx.resumes,2);
  ctx.state = 'suspended';
  ctx.resume = async () => {ctx.resumes++; throw new Error('Gesture needed');};
  await events.get('focus')();
  await events.get('touchend')();
  assert.equal(ctx.resumes,4);
  ctx.state = 'closed';
  await events.get('pageshow')();
  assert.equal(ctx.resumes,4);
  assert.equal(creations,1);
});

test('VK hide suspends audio even with a visible document and retains pause through rapid restore', async () => {
  let receive;
  const events = new Map();
  class Context {
    constructor() { this.state = 'running'; }
    addEventListener() {}
    async suspend() { this.state = 'suspended'; }
    async resume() { this.state = 'running'; }
  }
  const sandbox = {AudioContext:Context, document:{hidden:false,addEventListener(){}},
    window:{addEventListener:(name,fn)=>events.set(name,fn)}};
  runInNewContext(readFileSync(new URL('../web/audio-recovery.js',import.meta.url),'utf8'),sandbox);
  sandbox.window.RallyLifecycle.attachVK({subscribe:fn=>{receive=fn;}});
  const ctx = new sandbox.AudioContext();
  receive({detail:{type:'VKWebAppViewHide'}});
  assert.equal(ctx.state,'suspended');
  assert.equal(sandbox.window.RallyLifecycle.snapshot().hidden,true);
  await events.get('focus')();
  assert.equal(ctx.state,'suspended');
  receive({detail:{type:'VKWebAppViewRestore'}});
  await events.get('touchend')();
  assert.equal(ctx.state,'running');
  assert.equal(sandbox.window.RallyLifecycle.snapshot().pause_sequence,1);
  receive({detail:{type:'VKWebAppViewHide'}});
  const newContext = new sandbox.AudioContext();
  assert.equal(newContext.state,'suspended');
  assert.equal(sandbox.window.RallyLifecycle.snapshot().pause_sequence,2);
});
