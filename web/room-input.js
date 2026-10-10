/* VK mobile room editor: native input focus stays inside the user's click. */
(() => {
  if (document.querySelector('meta[name="rally-platform"]')?.content !== 'vk') return;
  const style = document.createElement('style');
  style.textContent = `
  #room-input-hit {position:fixed;z-index:25;background:transparent;border:0;padding:0;touch-action:manipulation}
  #room-input-editor {position:fixed;inset:0;z-index:10000;background:#25352b;color:#ffe4a5;box-sizing:border-box;padding:max(20px,env(safe-area-inset-top)) max(24px,env(safe-area-inset-right)) max(20px,env(safe-area-inset-bottom)) max(24px,env(safe-area-inset-left));font:20px system-ui;overflow:auto}
  #room-input-editor input {display:block;box-sizing:border-box;width:100%;margin:20px 0;font:32px system-ui;letter-spacing:.2em;padding:12px;background:#18241d;color:white;border:2px solid #dfb270;border-radius:10px}
  #room-input-editor button {font:20px system-ui;padding:12px 20px;margin-right:12px;border-radius:10px;border:0;background:#dfb270;color:#25352b}
  `;
  document.head.appendChild(style);
  const hit = document.createElement('button');
  hit.id = 'room-input-hit'; hit.type = 'button'; hit.hidden = true;
  hit.setAttribute('aria-label', 'Ввести ID комнаты');
  const editor = document.createElement('form');
  editor.id = 'room-input-editor'; editor.hidden = true;
  editor.setAttribute('role', 'dialog'); editor.setAttribute('aria-modal', 'true');
  editor.setAttribute('aria-label', 'ID комнаты');
  const label = document.createElement('label'); label.textContent = 'ID комнаты · 6 символов';
  const input = document.createElement('input');
  input.type = 'text'; input.maxLength = 6; input.autocomplete = 'off'; input.spellcheck = false;
  input.setAttribute('autocapitalize', 'characters'); input.setAttribute('enterkeyhint', 'done');
  label.appendChild(input); editor.appendChild(label);
  const done = document.createElement('button'); done.type = 'submit'; done.textContent = 'Готово';
  const cancel = document.createElement('button'); cancel.type = 'button'; cancel.textContent = 'Отмена';
  editor.appendChild(done); editor.appendChild(cancel);
  document.body.appendChild(hit); document.body.appendChild(editor);
  let text = '', revision = 0, open = false, rect = null;
  const normalize = value => value.toUpperCase().replace(/[^A-F0-9]/g, '').slice(0, 6);
  const close = () => { open = false; input.blur(); editor.hidden = true; hit.focus({preventScroll:true}); };
  input.addEventListener('input', () => { input.value = normalize(input.value); });
  hit.addEventListener('click', () => {
    input.value = text; editor.hidden = false; open = true;
    input.focus({preventScroll:true}); input.select();
  });
  editor.addEventListener('submit', event => { event.preventDefault(); text = normalize(input.value); revision++; close(); });
  cancel.addEventListener('click', close);
  editor.addEventListener('keydown', event => { if (event.key === 'Escape') { event.preventDefault(); close(); } });
  const layout = () => {
    const canvas = document.getElementById('canvas')?.getBoundingClientRect();
    if (canvas && rect) Object.assign(hit.style, {left:`${canvas.left+rect[0]*canvas.width}px`,top:`${canvas.top+rect[1]*canvas.height}px`,width:`${rect[2]*canvas.width}px`,height:`${rect[3]*canvas.height}px`});
    if (window.visualViewport) editor.style.height = `${window.visualViewport.height}px`;
  };
  window.addEventListener('resize', layout); window.visualViewport?.addEventListener('resize', layout);
  window.RallyRoomInput = {sync(state) {
    hit.hidden = !state.visible;
    if (!state.visible && open) close();
    if (!open && state.revision >= revision) text = normalize(String(state.text || ''));
    if (Array.isArray(state.rect) && state.rect.length === 4 && state.rect.every(Number.isFinite)) rect = state.rect;
    layout();
    return {text, revision};
  }};
})();
