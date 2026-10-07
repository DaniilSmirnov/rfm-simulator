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
