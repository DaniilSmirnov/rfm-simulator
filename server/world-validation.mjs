import schema from '../game/data/world_schema.json' with {type:'json'};
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
function bounded(value, budget, depth = 0) {
  if (--budget.left < 0 || depth > 12) return false;
  if (value === null || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER;
  if (typeof value === 'string') return [...value].length <= 4096;
  if (Array.isArray(value)) return value.length <= 20000 && value.every(v=>bounded(v,budget,depth+1));
  return object(value) && Object.keys(value).length <= 2048 && Object.entries(value).every(([k,v])=>[...k].length<=128 && bounded(v,budget,depth+1));
}
function matches(value, shape) {
  if (typeof shape === 'string') {
    if (shape === 'null') return value === null;
    if (shape === 'bool') return typeof value === 'boolean';
    if (shape === 'string') return typeof value === 'string';
    if (shape === 'int') return Number.isSafeInteger(value);
    if (shape === 'number' || shape === 'coordinate') return typeof value === 'number' && Number.isFinite(value) && (shape !== 'coordinate' || Math.abs(value)<100000);
    return matches(value,schema.types[shape]) && (shape!=='world' || usable(value));
  }
  if (Array.isArray(shape)) return Array.isArray(value) && value.length===shape.length && shape.every((s,i)=>matches(value[i],s));
  if (shape.one) return shape.one.some(s=>matches(value,s));
  if (shape.array) return Array.isArray(value) && value.length<=shape.max && value.every(v=>matches(v,shape.array));
  if (!object(value)) return false;
  if (shape.map) return Object.keys(value).length<=shape.max && Object.values(value).every(v=>matches(v,shape.map));
  if (shape.empty && Object.keys(value).length===0) return true;
  return (shape.required??[]).every(k=>Object.hasOwn(value,k)) && Object.entries(shape.fields).every(([k,s])=>!Object.hasOwn(value,k)||matches(value[k],s));
}
function usable(world) {
  if (!object(world) || Object.keys(world).length>96 || !Object.keys(world).every(k=>/^[a-z_]{1,32}$/.test(k))) return false;
  if (world.cooking===true && !world.grill_pose && !world.camp) return false;
  if (world.notice_time>0 && typeof world.notice!=='string') return false;
  const cooking=world.camp_cooking;
  return !cooking?.pot || cooking.pot_pos===undefined || cooking.pot_pos.length===3;
}
export function validWorld(world) {
  return bounded(world,{left:32768}) && matches(world,'world');
}
export function validCold(cold, revisions) {
  if (!object(cold) || !object(revisions)) return false;
  return Object.entries(cold).slice(0,16).every(([section,value])=>
    !/^[a-z_]{1,24}$/.test(section) || !Number.isSafeInteger(revisions[section]) || validWorld(value));
}
