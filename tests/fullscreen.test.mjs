import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../web/fullscreen.js', import.meta.url), 'utf8');

function setup({ supported = true } = {}) {
  const listeners = new Map();
  const byId = new Map();
  const makeNode = tag => ({
    tagName: tag.toUpperCase(),
    id: '',
    type: '',
    title: '',
    dataset: {},
    attrs: {},
    style: {},
    innerHTML: '',
    children: [],
    setAttribute(name, value) { this.attrs[name] = String(value); },
    addEventListener(name, fn) { this.listeners ??= {}; this.listeners[name] = fn; },
    appendChild(node) { this.children.push(node); if (node.id) byId.set(node.id, node); },
  });

  const head = makeNode('head');
  const body = makeNode('body');
  const root = makeNode('html');
  const document = {
    readyState: 'complete',
    head,
    body,
    documentElement: root,
    fullscreenElement: null,
    webkitFullscreenElement: null,
    getElementById: id => byId.get(id) || null,
    createElement: makeNode,
    addEventListener(name, fn) { listeners.set(name, fn); },
  };

  if (supported) {
    root.requestFullscreen = async () => {
      document.fullscreenElement = root;
      listeners.get('fullscreenchange')?.();
    };
    document.exitFullscreen = async () => {
      document.fullscreenElement = null;
      listeners.get('fullscreenchange')?.();
    };
  }

  const context = { document, console, window: null };
  context.window = context;
  runInNewContext(source, context);
  return { context, document, button: byId.get('rally-fullscreen') };
}

test('fullscreen button is installed and enters/exits fullscreen', async () => {
  const { context, button } = setup();
  assert.ok(button);
  assert.equal(button.attrs['aria-label'], 'На весь экран');
  await button.listeners.click();
  assert.equal(context.RallyFullscreen.isActive(), true);
  assert.equal(button.dataset.fullscreen, 'on');
  assert.equal(button.attrs['aria-label'], 'Выйти из полноэкранного режима');
  await button.listeners.click();
  assert.equal(context.RallyFullscreen.isActive(), false);
  assert.equal(button.dataset.fullscreen, 'off');
});

test('fullscreen button stays visible on browsers without Fullscreen API', async () => {
  const { context, button } = setup({ supported: false });
  assert.ok(button);
  assert.equal(await context.RallyFullscreen.enter(), false);
  await button.listeners.click();
  assert.equal(context.RallyFullscreen.isActive(), false);
});
