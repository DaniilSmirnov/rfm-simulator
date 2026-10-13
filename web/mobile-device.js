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
        background:#131d17; color:#f2e8d0; font:18px system-ui,sans-serif;
        align-items:center; justify-content:center; flex-direction:column;
        text-align:center; gap:20px; touch-action:none; }
      #rally-rotate .rotate-icon { font-size:64px; color:#e3b16b; }
      #rally-rotate p { max-width:340px; margin:0; line-height:1.5; }
      #rally-rotate button { padding:16px 24px; border:2px solid #e3b16b;
        border-radius:14px; background:#2a3c31; color:inherit; font:inherit; }
      @media (orientation:portrait) { #rally-rotate { display:flex; } }
    `;
    document.head.appendChild(style);
    const prompt = document.createElement('div');
    prompt.id = 'rally-rotate';
    prompt.setAttribute('role', 'dialog');
    const t = text => globalThis.RallyI18n ? globalThis.RallyI18n.t(text) : text;
    const label = () => {
      prompt.setAttribute('aria-label', t('Горизонтальная ориентация'));
      const [rotate, controls] = prompt.querySelectorAll('p');
      if (rotate && controls) { rotate.textContent = t('Поверните устройство горизонтально'); controls.textContent = t('Движение — слева, обзор камеры — справа.'); }
      const full = prompt.querySelector('button');
      if (full) full.textContent = t('На весь экран');
    };
    prompt.innerHTML = '<span class="rotate-icon" aria-hidden="true">↻ ▭</span><p></p><p></p><button type="button"></button>';
    label();
    globalThis.RallyI18n?.onChange(label);
    if (globalThis.RallyViewport?.isVKMobile()) prompt.querySelector('button').remove();
    else prompt.querySelector('button').addEventListener('click', () => { this.landscapeRequest = this.requestLandscape(); });
    document.body.appendChild(prompt);
    // Rotation and browser focus changes must cancel every Godot touch owner.
    const cancel = () => document.getElementById('canvas')?.dispatchEvent(new Event('blur'));
    screen.orientation?.addEventListener?.('change', cancel);
    window.addEventListener('blur', cancel);
  },
  // Which GPU the browser draws WebGL with. A blocklisted card or disabled
  // hardware acceleration falls back to a software rasteriser (SwiftShader,
  // llvmpipe…), where the forest runs at ~1 FPS; the game then starts on the
  // cheapest graphics and tells the player.
  probeGpu() {
    try {
      const canvas = document.createElement('canvas');
      const fast = canvas.getContext('webgl2', { failIfMajorPerformanceCaveat: true });
      const gl = fast || document.createElement('canvas').getContext('webgl2');
      if (!gl) return { software: false, renderer: 'нет WebGL2' };
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      const renderer = String(info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER));
      const software = !fast || /swiftshader|llvmpipe|softpipe|software|basic render|microsoft basic/i.test(renderer);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
      return { software, renderer };
    } catch (error) {
      return { software: false, renderer: 'ошибка проверки: ' + error };
    }
  },
  configure(config) {
    config.args.push('--', '--room-server=' + location.origin);
    const gpu = this.probeGpu();
    globalThis.RallyBoot?.note?.(`Видеокарта: ${gpu.renderer}${gpu.software ? ' (программная отрисовка)' : ''}`);
    if (gpu.software) config.args.push('--gpu-software');
    if (!this.isMobile()) return;
    config.args.push('--mobile-controls');
    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overscrollBehavior = 'none';
    document.getElementById('canvas').style.touchAction = 'none';
    this.installLandscapePrompt();
  },
};
