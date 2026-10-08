/* Browser-local JSON transport for the minimal engine, which has no JS bridge. */
(() => {
  const networkFetch = window.fetch.bind(window);
  const origin = location.origin;
  window.fetch = async function(input, init) {
    const request = new Request(input instanceof Request ? input : new URL(input, location.href), init);
    const url = new URL(request.url);
    if (url.origin === origin && /^\/api\/rooms(?:\/|$)/.test(url.pathname) && RallyPlatform.target === 'vk') {
      let authorized;
      try { authorized = await RallyPlatform.authorize(request); }
      catch { return Response.json({error:'Сессия VK истекла. Откройте игру заново через VK.'}, {status:401}); }
      return networkFetch(authorized);
    }
    if (url.origin !== origin || url.pathname !== '/__rally_platform') return networkFetch(input, init);
    if (request.method !== 'POST') return Response.json({error:'POST required'}, {status:405});
    try {
      const raw = await request.text();
      if (raw.length > 4096) return Response.json({error:'Message too large'}, {status:413});
      const {method} = JSON.parse(raw);
      const methods = {getBootstrap: async () => RallyPlatform.getBootstrap ? RallyPlatform.getBootstrap() : {profile:await RallyPlatform.getProfile(), entitlements:await RallyPlatform.getEntitlements(),catalog:[]}, getProfile: () => RallyPlatform.getProfile(), getEntitlements: () => RallyPlatform.getEntitlements()};
      if (!Object.hasOwn(methods, method)) return Response.json({error:'Unknown platform method'}, {status:400});
      await RallyPlatform.ready();
      return Response.json({result:await methods[method]()});
    } catch { return Response.json({error:'Platform request failed'}, {status:503}); }
  };
})();
