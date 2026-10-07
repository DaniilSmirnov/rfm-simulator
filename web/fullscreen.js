(() => {
  const id = 'rally-fullscreen';

  const fullscreenElement = () =>
    document.fullscreenElement || document.webkitFullscreenElement || null;

  const request = async () => {
    const root = document.documentElement;
    const method = root.requestFullscreen || root.webkitRequestFullscreen;
    if (!method) return false;
    await method.call(root);
    return true;
  };

  const exit = async () => {
    const method = document.exitFullscreen || document.webkitExitFullscreen;
    if (!method) return false;
    await method.call(document);
    return true;
  };

  const updateButton = button => {
    const active = Boolean(fullscreenElement());
    button.dataset.fullscreen = active ? 'on' : 'off';
    button.setAttribute('aria-label', active ? 'Выйти из полноэкранного режима' : 'На весь экран');
    button.title = active ? 'Выйти из полноэкранного режима' : 'На весь экран';
    button.innerHTML = active
      ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3v6H3M15 3v6h6M9 21v-6H3M15 21v-6h6"/></svg>'
      : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9V3h6M21 9V3h-6M3 15v6h6M21 15v6h-6"/></svg>';
  };

  const toggle = async () => {
    if (fullscreenElement()) return exit();
    return request();
  };

  const install = () => {
    if (document.getElementById(id)) return document.getElementById(id);

    const style = document.createElement('style');
    style.textContent = `
      #${id} {
        position: fixed;
        top: max(12px, env(safe-area-inset-top));
        right: max(12px, env(safe-area-inset-right));
        z-index: 9998;
        width: 44px;
        height: 44px;
        padding: 0;
        display: grid;
        place-items: center;
        border: 1px solid rgba(246, 234, 209, .38);
        border-radius: 12px;
        background: rgba(23, 36, 43, .82);
        color: #f6ead1;
        box-shadow: 0 4px 18px rgba(0, 0, 0, .24);
        -webkit-backdrop-filter: blur(8px);
        backdrop-filter: blur(8px);
        cursor: pointer;
        touch-action: manipulation;
        -webkit-tap-highlight-color: transparent;
      }
      #${id}:hover { background: rgba(37, 53, 43, .94); }
      #${id}:active { transform: scale(.96); }
      #${id}:focus-visible { outline: 2px solid #dfb270; outline-offset: 2px; }
      #${id} svg {
        width: 24px;
        height: 24px;
        fill: none;
        stroke: currentColor;
        stroke-width: 2;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      @media (max-width: 640px) {
        #${id} {
          top: max(8px, env(safe-area-inset-top));
          right: max(8px, env(safe-area-inset-right));
          width: 42px;
          height: 42px;
        }
      }
    `;
    document.head.appendChild(style);

    const button = document.createElement('button');
    button.id = id;
    button.type = 'button';
    updateButton(button);
    button.addEventListener('click', async () => {
      try {
        await toggle();
      } catch (error) {
        console.warn('[RFM Fullscreen] request failed', error);
      } finally {
        updateButton(button);
      }
    });
    document.body.appendChild(button);

    const update = () => updateButton(button);
    document.addEventListener('fullscreenchange', update);
    document.addEventListener('webkitfullscreenchange', update);
    return button;
  };

  window.RallyFullscreen = {
    isActive: () => Boolean(fullscreenElement()),
    enter: request,
    exit,
    toggle,
    install,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install, { once: true });
  } else {
    install();
  }
})();
