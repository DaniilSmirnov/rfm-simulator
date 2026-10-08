/* CSS pixels only: Godot converts this rectangle to its stretched UI space.
 * VK insets and CSS env describe the same hardware edge, so use max, not sum. */
(() => {
  const edges = ['top', 'right', 'bottom', 'left'];
  let vkInsets = {}, probe;
  const isVKMobile = () => document.querySelector('meta[name="rally-platform"]')?.content === 'vk'
    && RallyDevice.isMobile();
  const number = value => typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : 0;
  const snapshot = () => {
    const width = Math.max(1, window.innerWidth), height = Math.max(1, window.innerHeight);
    const css = probe ? getComputedStyle(probe) : {};
    const inset = Object.fromEntries(edges.map(edge => [edge,
      Math.max(number(vkInsets[edge]), parseFloat(css['padding' + edge[0].toUpperCase() + edge.slice(1)]) || 0)]));
    // Native close/menu buttons are overlays, not part of the hardware insets.
    // Landscape VK uses a vertical close/menu rail at the left edge.
    // Reserve its width for UI, leaving the full height and canvas available.
    if (isVKMobile()) inset.left += 64;
    const visual = window.visualViewport;
    if (visual) {
      inset.left = Math.max(inset.left, visual.offsetLeft);
      inset.top = Math.max(inset.top, visual.offsetTop);
      inset.right = Math.max(inset.right, width - visual.width - visual.offsetLeft);
      inset.bottom = Math.max(inset.bottom, height - visual.height - visual.offsetTop);
    }
    inset.left = Math.min(inset.left, width * .35);
    inset.right = Math.min(inset.right, width * .35);
    inset.top = Math.min(inset.top, height * .4);
    inset.bottom = Math.min(inset.bottom, height * .4);
    return {width, height, ...inset};
  };
  const install = () => {
    if (probe) return;
    probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
    document.body.appendChild(probe);
  };
  const attachVK = bridge => {
    bridge.subscribe(event => {
      if (['VKWebAppUpdateConfig', 'VKWebAppUpdateInsets'].includes(event.detail?.type)
          && event.detail.data?.insets) vkInsets = event.detail.data.insets;
    });
  };
  window.RallyViewport = {snapshot, install, attachVK, isVKMobile};
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install, {once:true});
  else install();
})();
