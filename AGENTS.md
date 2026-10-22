# AGENTS.md

Repository guidance for Rally Fans Simulator: a Godot game with standalone and VK browser builds, native exports, and a Cloudflare Worker backend.

## Read for the task

- Gameplay, stages, cars, UI, or networking: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes subsystem contracts, registries, and extension steps.
- Test selection or CI changes: [docs/TEST_AUDIT.md](docs/TEST_AUDIT.md), `scripts/test-catalog.mjs`, and `.github/workflows/check.yml` are the entry points. Derive current test counts from the registry.
- VK authentication, payments, or deployment: [docs/VK_MINI_APPS.md](docs/VK_MINI_APPS.md) and [docs/VK_CLOUDFLARE_SETUP.md](docs/VK_CLOUDFLARE_SETUP.md). For request limits, read [docs/REQUEST_RATE_LIMITS.md](docs/REQUEST_RATE_LIMITS.md).
- Loading or performance: [docs/MEMORY_CACHE_AND_LOADING.md](docs/MEMORY_CACHE_AND_LOADING.md), [docs/CPU_PERFORMANCE.md](docs/CPU_PERFORMANCE.md), or [docs/RENDER_PERFORMANCE.md](docs/RENDER_PERFORMANCE.md), according to the bottleneck.
- Custom Web engine changes: [engine/README.md](engine/README.md), `engine/custom.py`, and `engine/manifest.json`.

## Change boundaries

- Put gameplay in the matching domain under `game/scripts/`; keep `core/game.gd` as the assembly point and delegate to existing systems. Reuse registries and contracts rather than adding scattered special cases.
- Keep shared definitions in `game/data/`. Changes to catalogs or `net_protocol.json` must account for GDScript, browser, Worker, and test consumers. Preserve host-authoritative world simulation; follow the architecture's compatibility rules when changing the wire format.
- Use the existing UI kit and localization layer for interface changes. Keep standalone, VK, desktop, and touch input paths working where affected.
- Match surrounding style. GDScript uses tabs; `scripts/lint-gdscript.mjs` enforces paths, supported Web modules, record/layer helpers, and size budgets. `scripts/gdscript-budget.json` is a downward-only ratchet.
- Edit source files, then regenerate outputs through `scripts/` or `game/tools/`. Treat `game/generated/`, `.godot/`, `.cache/`, and `dist*` as generated output.
- Preserve the checked-in engine template, manifest hashes, and license notices together. The Web loader decompresses `index.wasm.gz` itself; serve it without `Content-Encoding: gzip`.
- Keep VK secrets in server configuration and ignored local secret files; exclude them from browser assets, logs, and commits. Run deployment commands only when deployment is requested.

## Verification

Use Node.js 22+ and Python 3; install JavaScript dependencies with `npm ci`. Scripts use Godot 4.4.1. On macOS or Windows, set `GODOT_BIN` to its absolute executable path; Linux x64 scripts can download the verified binary.

Run from the repository root, selecting checks that cover the change:

```sh
node scripts/lint-gdscript.mjs
node --test tests/<affected-suite>.test.mjs
node scripts/test-game.mjs --only=test_<name>.gd
node scripts/test-game.mjs --shard=core
npm test
```

The available shards are `core`, `simulation`, and `world`; `--only` runs one Godot test without the Node suites. Use `node scripts/test-game.mjs --list` to inspect the registry without downloading Godot. New functional Godot tests extend `res://tests/harness.gd`, have unique filenames, and must be registered in `scripts/test-catalog.mjs`. `--part=K/N` runs the K-th of N balanced slices of a shard (part 1 also runs its Node suites); CI runs every slice on its own runner, see the `tests` matrix in `.github/workflows/check.yml`.

Run Godot imports and bakes sequentially within one checkout; the test runner prepares shared generated assets. Use `package.json` for build commands and the CI workflow for exported-browser, multiplayer, Worker integration, and native startup checks relevant to the change. On pull requests the release exports (desktop, Android, the radio library for non-Linux targets, the VK prototype) run only when their inputs change, see the `changes` job in `.github/workflows/check.yml`; main runs them on every commit.

Report commands run and any blocked checks. Headless tests and successful exports do not establish visual quality, touch behavior, real VK authorization/payments, or target-device runtime behavior; validate those separately when affected.
