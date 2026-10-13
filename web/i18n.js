/* Language of the page around the game (loading screen, rotate prompt, ID input).
 * Same rules as game/scripts/loc.gd: VK is Russian, otherwise the choice saved by
 * the in-game language button, otherwise the browser language (Russian or English).
 * Russian text is the key; a missing entry shows the Russian text. */
globalThis.RallyI18n = (() => {
  const english = {
    'Проверка браузера': 'Checking the browser',
    'Загрузка файлов движка': 'Loading the engine files',
    'Загрузка WebAssembly': 'Loading WebAssembly',
    'Загрузка игрового пакета': 'Loading the game package',
    'Распаковка WebAssembly': 'Unpacking WebAssembly',
    'Подготовка WebAssembly': 'Preparing WebAssembly',
    'Подключение к VK': 'Connecting to VK',
    'Запуск движка и загрузка сцены': 'Starting the engine and loading the scene',
    'Запуск сцены': 'Starting the scene',
    'Загрузка игры…': 'Loading the game…',
    'Запуск игры…': 'Starting the game…',
    'Загрузка игры · %s%': 'Loading the game · %s%',
    'Повторить запуск': 'Try again',
    'Технические подробности': 'Technical details',
    'Скопировать отчёт': 'Copy the report',
    'Скопировано': 'Copied',
    'Игра запущена': 'The game has started',
    'Этап': 'Stage',
    'Браузер': 'Browser',
    'Браузер не поддерживает необходимые функции:': 'The browser lacks features the game needs:',
    'Логотип Rally Fans Simulator': 'Rally Fans Simulator logo',
    'Загрузка игры': 'Loading the game',
    'Ваш браузер не поддерживает canvas.': 'Your browser does not support canvas.',
    'Для игры Rally Fans Simulator нужно включить JavaScript.': 'Rally Fans Simulator needs JavaScript.',
    'Не удалось запустить графику. Попробуйте обновить браузер или открыть игру в Chrome/Safari.': "Couldn't start the graphics. Try updating your browser or open the game in Chrome or Safari.",
    'Браузеру не хватило памяти для игры. Закройте лишние вкладки и повторите запуск.': 'The browser ran out of memory for the game. Close other tabs and try again.',
    'Не удалось скачать файлы игры. Проверьте соединение и повторите запуск.': "Couldn't download the game files. Check your connection and try again.",
    'Файлы движка повреждены или несовместимы. Обновите страницу; если ошибка повторяется, сохраните подробности.': 'The engine files are damaged or incompatible. Refresh the page; if the error repeats, save the details.',
    'Движок игры аварийно остановился при запуске. Сохраните технические подробности — они помогут найти причину.': 'The game engine crashed on start. Save the technical details — they help find the cause.',
    'Не удалось запустить игру. Повторите запуск; если ошибка сохраняется, сохраните технические подробности.': "Couldn't start the game. Try again; if the error persists, save the technical details.",
    'Выйти из полноэкранного режима': 'Exit full screen',
    'На весь экран': 'Full screen',
    'Горизонтальная ориентация': 'Landscape orientation',
    'Поверните устройство горизонтально': 'Rotate your device to landscape',
    'Движение — слева, обзор камеры — справа.': 'Move with the left stick, look with the right one.',
    'Ввести ID комнаты': 'Enter the room ID',
    'ID комнаты': 'Room ID',
    'ID комнаты · 6 символов': 'Room ID · 6 characters',
    'Готово': 'Done',
    'Отмена': 'Cancel',
  };
  const key = 'rfm-language';
  const listeners = [];
  const safe = fn => { try { return fn(); } catch { return undefined; } };
  const vk = () => /vk/.test(safe(() => document.querySelector('meta[name="rally-platform"]').content) || '');
  function detect() {
    if (vk()) return 'ru';
    const saved = safe(() => localStorage.getItem(key));
    if (saved === 'ru' || saved === 'en') return saved;
    const system = safe(() => (navigator.languages?.[0] || navigator.language || '')) || '';
    return system ? (/^ru/i.test(system) ? 'ru' : 'en') : 'ru';
  }
  let current = detect();
  return {
    language: () => current,
    t: text => (current === 'en' && english[text]) || text,
    // The game switches the language from its menu and tells the page.
    set(language) {
      if (language !== 'ru' && language !== 'en') return;
      current = language;
      safe(() => localStorage.setItem(key, language));
      safe(() => { document.documentElement.lang = language; });
      listeners.forEach(fn => safe(fn));
    },
    onChange: fn => { listeners.push(fn); },
    // Static markup of the shell: elements carry their Russian text and data-i18n.
    apply(root = document) {
      root.querySelectorAll('[data-i18n]').forEach(node => {
        node.dataset.ru ??= node.textContent;
        node.textContent = this.t(node.dataset.ru);
      });
      for (const [attribute, name] of [['data-i18n-label', 'aria-label'], ['data-i18n-alt', 'alt']]) {
        root.querySelectorAll(`[${attribute}]`).forEach(node => {
          node.dataset.ruAttribute ??= node.getAttribute(name);
          node.setAttribute(name, this.t(node.dataset.ruAttribute));
        });
      }
    },
    keys: () => Object.keys(english),
  };
})();
document.documentElement.lang = globalThis.RallyI18n.language();
globalThis.RallyI18n.apply();
globalThis.RallyI18n.onChange(() => globalThis.RallyI18n.apply());
