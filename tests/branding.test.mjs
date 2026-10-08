import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { join } from 'node:path';

test('loading progress is real, bounded, supports unknown sizes and waits for startup', async () => {
  const html = await readFile(new URL('../game/branding/web-shell.html', import.meta.url), 'utf8');
  const nodes = {};
  for (const id of ['status','status-progress','status-fill','status-label','status-notice']) nodes[id] = {
    style: {}, attrs: {}, hidden: false, textContent: '', removed: false,
    classList: { values: new Set(['indeterminate']), add(v) {this.values.add(v)}, remove(v) {this.values.delete(v)} },
    setAttribute(k,v) {this.attrs[k]=String(v)}, removeAttribute(k) {delete this.attrs[k]},
    remove() {this.removed=true}
  };
  let options, ready;
  const inline = html.split('<script>')[1].split('</script>')[0].replace('$GODOT_CONFIG','{}').replace('$GODOT_THREADS_ENABLED','false');
  class Engine {
    static getMissingFeatures() {return []}
    startGame(value) {options=value; return new Promise(resolve => {ready=resolve})}
  }
  runInNewContext(inline, {Engine, document:{getElementById:id=>nodes[id]}, console});
  assert.equal(nodes.status.removed,false);
  options.onProgress(25,100);
  assert.equal(nodes['status-progress'].attrs['aria-valuenow'],'25');
  assert.equal(nodes['status-fill'].style.width,'25%');
  options.onProgress(200,100);
  assert.equal(nodes['status-fill'].style.width,'100%');
  assert.equal(nodes['status-label'].textContent,'Запуск игры…');
  assert.equal(nodes.status.removed,false);
  options.onProgress(0,0);
  assert.equal(nodes['status-progress'].attrs['aria-valuenow'],undefined);
  assert.ok(nodes['status-progress'].classList.values.has('indeterminate'));
  ready();
  await Promise.resolve();
  assert.equal(nodes.status.removed,true);
});
test('game title is Rally Fans Simulator everywhere it is presented', async () => {
  const project = await readFile(new URL('../game/project.godot', import.meta.url), 'utf8');
  const shell = await readFile(new URL('../game/branding/web-shell.html', import.meta.url), 'utf8');
  const game = await readFile(new URL('../game/scripts/game.gd', import.meta.url), 'utf8') + await readFile(new URL('../game/scripts/game_ui.gd', import.meta.url), 'utf8');
  assert.match(project, /config\/name="Rally Fans Simulator"/);
  assert.match(shell, /id="status-brand">Rally Fans Simulator<\/h1>/);
  assert.ok((game.match(/Rally Fans Simulator/g) ?? []).length >= 2);
  assert.equal(/СИМУЛЯТОР РАЛЛИЙНОГО ОВОЩА|РАЛЛИЙНЫЙ ОВОЩ/.test(game), false);
});
test('all project brand references use Rally Fans Map spelling', async () => {
  async function visit(directory) {
    for (const entry of await readdir(directory,{withFileTypes:true})) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'dist') continue;
      const path = join(directory,entry.name);
      if (entry.isDirectory()) await visit(path);
      else if (/\.(gd|js|mjs|md|html|svg|json|godot|cfg)$/.test(path) && path !== new URL(import.meta.url).pathname) {
        const text=await readFile(path,'utf8');
        assert.equal(/Rally Fans Maps|Rally Fan Maps|RallyFanMaps|rally_fan_maps|FANS MAPS|FAN MAPS/.test(text),false,path);
      }
    }
  }
  for(const folder of ['game','scripts','web','docs']) await visit(new URL('../'+folder,import.meta.url).pathname);
  assert.equal(/Rally Fan Maps|FAN MAPS/.test(await readFile(new URL('../README.md',import.meta.url),'utf8')),false);
});

test('authored game content has no third-party vehicle brands or named crews', async () => {
  const props = await readFile(new URL('../game/scripts/props.gd', import.meta.url), 'utf8');
  assert.doesNotMatch(props, /BMW|Lada|Hyundai|Kia Rio|Renault|ВАЗ|ТАТНЕФТЬ|Крылов|Ярош|KidneyGrille|var badge\s*=/i);
  const rallyModels = props.split('const RALLY_MODELS = [')[1].split('\n]')[0];
  const sponsors = [...rallyModels.matchAll(/"sponsor": "([^"]+)"/g)].map(match => match[1]);
  assert.equal(sponsors.length, 6);
  assert.ok(sponsors.every(sponsor => sponsor === 'Rally Fans Map'));
  assert.match(props, /name = "SportGrille"/);
  assert.match(props, /"FANS MAP"/);
  const room = await readFile(new URL('../game/scripts/room_ui.gd', import.meta.url), 'utf8');
  assert.match(room, /placeholder_text = "Твой ник"/);
});
