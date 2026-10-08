// A single declarative contract is consumed by both Godot and the Worker.
import protocol from '../game/data/world_protocol.json' with { type: 'json' };
export const WORLD_PROTOCOL = protocol.version;
export function validateWorld(world, { legacy = true } = {}) {
  const old = world?.world_protocol === undefined;
  if (old && !legacy) return 'world.world_protocol';
  const check = (value, rule, path, depth = 0) => {
    if (depth > 12) return path;
    if (rule.type === 'anyOf') return rule.rules.some(r => check(value, r, path, depth + 1) === '') ? '' : path;
    if (rule.type === 'ref') return check(value, protocol.definitions[rule.name], path, depth + 1);
    if (rule.type === 'nullable') return value === null ? '' : check(value, rule.items, path, depth + 1);
    if (rule.type === 'enum') return rule.values.includes(value) ? '' : path;
    if (rule.type === 'number' || rule.type === 'integer') return typeof value === 'number' && Number.isFinite(value) && (rule.type !== 'integer' || Number.isSafeInteger(value)) && value >= rule.min && value <= rule.max ? '' : path;
    if (rule.type === 'boolean') return typeof value === 'boolean' ? '' : path;
    if (rule.type === 'string') return typeof value === 'string' && value.length <= rule.max ? '' : path;
    if (rule.type === 'array') {
      if (!Array.isArray(value) || value.length > rule.max || value.length < (rule.min ?? 0)) return path;
      for (let i = 0; i < value.length; i++) { const error = check(value[i], rule.items, `${path}[${i}]`, depth + 1); if (error) return error; }
      return '';
    }
    if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length > rule.max) return path;
    if (rule.type === 'object') {
      for (const key of rule.required) if (!old && !Object.hasOwn(value, key)) return `${path}.${key}`;
      for (const [key, item] of Object.entries(value)) {
        if (!Object.hasOwn(rule.fields, key)) { if (!old) return `${path}.${key}`; continue; }
        const error = check(item, rule.fields[key], `${path}.${key}`, depth + 1); if (error) return error;
      }
      return '';
    }
    for (const [key, item] of Object.entries(value)) { if (key.length > 256) return path; const error = check(item, rule.items, `${path}.${key}`, depth + 1); if (error) return error; }
    return '';
  };
  const error = check(world, protocol.definitions.world, 'world');
  if (error) return error;
  if (world.cooking && !world.grill_pose && !world.camp) return 'world.grill_pose';
  if (world.camp_cooking?.fire && !world.camp_cooking.pos) return 'world.camp_cooking.pos';
  if (!old && world.camp_cooking?.pot && world.camp_cooking.pot_pos?.length !== 3) return 'world.camp_cooking.pot_pos';
  return '';
}
