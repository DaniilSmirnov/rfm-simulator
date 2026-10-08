/* Explicitly separate mock artifact; no authentication, purchases or ownership. */
window.RallyPlatform = {
  target:'vk-prototype',
  ready:async () => {},
  getProfile:async () => ({platform:'vk-prototype',nickname:'vk_prototype',verified:false}),
  getEntitlements:async () => ({mode:'unrestricted',skus:[]}),
};
