import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {lint, overBudget, functions, codeOf} from '../scripts/lint-gdscript.mjs';

test('GDScript passes the static checks and stays within the budget', () => {
  const {errors, metrics} = lint();
  const budget = JSON.parse(readFileSync(new URL('../scripts/gdscript-budget.json', import.meta.url), 'utf8'));
  assert.deepEqual([...errors, ...overBudget(metrics, budget)], []);
});

test('function lengths ignore trailing comments and members', () => {
  const lines = ['extends Node', 'func a():', '\tpass', '', '# about b', 'var x = 1', 'func b():', '\tpass', '\tpass'];
  assert.deepEqual(functions(lines).map(f => [f.name, f.length]), [['a', 2], ['b', 3]]);
});

test('patterns see code, not strings or comments', () => {
  assert.equal(codeOf('var a = "RegEx" # RegEx'), 'var a = "" ');
});

test('the budget only names existing scripts', () => {
  const budget = JSON.parse(readFileSync(new URL('../scripts/gdscript-budget.json', import.meta.url), 'utf8'));
  const {metrics} = lint();
  for (const file of Object.keys(budget.file_lines)) {
    if (file !== 'default') assert.ok(file in metrics.files, file + ' exists');
  }
});
