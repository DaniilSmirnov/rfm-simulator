(() => {
  let profile, entitlements, session, catalog, purchasing = false, orderOpen = false;
  window.RallyViewport?.attachVK(vkBridge);
  // RequestBox, unlike InviteBox, carries a per-invitation requestKey.
  // The key is only a room locator; authorization and room capacity are still
  // enforced by the normal signed VK session and /api/rooms/:id/join endpoint.
  const roomId = value => typeof value === 'string' && /^[A-F0-9]{6}$/i.test(value) ? value.toUpperCase() : '';
  const keyForRoom = id => 'rfm_room_' + id;
  const roomFromKey = value => {
    const match = typeof value === 'string' && /^rfm_room_([A-F0-9]{6})$/i.exec(value);
    return match ? roomId(match[1]) : '';
  };
  const roomFromLaunch = raw => {
    const query = typeof raw === 'string' ? new URLSearchParams(raw) : raw || {};
    const read = key => query instanceof URLSearchParams ? query.get(key) : query[key];
    return roomFromKey(read('request_key')) || roomFromKey(read('vk_request_key')) || roomFromKey(read('requestKey'));
  };
  let inviteRoom = roomFromLaunch(location.search);

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
      const launch = await vkBridge.send('VKWebAppGetLaunchParams');
      inviteRoom ||= roomFromLaunch(launch);
      launchParams = serializeLaunch(launch);
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
  const updateStore = data => {
    if (!data.entitlements || !Array.isArray(data.entitlements.skus) || !Array.isArray(data.catalog)) throw new Error('Некорректные права покупки.');
    entitlements = {mode:'restricted',skus:data.entitlements.skus};
    catalog = data.catalog;
    return {profile,entitlements,catalog};
  };
  const storeRequest = async (path, body = {}) => {
    const request = await window.RallyPlatform.authorize(new Request(new URL(path,location.href), {
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000),
    }));
    const response = await networkFetch(request);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Не удалось проверить покупку.');
    return data;
  };
  const refreshStore = async () => updateStore(await storeRequest('/api/vk/store'));
  const buy = async sku => {
    if (purchasing || orderOpen) throw new Error('Покупка уже выполняется.');
    if (typeof sku !== 'string' || !catalog?.some(p => p.sku === sku && p.purchase_enabled)) throw new Error('Товар недоступен.');
    purchasing = true;
    try {
      const prepared = await storeRequest('/api/vk/payments/prepare',{sku});
      updateStore(prepared);
      if (prepared.owned) return {...await refreshStore(),status:'owned',purchased_sku:sku};
      let outcome = 'pending', timer;
      try {
        orderOpen = true;
        const order = Promise.resolve().then(() => vkBridge.send('VKWebAppShowOrderBox',{type:'item',item:prepared.item})).finally(() => {orderOpen = false;});
        const result = await Promise.race([
          order,
          new Promise((_,reject) => {timer = setTimeout(() => reject(new Error('Order timeout')),25000);}),
        ]);
        outcome = result?.status === 'cancel' ? 'cancel' : result?.status === 'success' ? 'pending' : 'fail';
      } catch { outcome = 'pending'; }
      finally { clearTimeout(timer); }
      // Bridge is only presentation. Signed callbacks are the source of ownership,
      // including when a mobile client reports an error after a completed order.
      for (let attempt = 0; attempt < 4; attempt++) {
        const store = await refreshStore();
        if (store.entitlements.skus.includes(sku)) return {...store,status:'owned',purchased_sku:sku};
        if (outcome === 'cancel' || outcome === 'fail') return {...store,status:outcome};
        if (attempt < 3) await new Promise(resolve => setTimeout(resolve,1000));
      }
      return {profile,entitlements,catalog,status:'pending'};
    } finally { purchasing = false; }
  };
  const inviteFriend = async rawRoom => {
    await ready;
    const id = roomId(rawRoom);
    if (!id) throw new Error('Некорректный ID комнаты.');
    // The user explicitly chooses one VK friend; do not send bulk/spam requests.
    const selection = await vkBridge.send('VKWebAppGetFriends', {multi:false});
    const uid = Number(selection?.users?.[0]?.id);
    if (!Number.isSafeInteger(uid) || uid <= 0) return {status:'cancel'};
    const request = await vkBridge.send('VKWebAppShowRequestBox', {
      uid, message:'Заходи смотреть ралли со мной в Rally Fans Simulator!',
      requestKey:keyForRoom(id),
    });
    return {status:request?.success === true ? 'sent' : 'cancel'};
  };
  window.RallyPlatform = {
    target:'vk',ready:() => ready, buy, refreshStore, inviteFriend,
    authorize:async request => {
      await ready;
      if (Date.now() >= session.expires_at * 1000) throw new Error('Сессия VK истекла. Откройте игру заново через VK.');
      const headers = new Headers(request.headers);
      headers.set('Authorization', 'Bearer ' + session.token);
      headers.set('X-Rally-Platform', 'vk');
      return new Request(request, {headers});
    },
    getBootstrap:async () => {await ready;return {profile,entitlements,catalog,invite_room:inviteRoom};},
    getProfile:async () => {await ready;return profile;},
    getEntitlements:async () => {await ready;return entitlements;},
  };
})();
