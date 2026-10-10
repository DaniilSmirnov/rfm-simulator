import playwright from 'playwright';
const {chromium} = playwright;
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const source = await readFile(new URL('../web/room-input.js', import.meta.url), 'utf8');
const browser = await chromium.launch({headless:true});
try {
 for (const viewport of [{width:844,height:390},{width:390,height:844}]) {
  const page = await browser.newPage({viewport,isMobile:true,hasTouch:true});
  await page.setContent('<meta name="rally-platform" content="vk"><canvas id="canvas" style="position:fixed;inset:0;width:100%;height:100%"></canvas>');
  await page.addScriptTag({content:source});
  const sync = state => page.evaluate(state => RallyRoomInput.sync(state),state);
  const state = {visible:true,text:'',revision:0,rect:[.4,.3,.4,.12]};
  await sync(state);
  await page.locator('#room-input-hit').tap();
  assert.equal(await page.locator('input').evaluate(el=>el===document.activeElement),true);
  await page.locator('input').fill('abc123');
  await page.locator('input').press('Enter');
  assert.deepEqual(await sync(state),{text:'ABC123',revision:1});
  assert.deepEqual(await sync({...state,text:'ABC123',revision:1}),{text:'ABC123',revision:1});
  await page.locator('#room-input-hit').tap();
  await page.locator('input').fill('DEF456');
  await page.getByText('Отмена',{exact:true}).tap();
  assert.deepEqual(await sync({...state,text:'ABC123',revision:1}),{text:'ABC123',revision:1});
  await page.locator('#room-input-hit').tap();
  await sync({...state,visible:false});
  assert.equal(await page.locator('#room-input-editor').isVisible(),false);
  assert.equal(await page.locator('#room-input-hit').isVisible(),false);
  await page.close();
 }
 const page=await browser.newPage();
 await page.setContent('<meta name="rally-platform" content="standalone">');
 await page.addScriptTag({content:source});
 assert.equal(await page.locator('#room-input-hit').count(),0);
 console.log('Room editor: focus, commit, acknowledgement, cancel, hide, standalone passed');
} finally {await browser.close();}
