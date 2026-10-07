/* Local startup diagnostics. No reports are sent to a server. */
globalThis.RallyBoot = (() => {
  const started = performance.now();
  const logs = [];
  let stage = 'Проверка браузера';
  let failed = false;
  let version = 'unknown';
  let lastPercent = -1;
  const node = id => document.getElementById(id);
  function record(level, message) {
    logs.push(`${((performance.now() - started) / 1000).toFixed(1)}s [${level}] ${String(message).slice(0, 1500)}`);
    if (logs.length > 40) logs.shift();
    console[level === 'error' ? 'error' : 'log']('[RFM startup]', message);
  }
  function setStage(value) {
    if (failed) return;
    stage = value;
    if (node('status-stage')) node('status-stage').textContent = value;
    record('stage', value);
  }
  function classify(detail) {
    if (/WebGL|GPU|context lost/i.test(detail)) return 'Не удалось запустить графику. Попробуйте обновить браузер или открыть игру в Chrome/Safari.';
    if (/memory|out of bounds|allocation|OOM/i.test(detail)) return 'Браузеру не хватило памяти для игры. Закройте лишние вкладки и повторите запуск.';
    if (/HTTP|Failed to fetch|Network|fetch|загрузить/i.test(detail)) return 'Не удалось скачать файлы игры. Проверьте соединение и повторите запуск.';
    if (/gzip|decompress|WebAssembly|CompileError|сборк/i.test(detail)) return 'Файлы движка повреждены или несовместимы. Обновите страницу; если ошибка повторяется, сохраните подробности.';
    if (/unreachable|RuntimeError/i.test(detail)) return 'Движок игры аварийно остановился при запуске. Сохраните технические подробности — они помогут найти причину.';
    return 'Не удалось запустить игру. Повторите запуск; если ошибка сохраняется, сохраните технические подробности.';
  }
  function report() {
    return `Rally Fans Map ${version}\nЭтап: ${stage}\nБраузер: ${navigator.userAgent}\n\n${logs.join('\n')}`;
  }
  function fail(error) {
    if (failed) return;
    const detail = error?.stack || error?.message || String(error);
    record('error', detail);
    failed = true;
    if (node('status-progress')) node('status-progress').hidden = true;
    if (node('status-label')) node('status-label').hidden = true;
    const notice = node('status-notice');
    if (notice) { notice.textContent = classify(detail); notice.hidden = false; }
    if (node('status-details')) node('status-details').hidden = false;
    if (node('status-log')) node('status-log').textContent = report();
    if (node('status-retry')) node('status-retry').hidden = false;
  }
  return {
    setStage, fail, report,
    install(buildVersion) {
      version = buildVersion;
      setStage('Проверка браузера');
      node('status-retry')?.addEventListener('click', () => location.reload());
      node('status-copy')?.addEventListener('click', async () => {
        try { await navigator.clipboard.writeText(report()); node('status-copy').textContent = 'Скопировано'; }
        catch { node('status-log')?.focus(); }
      });
      window.addEventListener('error', event => fail(event.error || event.message));
      window.addEventListener('unhandledrejection', event => fail(event.reason));
    },
    progress(current, total) {
      if (total > 0) {
        const percent = Math.floor(current / total * 100);
        if (percent >= lastPercent + 10 || percent === 100 && lastPercent !== 100) {
          lastPercent = percent; record('download', `${Math.min(100, percent)}% (${current}/${total} байт)`);
        }
        if (percent >= 100) setStage('Запуск движка и загрузка сцены');
      }
    },
    print(...args) { record('engine', args.join(' ')); },
    printError(...args) { record('error', args.join(' ')); },
    ready() { if (!failed) { record('stage', 'Игра запущена'); node('status')?.remove(); } },
  };
})();
