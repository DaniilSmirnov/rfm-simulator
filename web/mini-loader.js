/* Stream WASM without buffering another full copy in mobile RAM. */
const RallyMini = {
  async fetch(file) {
    const url = new URL(file, document.baseURI);
    const wasm = url.pathname.endsWith('/index.wasm');
    globalThis.RallyBoot?.setStage(wasm ? 'Загрузка WebAssembly' : 'Загрузка игрового пакета');
    if (wasm) url.pathname += '.gz';
    let response;
    try { response = await fetch(url, {cache:'no-store'}); }
    catch (cause) { throw new Error('Не удалось загрузить ' + url.pathname, {cause}); }
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${url.pathname}`);
    if (!wasm) return response;
    const peek = async stream => {
      const reader = stream.getReader();
      let bytes = new Uint8Array();
      while (bytes.length < 4) {
        const next = await reader.read();
        if (next.done) break;
        const joined = new Uint8Array(bytes.length + next.value.length);
        joined.set(bytes); joined.set(next.value, bytes.length); bytes = joined;
      }
      let first = true;
      return {bytes, stream:new ReadableStream({
        async pull(controller) {
          if (first) { first=false; if(bytes.length) {controller.enqueue(bytes);return;} }
          const next = await reader.read();
          if(next.done) {controller.close();reader.releaseLock();} else controller.enqueue(next.value);
        }, cancel(reason) {return reader.cancel(reason);}
      })};
    };
    if (!response.body) throw new Error('Пустой ответ WebAssembly: ' + url.pathname);
    let data = await peek(response.body);
    if (data.bytes[0] === 0x1f && data.bytes[1] === 0x8b) {
      if (typeof DecompressionStream === 'undefined') throw new Error('Браузер не поддерживает распаковку gzip. Обновите браузер.');
      globalThis.RallyBoot?.setStage('Распаковка WebAssembly');
      try { data = await peek(data.stream.pipeThrough(new DecompressionStream('gzip'))); }
      catch(cause) {throw new Error('Повреждён gzip-файл движка: ' + url.pathname, {cause});}
    }
    if (data.bytes[0] !== 0 || data.bytes[1] !== 97 || data.bytes[2] !== 115 || data.bytes[3] !== 109) {
      await data.stream.cancel();
      throw new Error('Некорректный файл WebAssembly: ' + url.pathname + '. Возможно, сервер вернул HTML вместо движка.');
    }
    const headers = new Headers(response.headers);
    headers.delete('Content-Encoding');
    headers.delete('Content-Length');
    headers.set('Content-Type', 'application/wasm');
    globalThis.RallyBoot?.setStage('Подготовка WebAssembly');
    return new Response(data.stream, {
      status: response.status, statusText: response.statusText, headers,
    });
  },
};
