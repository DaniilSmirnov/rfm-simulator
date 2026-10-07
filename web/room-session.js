/* The mini engine has no JS bridge. Observe its same-origin room handshake
 * to keep membership alive while requestAnimationFrame is suspended. */
(() => {
  const originalFetch = window.fetch.bind(window);
  let session = null;
  let heartbeatBusy = false;
  window.fetch = function(input, init) {
    const url = new URL(typeof input === 'string' ? input : input.url, location.href);
    const handshake = url.origin === location.origin && /^\/api\/rooms(?:\/[A-F0-9]{6}\/join)?$/.test(url.pathname);
    const response = originalFetch(input, init);
    if (handshake) response.then(async result => {
      if (!result.ok) return;
      const data = await result.clone().json();
      if (data.token && data.player) session = { token: data.token, room: data.room || url.pathname.split('/')[3] };
    }).catch(() => {});
    if (url.origin === location.origin && url.pathname.endsWith('/leave')) session = null;
    return response;
  };
  setInterval(async () => {
    if (!session || heartbeatBusy) return;
    heartbeatBusy = true;
    const current = session;
    try {
      const response = await window.fetch(`/api/rooms/${current.room}/heartbeat`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: current.token }), keepalive: true,
      });
      if ([401, 404, 410].includes(response.status) && session === current) session = null;
    } catch {} finally { heartbeatBusy = false; }
  }, 5000);
  window.addEventListener('pagehide', event => {
    if (event.persisted || !session) return;
    if (window.RallyPlatform?.target === 'vk') {
      window.fetch(`/api/rooms/${session.room}/leave`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({token:session.token}), keepalive:true}).catch(() => {});
      return;
    }
    navigator.sendBeacon(`/api/rooms/${session.room}/leave`, new Blob([JSON.stringify({ token: session.token })], { type: 'application/json' }));
  });
})();
