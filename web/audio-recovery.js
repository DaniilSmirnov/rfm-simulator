/* Track the engine's real contexts without depending on private Godot exports. */
(() => {
  const contexts = new Set();
  let vkHidden = false, pauseSequence = 0;
  const hidden = () => vkHidden || document.hidden === true;
  const suspend = async () => {
    await Promise.all([...contexts].filter(c => c.state !== 'closed' && c.state !== 'suspended')
      .map(async c => { await c.suspend().catch(() => {}); if (!hidden() && c.state !== 'running' && c.state !== 'closed') await c.resume().catch(() => {}); }));
  };
  const visibilityChanged = async () => {
    if (hidden()) pauseSequence++;
    window.dispatchEvent?.(new Event('rallyvisibilitychange'));
    if (hidden()) await suspend();
    else await resume();
  };
  window.RallyLifecycle = {
    snapshot: () => ({hidden: hidden(), pause_sequence: pauseSequence}),
    attachVK: bridge => bridge.subscribe(event => {
      if (event.detail?.type === 'VKWebAppViewHide') vkHidden = true;
      else if (event.detail?.type === 'VKWebAppViewRestore') vkHidden = false;
      else return;
      visibilityChanged();
    }),
  };
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const Original = globalThis[name];
    if (!Original) continue;
    globalThis[name] = new Proxy(Original, {
      construct(target, args) {
        const context = Reflect.construct(target, args);
        contexts.add(context);
        if (hidden()) void context.suspend().catch(() => {});
        context.addEventListener('statechange', () => {
          if (context.state === 'closed') contexts.delete(context);
        });
        return context;
      },
    });
  }
  const resume = async () => {
    if (hidden()) return;
    await Promise.all([...contexts].filter(c => c.state !== 'running' && c.state !== 'closed')
        .map(async c => { await c.resume().catch(() => {}); if (hidden()) await c.suspend().catch(() => {}); }));
  };
  // A user gesture remains necessary if the browser blocks automatic resume.
  for (const name of ['pointerdown', 'touchend', 'keydown', 'focus', 'pageshow']) {
    window.addEventListener(name, resume, {passive: true});
  }
  document.addEventListener('visibilitychange', visibilityChanged);
})();
