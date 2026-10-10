#!/usr/bin/env node
// Static checks of the game's GDScript that need no Godot binary.
//
// Hard rules (always zero):
//  - every preload()/load() of a res:// path points at an existing file;
//  - no trailing whitespace, no space-indented statements;
//  - a script starts with `extends`;
//  - no modules the web template disables (RegEx, XMLParser, ZIPReader);
//  - rock and collectible records come from stage_records.gd, detail layers
//    are described with detail_layer.gd (no option strings).
// Budgets (scripts/gdscript-budget.json) only ratchet down: a file, function or
// line may not grow past the budget, and the number of long functions may not
// rise. Lower the budget in the same change that shrinks the code.
//
//   node scripts/lint-gdscript.mjs            check, exit 1 on violations
//   node scripts/lint-gdscript.mjs --report   print the current metrics as JSON
import {readFileSync, readdirSync, existsSync, statSync} from 'node:fs';
import {join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const game = join(root, 'game');

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name.startsWith('.') || name === 'addons') continue;
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, out);
    else if (name.endsWith('.gd')) out.push(path);
  }
  return out;
}

// Strip strings and comments so patterns only see code.
export function codeOf(line) {
  return line.replace(/"(?:\\.|[^"\\])*"/g, '""').replace(/#.*$/, '');
}

// Top-level functions with their body length (trailing blanks and comments excluded).
export function functions(lines) {
  const starts = [];
  lines.forEach((line, i) => { if (/^(static )?func /.test(line)) starts.push(i); });
  return starts.map((start, k) => {
    let end = k + 1 < starts.length ? starts[k + 1] : lines.length;
    while (end - 1 > start && (lines[end - 1].trim() === '' || /^(#|var |const |signal |@)/.test(lines[end - 1]))) end--;
    return {name: lines[start].match(/func ([A-Za-z_0-9]+)/)[1], line: start + 1, length: end - start};
  });
}

export function lint() {
  const errors = [];
  const metrics = {files: {}, longest_function: 0, long_functions: 0, longest_line: 0};
  for (const file of walk(game)) {
    const rel = relative(root, file);
    const text = readFileSync(file, 'utf8');
    const lines = text.split('\n');
    const runtime = rel.startsWith('game/scripts/');
    if (!/^(@tool\s+)?extends /.test(text.replace(/^(#.*\n|\s*\n)*/, ''))) errors.push(`${rel}: script must start with extends`);
    let depth = 0;
    lines.forEach((line, i) => {
      const at = `${rel}:${i + 1}`;
      if (/[ \t]+$/.test(line)) errors.push(`${at}: trailing whitespace`);
      if (depth === 0 && /^ +\S/.test(line)) errors.push(`${at}: indent with tabs`);
      const code = codeOf(line);
      depth = Math.max(0, depth + (code.match(/[[({]/g) || []).length - (code.match(/[\])}]/g) || []).length);
      for (const m of line.matchAll(/\b(?:pre)?load\("(res:\/\/[^"]+)"\)/g)) {
        if (!existsSync(join(game, m[1].slice('res://'.length)))) errors.push(`${at}: missing ${m[1]}`);
      }
      if (/\b(RegEx|XMLParser|ZIPReader)\b/.test(code)) errors.push(`${at}: module disabled in the web template`);
      if (runtime && /\b(rocks|collectibles)\.append\(\{/.test(line)) errors.push(`${at}: make the record with stage_records.gd`);
      if (runtime && /_detail_batch\(|"collectible": true|"tiles": true/.test(line)) errors.push(`${at}: describe detail layers with detail_layer.gd`);
      if (runtime) metrics.longest_line = Math.max(metrics.longest_line, line.length);
    });
    if (!runtime) continue;
    metrics.files[rel] = lines.length;
    for (const f of functions(lines)) {
      metrics.longest_function = Math.max(metrics.longest_function, f.length);
      if (f.length > 60) metrics.long_functions++;
    }
  }
  return {errors, metrics};
}

export function overBudget(metrics, budget) {
  const errors = [];
  for (const [file, length] of Object.entries(metrics.files)) {
    const limit = budget.file_lines[file] ?? budget.file_lines.default;
    if (length > limit) errors.push(`${file}: ${length} lines, budget ${limit}`);
  }
  for (const key of ['longest_function', 'long_functions', 'longest_line']) {
    if (metrics[key] > budget[key]) errors.push(`${key}: ${metrics[key]}, budget ${budget[key]}`);
  }
  return errors;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const {errors, metrics} = lint();
  if (process.argv.includes('--report')) {
    console.log(JSON.stringify(metrics, null, 1));
    process.exit(0);
  }
  const budget = JSON.parse(readFileSync(join(root, 'scripts/gdscript-budget.json'), 'utf8'));
  errors.push(...overBudget(metrics, budget));
  for (const e of errors) console.error(e);
  console.log(errors.length ? `GDSCRIPT LINT: ${errors.length} problems` : 'GDSCRIPT LINT: ok');
  process.exit(errors.length ? 1 : 0);
}
