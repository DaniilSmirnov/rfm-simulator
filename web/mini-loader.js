/* MIT. The Godot preloader calls this instead of fetch() for its assets.
 * Gzip is decoded in the browser, without HTTP Content-Encoding headers.
 * Thus the deployed WASM asset itself stays below Cloudflare's size limit.
 */
const RallyMini = {
  async fetch(file) {
    const url = new URL(file, document.baseURI);
    if (!url.pathname.endsWith('/index.wasm')) return fetch(file);
    if (typeof DecompressionStream === 'undefined') {
      throw new Error('Обновите браузер: для mini-сборки нужна поддержка DecompressionStream.');
    }
    url.pathname += '.gz';
    const response = await fetch(url);
    if (!response.ok) return response;
    const headers = new Headers(response.headers);
    headers.delete('Content-Encoding');
    headers.delete('Content-Length');
    headers.set('Content-Type', 'application/wasm');
    return new Response(response.body.pipeThrough(new DecompressionStream('gzip')), {
      status: response.status, statusText: response.statusText, headers,
    });
  },
};
