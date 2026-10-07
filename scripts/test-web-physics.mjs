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
  const mobileContext = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile Safari/604.1' });
  const mobilePage = await mobileContext.newPage();
  await mobilePage.setContent('<meta name="viewport" content="width=device-width,initial-scale=1"><canvas id="canvas"></canvas>');
  await mobilePage.addScriptTag({ content: await readFile(join(root, 'web/mobile-device.js'), 'utf8') });
  const mobileArgs = await mobilePage.evaluate(() => { const config = { args: [] }; RallyDevice.configure(config); RallyDevice.configure({args:[]}); return config.args; });
  if (!mobileArgs.includes('--mobile-controls')) throw new Error('Mobile browser failed to enable controls');
  if (await mobilePage.locator('#rally-rotate').count() !== 1) throw new Error('Orientation prompt duplicated');
  await mobilePage.locator('#rally-rotate').waitFor({ state: 'visible' });
  await mobilePage.setViewportSize({ width: 844, height: 390 });
  await mobilePage.locator('#rally-rotate').waitFor({ state: 'hidden' });
  await mobilePage.setViewportSize({ width: 390, height: 844 });
  await mobilePage.locator('#rally-rotate').waitFor({ state: 'visible' });
  await mobilePage.locator('#rally-rotate button').click();
  await mobilePage.evaluate(() => RallyDevice.landscapeRequest);
  console.log('Mobile portrait prompt, fullscreen fallback and landscape transition verified.');
  await mobileContext.close();
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
  // Hold the engine download to inspect the actual exported loading screen.
  let releaseEngine;
  const engineGate = new Promise(resolve => { releaseEngine = resolve; });
  await page.route('**/index.wasm.gz', async route => { await engineGate; await route.continue(); });
  try {
    await page.goto('http://127.0.0.1:' + server.address().port, { waitUntil: 'domcontentloaded' });
    await page.locator('#status-splash').waitFor({ state: 'visible' });
    await page.waitForFunction(() => {
      const image = document.getElementById('status-splash');
      return image.complete && image.naturalWidth > 0;
    });
    const branded = await page.evaluate(async () => {
      const isBrand = image => {
        const canvas = document.createElement('canvas');
        canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
        const ctx = canvas.getContext('2d'); ctx.drawImage(image, 0, 0);
        const [r, g, b, a] = ctx.getImageData(Math.floor(canvas.width * 0.5), Math.floor(canvas.height * 0.1), 1, 1).data;
        return r > 240 && g > 40 && g < 80 && b < 30 && a === 255;
      };
      const splash = document.getElementById('status-splash');
      const links = [...document.querySelectorAll('link')].filter(link => ['icon', 'apple-touch-icon'].includes(link.rel));
      if (!links.some(link => link.rel === 'icon') || !links.some(link => link.rel === 'apple-touch-icon')) return false;
      for (const link of links) {
        const image = new Image(); image.src = link.href; await image.decode();
        if (!isBrand(image)) return false;
      }
      return isBrand(splash);
    });
    if (!branded) throw new Error('Exported splash/favicon/apple-touch-icon are not Rally Fans Map branded');
    const favicon = page.locator('link[rel="icon"][type="image/svg+xml"]');
    if (await favicon.count() !== 1 || !(await favicon.getAttribute('href')).endsWith('favicon.svg')) throw new Error('Missing canonical SVG favicon');
    const faviconResponse = await page.request.get('http://127.0.0.1:' + server.address().port + '/favicon.svg');
    if ((await faviconResponse.text()) !== await readFile(join(root, 'game/branding/rfm-icon.svg'), 'utf8')) throw new Error('Favicon differs from canonical SVG logo');
    await page.locator('#status-brand').waitFor();
    if (await page.locator('#status-brand').textContent() !== 'Rally Fans Simulator') throw new Error('Loading brand text is incorrect');
    const loadingStyle = await page.evaluate(() => ({
      background: getComputedStyle(document.getElementById('status')).backgroundColor,
      fill: getComputedStyle(document.getElementById('status-fill')).backgroundColor,
    }));
    if (loadingStyle.background !== 'rgb(0, 0, 0)' || loadingStyle.fill !== 'rgb(255, 59, 10)') throw new Error('Loading screen must be black with brand orange progress');
    await page.evaluate(() => loadingProgress(37, 100));
    if (await page.locator('#status-progress').getAttribute('aria-valuenow') !== '37') throw new Error('Loading progress is not determinate');
    if (!(await page.locator('#status-label').textContent()).includes('37%')) throw new Error('Loading percentage label is missing');
    await page.screenshot({ path: join(root, 'branding-loading.png') });
    await page.setViewportSize({width:844,height:390});
    await page.screenshot({path:join(root,'branding-loading-mobile.png')});
    const overflow = await page.evaluate(() => {
      const card = document.querySelector('.loading-card').getBoundingClientRect();
      return card.left < 0 || card.right > innerWidth || card.top < 0 || card.bottom > innerHeight;
    });
    if (overflow) throw new Error('Loading card overflows mobile landscape');
    await page.setViewportSize({width:1280,height:720});
    await page.evaluate(() => loadingProgress(100, 100));
    if (await page.locator('#status-label').textContent() !== 'Запуск игры…') throw new Error('Completed downloads must wait for engine startup');
    await page.evaluate(() => loadingProgress(0, 0));
    if (!(await page.locator('#status-progress').getAttribute('class')).includes('indeterminate')) throw new Error('Unknown total should use indeterminate progress');
    console.log('Rally Fans Map loading screen and browser icons verified.');
  } finally {
    releaseEngine();
  }
  const until = Date.now() + 90000;
  while (!pass && !fail && Date.now() < until) await page.waitForTimeout(250);
  if (fail || !pass) throw new Error(fail || 'Exported Web physics check timed out');
  if (await page.locator('#status').count() !== 0) throw new Error('Loading overlay still covers the started game');
  console.log('WebAssembly 3D physics verified in Chromium.');
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
