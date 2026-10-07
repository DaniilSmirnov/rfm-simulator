(() => {
  let profile, entitlements, session;
  // Preserve the real network transport, before the browser-local handler wraps it.
  const networkFetch = window.fetch.bind(window);
  const ready = (async () => {
    RallyBoot?.setStage('Подключение к VK');
    await vkBridge.send('VKWebAppInit');
    const response = await networkFetch('/api/vk/session', {
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({launch_params:location.search}),
      signal:AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error('Не удалось подтвердить аккаунт VK. Откройте игру заново через VK или попробуйте позже.');
    const data = await response.json();
    if (!data.profile?.verified || data.profile.platform !== 'vk' || !data.profile.nickname || !data.entitlements || typeof data.session?.token !== 'string' || !Number.isFinite(data.session.expires_at)) {
      throw new Error('Некорректный ответ сервера авторизации VK.');
    }
    profile = data.profile;
    entitlements = data.entitlements;
    session = data.session;
  })();
  ready.catch(() => {});
  window.RallyPlatform = {
    target:'vk',ready:() => ready,
    authorize:async request => {
      await ready;
      if (Date.now() >= session.expires_at * 1000) throw new Error('Сессия VK истекла. Откройте игру заново через VK.');
      const headers = new Headers(request.headers);
      headers.set('Authorization', 'Bearer ' + session.token);
      return new Request(request, {headers});
    },
    getProfile:async () => {await ready;return profile;},
    getEntitlements:async () => {await ready;return entitlements;},
  };
})();
