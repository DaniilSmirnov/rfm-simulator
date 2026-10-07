(() => {
  let profile, entitlements;
  // Preserve the real network transport, before the browser-local handler wraps it.
  const networkFetch = window.fetch.bind(window);
  const ready = (async () => {
    RallyBoot?.setStage('Подключение к VK');
    await vkBridge.send('VKWebAppInit');
    const response = await networkFetch('/api/vk/session', {
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({launch_params:location.search}),
    });
    if (!response.ok) throw new Error('Не удалось подтвердить аккаунт VK. Сервер авторизации ещё не подключён или отклонил запуск.');
    const data = await response.json();
    if (!data.profile?.verified || data.profile.platform !== 'vk' || !data.profile.nickname || !data.entitlements) {
      throw new Error('Некорректный ответ сервера авторизации VK.');
    }
    profile = data.profile;
    entitlements = data.entitlements;
  })();
  ready.catch(() => {});
  window.RallyPlatform = {
    target:'vk',ready:() => ready,
    getProfile:async () => {await ready;return profile;},
    getEntitlements:async () => {await ready;return entitlements;},
  };
})();
