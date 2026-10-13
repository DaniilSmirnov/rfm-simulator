import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// Every Russian string shown to a player is the key of game/data/translations_en.json.
// This keeps the dictionary complete, free of stale entries and format-safe.
const root = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const cyrillic = /[А-Яа-яЁё]/;
const dictionary = JSON.parse(readFileSync(join(root, 'game/data/translations_en.json'), 'utf8'));

const unescape = text => text.replace(/\\(.)/g, (_, c) => (c === 'n' ? '\n' : c === 't' ? '\t' : c));

// Double-quoted string literals of a GDScript line, comments excluded.
function literals(line) {
  const found = [];
  const pattern = /"((?:[^"\\\n]|\\.)*)"/g;
  let hashAt = -1;
  for (let m; (m = pattern.exec(line));) {
    if (hashAt < 0) {
      const head = line.slice(0, m.index);
      const quotes = (head.match(/"/g) || []).length;
      if (quotes % 2 === 0 && head.includes('#')) break;
    }
    found.push(m[1]);
  }
  return found;
}

function scriptStrings() {
  const used = new Map();
  const dir = join(root, 'game/scripts');
  for (const name of readdirSync(dir).filter(n => n.endsWith('.gd'))) {
    // Block lettering glyph tables and the language module itself are not UI text.
    if (name === 'block_text.gd' || name === 'loc.gd') continue;
    readFileSync(join(dir, name), 'utf8').split('\n').forEach((line, i) => {
      for (const text of literals(line)) {
        if (cyrillic.test(text) && !text.startsWith('[RFM]')) used.set(unescape(text), `${name}:${i + 1}`);
      }
    });
  }
  return used;
}

function dataStrings() {
  const used = new Map();
  const walk = (value, file) => {
    if (typeof value === 'string') { if (cyrillic.test(value)) used.set(value, file); }
    else if (Array.isArray(value)) value.forEach(v => walk(v, file));
    else if (value && typeof value === 'object') {
      for (const [key, v] of Object.entries(value)) if (key !== 'comment') walk(v, file);
    }
  };
  const dir = join(root, 'game/data');
  for (const name of readdirSync(dir).filter(n => n.endsWith('.json') && !n.startsWith('translations'))) {
    walk(JSON.parse(readFileSync(join(dir, name), 'utf8')), `data/${name}`);
  }
  return used;
}

// Messages the room server sends and the client shows as they are.
function serverStrings() {
  const used = new Map();
  const skip = /Платеж|Авториз|имя|VK/;
  for (const name of ['room-core.mjs', 'rate-limits.mjs', 'worker.mjs']) {
    for (const line of readFileSync(join(root, 'server', name), 'utf8').split('\n')) {
      for (const m of line.matchAll(/'((?:[^'\\]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g)) {
        const text = (m[1] ?? m[2]).replace('${MAX_PLAYERS}', '8');
        if (cyrillic.test(text) && !skip.test(text) && text !== 'Фанат') used.set(text, `server/${name}`);
      }
    }
  }
  return used;
}

const placeholders = text => (text.match(/%[-+ 0#]*\d*(?:\.\d+)?[sdif%]/g) || []).sort().join(' ');

test('every Russian string in the game has an English translation', () => {
  const missing = [];
  for (const [text, where] of [...scriptStrings(), ...dataStrings(), ...serverStrings()]) {
    if (!(text in dictionary)) missing.push(`${where}: ${JSON.stringify(text)}`);
  }
  assert.deepEqual(missing, [], 'add these to game/data/translations_en.json:\n' + missing.join('\n'));
});

test('the dictionary has no entries nothing uses', () => {
  const used = new Set([...scriptStrings().keys(), ...dataStrings().keys(), ...serverStrings().keys()]);
  const stale = Object.keys(dictionary).filter(key => !used.has(key));
  assert.deepEqual(stale, [], 'unused translations:\n' + stale.map(s => JSON.stringify(s)).join('\n'));
});

test('translations keep the format placeholders and contain no Russian', () => {
  for (const [ru, en] of Object.entries(dictionary)) {
    assert.equal(typeof en, 'string', JSON.stringify(ru));
    assert.notEqual(en.trim(), '', 'empty translation of ' + JSON.stringify(ru));
    assert.equal(placeholders(en), placeholders(ru), 'placeholders differ: ' + JSON.stringify(ru));
    assert.ok(!cyrillic.test(en), 'Russian left in ' + JSON.stringify(en));
    assert.equal((en.match(/\n/g) || []).length, (ru.match(/\n/g) || []).length, 'line breaks differ: ' + JSON.stringify(ru));
  }
});
