# VK platform transport prototype

This is a technical prototype, not a completed VK integration. No account authentication, permanent entitlements, purchase flow or achievements are implemented.

## Build targets

- `npm run build`: standalone `dist/`; no VK Bridge or VK adapters.
- `npm run build:vk:prototype`: `dist-vk-prototype/`; explicit mock profile `vk_prototype`, `verified: false`. No VK Bridge, real accounts or purchases. Never use this artifact as the production VK application.
- `npm run build:vk`: `dist-vk/`; pinned VK Bridge 3.0.2, real `VKWebAppInit`, then `/api/vk/session`. That endpoint is not implemented in this prototype, so startup fails explicitly until the authentication backend is provided. This build never falls back to the mock adapter.

The common exporter preserves WASM/PCK integrity and asset-size checks. Every target has its own output and temporary directories; building another target does not delete the previous artifact.

## Communication

The existing minimal engine has no JS bridge. `PlatformService` sends `HTTPRequest` POST requests to an absolute same-origin `/__rally_platform` URL. The browser intercepts only that exact route and passes an allowlisted method to `RallyPlatform`. The returned JSON Response is consumed by Godot through its normal HTTP completion signal. Requests for all other routes/origins pass through unchanged, including the existing room transport.

The virtual endpoint is not a backend endpoint and grants no identity or ownership. Native/headless game execution does not use it. Native tests can continue without a browser adapter.

Methods in this prototype: `ready`, `getProfile`, `getEntitlements`. No `buy` method is exposed. The game consumes the returned profile and displays a noneditable platform nickname for a VK/prototype profile; standalone keeps the existing editable nickname.

VK bootstrap finishes before the engine starts; errors appear through existing boot diagnostics. Server authentication, session token lifecycle and profile validation will be added in the next stage. Raw launch parameters must never be logged.

## Validation

- `npm run test:platform`: adapter and transport unit tests.
- `node scripts/test-platform-build.mjs`: checks artifact isolation and includes.
- After building the prototype, `node scripts/test-platform-web.mjs`: executes the exported minimal WASM engine with the small `platform_probe.tscn` scene in Chromium desktop/mobile contexts; confirms that Godot receives the mock profile and that the virtual endpoint never reaches the HTTP server.
- After building standalone, `node scripts/test-platform-web.mjs dist`: same probe with the standalone profile.
- Browser checks use the same Playwright dependency/install procedure as the existing Web tests (`playwright@1.63.0`, Chromium).

The probe intentionally isolates communication from the expensive full game scene. Full-scene startup remains covered by `scripts/test-web-startup.mjs`. Chromium mobile emulation does not replace real VK Android/iOS testing.

## Next stage

Implement the signed-launch verification/session endpoint and persistent accounts, then test the `dist-vk/` artifact inside an actual VK test application. Payment callbacks and server-authoritative content access follow separately.

## Current local verification limitation

On the development execution host, the Web smoke test could not complete: the headless Chromium process closed during engine initialization; full Chromium launch reported `socket() failed: Operation not permitted`. No successful WASM-to-adapter roundtrip is claimed from this host. CI includes both desktop/mobile probe checks on Ubuntu; their successful results are required before treating the transport as proven in the exported engine. Unit tests and the three export/asset-isolation checks can run independently of that browser limitation.
