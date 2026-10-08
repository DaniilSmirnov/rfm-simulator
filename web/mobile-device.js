/* Touch laptops with a fine pointer keep the desktop layout; iPads in
 * desktop Safari mode are recognised by their Mac UA plus touch points. */
const RallyDevice = {
  isMobile(nav = navigator, media = window.matchMedia.bind(window)) {
    const ua = nav.userAgent || '';
    return Boolean(nav.userAgentData?.mobile || /Android|iPhone|iPad|iPod/i.test(ua)
      || (/Macintosh/i.test(ua) && nav.maxTouchPoints > 1)
      || (nav.maxTouchPoints > 0 && media('(pointer: coarse)').matches));
  },
  async requestLandscape() {
    try {
      if (!globalThis.RallyViewport?.isVKMobile() && !globalThis.RallyFullscreen?.isActive()) {
        await globalThis.RallyFullscreen?.enter?.();
      }
    } catch { /* The rotate prompt also works without fullscreen permission. */ }
    try {
      await screen.orientation?.lock?.('landscape');
    } catch { /* iOS and some browsers require physically turning the phone. */ }
  },
  installLandscapePrompt() {
    if (document.getElementById('rally-rotate')) return;
    const style = document.createElement('style');
    style.textContent = `
      #rally-rotate { display:none; position:fixed; inset:0; z-index:10000;
        box-sizing:border-box; padding:max(24px, env(safe-area-inset-top)) 24px;
        background:#17242b; color:#f6ead1; font:18px system-ui,sans-serif;
        align-items:center; justify-content:center; flex-direction:column;
        text-align:center; gap:20px; touch-action:none; }
      #rally-rotate .rotate-icon { font-size:64px; color:#dfb270; }
      #rally-rotate p { max-width:340px; margin:0; line-height:1.5; }
      #rally-rotate button { padding:16px 24px; border:2px solid #dfb270;
        border-radius:14px; background:#25352b; color:inherit; font:inherit; }
      @media (orientation:portrait) { #rally-rotate { display:flex; } }
    `;
    document.head.appendChild(style);
    const prompt = document.createElement('div');
    prompt.id = 'rally-rotate';
    prompt.setAttribute('role', 'dialog');
    prompt.setAttribute('aria-label', 'Горизонтальная ориентация');
    prompt.innerHTML = '<span class="rotate-icon" aria-hidden="true">↻ ▭</span><p>Поверните устройство горизонтально</p><p>Движение — слева, обзор камеры — справа.</p><button type="button">На весь экран</button>';
    if (globalThis.RallyViewport?.isVKMobile()) prompt.querySelector('button').remove();
    else prompt.querySelector('button').addEventListener('click', () => { this.landscapeRequest = this.requestLandscape(); });
    document.body.appendChild(prompt);
    // Rotation and browser focus changes must cancel every Godot touch owner.
    const cancel = () => document.getElementById('canvas')?.dispatchEvent(new Event('blur'));
    screen.orientation?.addEventListener?.('change', cancel);
    window.addEventListener('blur', cancel);
  },
  configure(config) {
    config.args.push('--', '--room-server=' + location.origin);
    if (!this.isMobile()) return;
    config.args.push('--mobile-controls');
    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overscrollBehavior = 'none';
    document.getElementById('canvas').style.touchAction = 'none';
    this.installLandscapePrompt();
  },
};
