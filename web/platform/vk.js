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
    return roomFromKey(read('request_key')) || roomFromKey(read('vk_request_key')) ||
      roomFromKey(read('requestKey')) || roomFromKey(read('vk_ref'));
  };
  // VK can launch the application from a requestKey or an app URL fragment.
  // The fragment is a room hint only; it is NOT used to authenticate the user.
  const roomFromHash = hash => roomFromKey(decodeURIComponent((hash || '').replace(/^#/, '')));
  let inviteRoom = roomFromLaunch(location.search) || roomFromHash(location.hash);

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
  let inviteDialog = null;
  const inviteFriend = async rawRoom => {
    await ready;
    const id = roomId(rawRoom);
    if (!id) throw new Error('Некорректный ID комнаты.');
    if (typeof document === 'undefined' || !document.body) {
      throw new Error('Окно VK пока недоступно. Повторите попытку.');
    }
    // Godot sends UI actions through asynchronous HTTP. Native VK dialogs can
    // require a browser user gesture, which is lost after the HTTP round trip.
    // Present an actual clickable DOM control and call Bridge from its click.
    if (inviteDialog?.parentNode) inviteDialog.remove();
    const link = 'https://vk.com/app54809523#' + keyForRoom(id);
    const overlay = document.createElement('div');
    inviteDialog = overlay;
    overlay.id = 'rfm-vk-invite-dialog';
    Object.assign(overlay.style, {
      position:'fixed',inset:'0',zIndex:'2147483000',background:'rgba(5,12,16,.78)',
      display:'flex',alignItems:'center',justifyContent:'center',padding:'18px',
      boxSizing:'border-box',fontFamily:'system-ui, sans-serif',color:'#edf3f7',
    });
    const panel = document.createElement('div');
    Object.assign(panel.style, {
      background:'#23342b',border:'1px solid #526657',borderRadius:'18px',
      width:'min(100%, 440px)',maxHeight:'90vh',overflowY:'auto',
      padding:'22px',boxSizing:'border-box',display:'flex',flexDirection:'column',gap:'12px',
      boxShadow:'0 12px 42px rgba(0,0,0,.4)',
    });
    const label = (tag, text, size) => {
      const el = document.createElement(tag);
      el.textContent = text;
      el.style.fontSize = size;
      el.style.margin = '0';
      return el;
    };
    const title = label('h2','Пригласить друзей','22px');
    const hint = label('p','Комната '+id+'. Приглашение откроет другу эту же гонку.','15px');
    const status = label('p','Выбери способ приглашения.','14px');
    status.setAttribute('role','status');
    status.setAttribute('aria-live','polite');
    status.style.color = '#efc78e';
    const urlInput = document.createElement('input');
    urlInput.type = 'text';
    urlInput.readOnly = true;
    urlInput.value = link;
    Object.assign(urlInput.style,{width:'100%',boxSizing:'border-box',padding:'10px',
      color:'#ffffff',background:'#15251f',border:'1px solid #526657',borderRadius:'8px'});
    const button = (text, handler, primary = false) => {
      const el = document.createElement('button');
      el.type = 'button';
      el.textContent = text;
      Object.assign(el.style,{
        padding:'12px',borderRadius:'10px',border:'0',cursor:'pointer',fontSize:'16px',
        background:primary?'#e3b16b':'#38516a',color:primary?'#23342b':'#ffffff',
      });
      el.addEventListener('click',handler);
      return el;
    };
    const vkError = (label, error) => {
      const reason = typeof error?.error_type === 'string' ? error.error_type :
        typeof error?.message === 'string' ? error.message : 'недоступно в этом VK-клиенте';
      status.textContent = label+': '+reason+'. Используй ссылку ниже.';
    };
    const pickFriend = button('Выбрать друга в VK',() => {
      status.textContent = 'Открываем друзей VK…';
      // Directly inside the browser's user gesture, without fetch()/await.
      vkBridge.send('VKWebAppGetFriends',{multi:false}).then(selection => {
        const uid = Number(selection?.users?.[0]?.id);
        if (!Number.isSafeInteger(uid) || uid <= 0) {
          status.textContent = 'Друг не выбран. Можно попробовать снова или отправить ссылку.';
          return;
        }
        status.textContent = 'Подтверди отправку приглашения в VK…';
        return vkBridge.send('VKWebAppShowRequestBox',{
          uid,message:'Заходи смотреть ралли со мной в Rally Fans Simulator!',
          requestKey:keyForRoom(id),
        }).then(result => {
          status.textContent = result?.success === true ?
            'Приглашение отправлено! Друг войдёт в комнату '+id+'.' :
            'Отправка не подтверждена. Попробуй снова или поделись ссылкой.';
        });
      }).catch(error=>vkError('VK не открыл приглашение',error));
    },true);
    const share = button('Поделиться ссылкой через VK',() => {
      status.textContent = 'Открываем отправку ссылки…';
      vkBridge.send('VKWebAppShare',{link}).then(() => {
        status.textContent = 'Проверь отправляемую ссылку: она должна содержать '+id+
          '. Некоторые версии VK игнорируют ссылку — в таком случае скопируй её ниже.';
      }).catch(error=>vkError('VK не открыл отправку ссылки',error));
    });
    const copy = button('Скопировать ссылку на комнату',async()=>{
      try {
        if (navigator?.clipboard?.writeText) {
          await navigator.clipboard.writeText(link);
        } else {
          urlInput.focus();
          urlInput.select();
          if (!document.execCommand?.('copy')) throw new Error('Clipboard unavailable');
        }
        status.textContent = 'Ссылка скопирована. Отправь её другу в сообщении VK.';
      } catch {
        urlInput.focus();
        urlInput.select();
        status.textContent = 'Скопируй выделенную ссылку вручную и отправь другу.';
      }
    });
    const close = button('Закрыть',()=>{overlay.remove(); if(inviteDialog===overlay)inviteDialog=null;});
    panel.append(title,hint,pickFriend,share,urlInput,copy,status,close);
    overlay.append(panel);
    document.body.append(overlay);
    return {status:'opened'};
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
