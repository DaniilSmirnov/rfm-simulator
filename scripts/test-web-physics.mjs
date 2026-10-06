import { createServer } from 'node:http';
import { readFile, writeFile, cp, mkdir, stat } from 'node:fs/promises';
import { join, extname, resolve } from 'node:path';
import { chromium } from 'playwright';
import { getGodot, root, run } from './godot.mjs';

const project = join(root, '.cache/export-project');
const raw = join(root, '.cache/physics-smoke-raw');
const output = join(root, '.cache/physics-smoke');
await mkdir(raw, { recursive: true });
await cp(join(root, 'dist'), output, { recursive: true });
await cp(join(root, 'game/tests/web_physics_scene.gd'), join(project, 'scripts/physics_smoke.gd'));
await writeFile(join(project, 'physics_smoke.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/physics_smoke.gd" id="1"]\n[node name="PhysicsSmoke" type="Node3D"]\nscript = ExtResource("1")\n');
const configPath = join(project, 'project.godot');
const original = await readFile(configPath, 'utf8');
await writeFile(configPath, original.replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://physics_smoke.tscn"'));
try {
  run(await getGodot(), ['--headless', '--path', project, '--export-release', 'Web', join(raw, 'index.html')]);
} finally {
  await writeFile(configPath, original);
}
await cp(join(raw, 'index.pck'), join(output, 'index.pck'));
const size = (await stat(join(output, 'index.pck'))).size;
const htmlPath = join(output, 'index.html');
await writeFile(htmlPath, (await readFile(htmlPath, 'utf8')).replace(/"index\.pck":\s*\d+/g, '"index.pck":' + size));
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    const path = resolve(output, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!path.startsWith(output + '/')) { response.writeHead(403).end(); return; }
    const type = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png', '.svg': 'image/svg+xml' }[extname(path)] ?? 'application/octet-stream';
    response.writeHead(200, { 'Content-Type': type });
    response.end(await readFile(path));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({ headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage();
  let pass = false;
  let fail = '';
  page.on('console', message => {
    const text = message.text();
    if (text.includes('WEB_PHYSICS_PASS')) pass = true;
    if (text.includes('WEB_PHYSICS_FAIL') || text.includes('SCRIPT ERROR') || text.includes('Parse Error')) fail = text;
    console.log('[browser]', text);
  });
  page.on('pageerror', error => { fail = String(error); });
  await page.goto('http://127.0.0.1:' + server.address().port);
  const until = Date.now() + 90000;
  while (!pass && !fail && Date.now() < until) await page.waitForTimeout(250);
  if (fail || !pass) throw new Error(fail || 'Exported Web physics check timed out');
  console.log('WebAssembly 3D physics verified in Chromium.');
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
