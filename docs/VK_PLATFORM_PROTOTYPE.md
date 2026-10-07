# VK platform transport prototype

This is a technical prototype, not a completed VK integration. Minimal server-verified VK authentication is implemented. Permanent account storage, entitlements, purchase flow and achievements are not implemented. See [Cloudflare setup](VK_CLOUDFLARE_SETUP.md).

## Build targets

- `npm run build`: standalone `dist/`; no VK Bridge or VK adapters.
- `npm run build:vk:prototype`: `dist-vk-prototype/`; explicit mock profile `vk_prototype`, `verified: false`. No VK Bridge, real accounts or purchases. Never use this artifact as the production VK application.
- `npm run build:vk`: `dist-vk/`; pinned VK Bridge 3.0.2, real `VKWebAppInit`, then `/api/vk/session`. The endpoint validates signed launch parameters and resolves the shortname through VK API; configure the VK Worker secrets before use. This build never falls back to the mock adapter.

The common exporter preserves WASM/PCK integrity and asset-size checks. Every target has its own output and temporary directories; building another target does not delete the previous artifact.

## Communication

The existing minimal engine has no JS bridge. `PlatformService` sends `HTTPRequest` POST requests to an absolute same-origin `/__rally_platform` URL. The browser intercepts only that exact route and passes an allowlisted method to `RallyPlatform`. The returned JSON Response is consumed by Godot through its normal HTTP completion signal. VK room requests additionally receive an in-memory bearer session; other routes/origins pass through unchanged.

The virtual endpoint is not a backend endpoint and grants no identity or ownership. Native/headless game execution does not use it. Native tests can continue without a browser adapter.

Methods in this prototype: `ready`, `getProfile`, `getEntitlements`. No `buy` method is exposed. The game consumes the returned profile and displays a noneditable platform nickname for a VK/prototype profile; standalone keeps the existing editable nickname.

VK bootstrap finishes before the engine starts; errors appear through existing boot diagnostics. A signed session lasts one hour; reopening through VK is required after expiry. Raw launch parameters must never be logged.

## Validation

- `npm run test:platform`: adapter and transport unit tests.
- `node scripts/test-platform-build.mjs`: checks artifact isolation and includes.
- After building the prototype, `node scripts/test-platform-web.mjs`: executes the exported minimal WASM engine with the small `scripts/platform_probe.tscn` scene in Chromium desktop/mobile contexts; confirms that Godot receives the mock profile and that the virtual endpoint never reaches the HTTP server.
- After building standalone, `node scripts/test-platform-web.mjs dist`: same probe with the standalone profile.
- Browser checks use the same Playwright dependency/install procedure as the existing Web tests (`playwright@1.63.0`, Chromium).

The probe intentionally isolates communication from the expensive full game scene. Full-scene startup remains covered by `scripts/test-web-startup.mjs`. Chromium mobile emulation does not replace real VK Android/iOS testing.

## Next stage

Configure the Worker and test `dist-vk/` inside an actual VK test application; add persistent accounts next. Payment callbacks and server-authoritative content access follow separately.

## Verified transport and remaining limitations

The original standalone/prototype WASM transport passed Chromium desktop/mobile CI on 2026-10-07. The VK build test now exercises a synthetic signed launch against the real auth module, a fixture VK API response, a stub Bridge initialization and an authorized room request. This does not prove production VK credentials or native VK container behavior. Actual VK Android/iOS and desktop launches remain deployment acceptance checks.
