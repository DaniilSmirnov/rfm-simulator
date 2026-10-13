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
  // ui_kit.gd owns the brand block (logo, title, byline); the HUD and
  // game.gd use it.
  const game = (await readFile(new URL('../game/scripts/core/game.gd', import.meta.url), 'utf8'))
    + await readFile(new URL('../game/scripts/ui/game_hud.gd', import.meta.url), 'utf8')
    + await readFile(new URL('../game/scripts/ui/ui_kit.gd', import.meta.url), 'utf8');
  assert.match(project, /config\/name="Rally Fans Simulator"/);
  assert.match(shell, /id="status-brand">Rally Fans Simulator<\/h1>/);
  assert.ok((game.match(/Rally Fans Simulator/g) ?? []).length >= 2);
  assert.equal(/СИМУЛЯТОР РАЛЛИЙНОГО ОВОЩА|РАЛЛИЙНЫЙ ОВОЩ/.test(game), false);
});
test('main menu credits Rally Fans Map and links to its site', async () => {
  const kit = await readFile(new URL('../game/scripts/ui/ui_kit.gd', import.meta.url), 'utf8');
  const lobby = await readFile(new URL('../game/scripts/ui/lobby_ui.gd', import.meta.url), 'utf8');
  const hud = await readFile(new URL('../game/scripts/ui/game_hud.gd', import.meta.url), 'utf8');
  assert.match(kit, /BRAND_URL = "https:\/\/rallyfansmap\.ru\/"/);
  assert.match(kit, /Loc\.t\("от %s"\) % BRAND_NAME/);
  assert.match(kit, /LOGO = "res:\/\/branding\/rfm-icon\.svg"/);
  assert.match(lobby, /"О НАС"/);
  assert.doesNotMatch(hud + lobby, /ПЕРЕВАЛ\. РАЛЛИ\. ШАШЛЫК/i);
});

test('players are fans, not vegetables, in every player-facing text', async () => {
  async function visit(directory, found) {
    for (const entry of await readdir(directory,{withFileTypes:true})) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'dist') continue;
      const path = join(directory,entry.name);
      if (entry.isDirectory()) await visit(path, found);
      else if (/\.(gd|js|mjs|md|html|json|cfg|tscn)$/.test(path) && path !== new URL(import.meta.url).pathname
        && /овощ/i.test(await readFile(path,'utf8'))) found.push(path);
    }
    return found;
  }
  const found = [];
  for (const folder of ['game','server','web','scripts','docs']) await visit(new URL('../'+folder,import.meta.url).pathname, found);
  for (const file of ['README.md','package.json']) if (/овощ/i.test(await readFile(new URL('../'+file,import.meta.url),'utf8'))) found.push(file);
  assert.deepEqual(found, []);
  const room = await readFile(new URL('../server/room-core.mjs', import.meta.url), 'utf8');
  assert.match(room, /'Фанат'/);
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
  const props = await readFile(new URL('../game/scripts/core/props.gd', import.meta.url), 'utf8');
  assert.doesNotMatch(props, /BMW|Lada|Hyundai|Kia Rio|Renault|ВАЗ|ТАТНЕФТЬ|Крылов|Ярош|KidneyGrille|var badge\s*=/i);
  // The rally fleet is data: every car is unbranded and carries the club sponsor.
  const fleetText = await readFile(new URL('../game/data/rally_cars.json', import.meta.url), 'utf8');
  const fleet = JSON.parse(fleetText);
  const brands = /BMW|Lada|Hyundai|Kia|Renault|Subaru|Mitsubishi|Lancer|Impreza|Audi|quattro|Lancia|Stratos|Peugeot|Ford|Escort|Volvo|Toyota|Celica|ВАЗ|Жигули|ТАТНЕФТЬ/i;
  assert.doesNotMatch(fleetText, brands);
  assert.ok(fleet.cars.length >= 6);
  assert.equal(fleet.defaults.sponsor, 'Rally Fans Map');
  assert.ok(fleet.cars.every(car => (car.sponsor ?? fleet.defaults.sponsor) === 'Rally Fans Map'));
  const model = await readFile(new URL('../game/scripts/cars/rally_car_model.gd', import.meta.url), 'utf8');
  assert.doesNotMatch(model, brands);
  assert.match(props, /name = "SportGrille"/);
  assert.match(props, /"FANS MAP"/);
  const room = await readFile(new URL('../game/scripts/net/room_lobby.gd', import.meta.url), 'utf8');
  assert.match(room, /"Твой ник"/);
});
