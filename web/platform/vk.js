(() => {
  let profile, entitlements, session, catalog;
  window.RallyViewport?.attachVK(vkBridge);
  // Preserve the real network transport, before the browser-local handler wraps it.
  const networkFetch = window.fetch.bind(window);

  const hasSignedLaunch = raw => {
    const params = new URLSearchParams(raw || '');
    return ['sign', 'vk_user_id', 'vk_app_id', 'vk_ts'].every(name => params.get(name));
  };
  const serializeLaunch = params => {
    const query = new URLSearchParams();
    for (const [name, value] of Object.entries(params || {})) {
      if ((name === 'sign' || name.startsWith('vk_')) && value !== undefined && value !== null) {
        query.set(name, String(value));
      }
    }
    const value = query.toString();
    return value ? '?' + value : '';
  };

  const ready = (async () => {
    RallyBoot?.setStage('Подключение к VK');
    await vkBridge.send('VKWebAppInit');

    let launchParams = location.search;
    if (!hasSignedLaunch(launchParams)) {
      launchParams = serializeLaunch(await vkBridge.send('VKWebAppGetLaunchParams'));
    }

    const response = await networkFetch('/api/vk/session', {
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({launch_params:launchParams}),
      signal:AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      let serverMessage = '';
      try { serverMessage = (await response.json())?.error || ''; } catch {}
      throw new Error(serverMessage || `Не удалось подтвердить аккаунт VK (HTTP ${response.status}). Откройте игру заново через VK или попробуйте позже.`);
    }
    const data = await response.json();
    if (!data.profile?.verified || data.profile.platform !== 'vk' || !data.profile.nickname || !data.entitlements || typeof data.session?.token !== 'string' || !Number.isFinite(data.session.expires_at)) {
      throw new Error('Некорректный ответ сервера авторизации VK.');
    }
    profile = data.profile;
    entitlements = {mode:'restricted',skus:Array.isArray(data.entitlements.skus) ? data.entitlements.skus : []};
    catalog = Array.isArray(data.catalog) ? data.catalog : [];
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
      headers.set('X-Rally-Platform', 'vk');
      return new Request(request, {headers});
    },
    getBootstrap:async () => {await ready;return {profile,entitlements,catalog};},
    getProfile:async () => {await ready;return profile;},
    getEntitlements:async () => {await ready;return entitlements;},
  };
})();
