import catalog from '../game/data/store_catalog.json' with { type: 'json' };
export { catalog };
export const vkEntitlements = () => ({mode:'restricted', skus:[]});
export function canUseContent(type, id, entitlements = vkEntitlements()) {
  const product = catalog.find(p => p.type === type && p.content_id === id);
  return !!product?.enabled && (product.free || entitlements.skus.includes(product.sku));
}
// Guests borrow the host's stage only within that room; no ownership is granted.
export function canUseStage(id, entitlements, guest = false) {
  return guest && catalog.some(p => p.type === 'stage' && p.content_id === id && p.enabled)
    || canUseContent('stage', id, entitlements);
}
export function validateRoomSelection(body, host, entitlements = vkEntitlements()) {
  const car = body.car_model ?? 0;
  const stage = body.stage ?? 0;
  if (!canUseContent('car', car, entitlements)) return 'Эта машина пока недоступна в VK.';
  if (host && !canUseStage(stage, entitlements)) return 'Этот спецучасток пока недоступен в VK.';
  return null;
}
