/* Track the engine's real contexts without depending on private Godot exports. */
(() => {
  const contexts = new Set();
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const Original = globalThis[name];
    if (!Original) continue;
    globalThis[name] = new Proxy(Original, {
      construct(target, args) {
        const context = Reflect.construct(target, args);
        contexts.add(context);
        context.addEventListener('statechange', () => {
          if (context.state === 'closed') contexts.delete(context);
        });
        return context;
      },
    });
  }
  const resume = async () => {
    if (document.hidden) return;
    await Promise.all([...contexts].filter(c => c.state !== 'running' && c.state !== 'closed')
        .map(c => c.resume().catch(() => {})));
  };
  // A user gesture remains necessary if the browser blocks automatic resume.
  for (const name of ['pointerdown', 'touchend', 'keydown', 'focus', 'pageshow']) {
    window.addEventListener(name, resume, {passive: true});
  }
  document.addEventListener('visibilitychange', resume);
})();
