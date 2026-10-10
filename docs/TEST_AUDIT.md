# Test suite audit — October 2026

## Findings and policy

Current counts come from `node scripts/test-game.mjs --list` (registry) and the directory listing; on 2026-10-10 there are 63 functional `game/tests/test_*.gd` scripts, 16 Node test modules in `tests/`, eight standalone `scripts/test-*.mjs` scenarios and ten Godot screenshot/preview generators. Every functional script extends `res://tests/harness.gd`, which provides `check()`, `finish()` and a watchdog that fails the test a few seconds before the runner timeout when a script error stops it. Counts describe **files**, not assertions, coverage percentages or independently executable scenarios. This is not a claim of 100% unit coverage.

**Keep the gameplay tests.** We found no demonstrably redundant test that can safely be deleted. In particular:
- `test_rolling_wheels.gd` identified real missing Granta wheel pivots.
- `test_woodland.gd` safeguards stage boundaries, but its old assertion incorrectly treated the intentionally added vineyard/village mushrooms as leaked rally-forest decoration. It now checks scene-specific layers.
- `test_room_origin.gd` existed only in a focused VK workflow and is now part of the core suite.
- `*_preview.gd` scripts are **render fixtures**, not automated visual regression tests, until their results are compared with approved baselines.
- The separate Node server tests (`worker.integration.mjs`, `payments.integration.mjs`) are run by `npm run test:server` in production CI; Playwright startup/physics/multiplayer tests also run in production CI. These are not duplicates of the small Godot unit tests.

## Single authoritative functional registry

`scripts/test-catalog.mjs` explicitly classifies every `test_*.gd`. `npm test` now validates the registry, and `node scripts/test-game.mjs --list` prints it without downloading Godot. New tests **fail CI** unless assigned a group; deletion of a registered test also fails. The registry is not a coverage report.

| Group | Responsibilities | Run |
| --- | --- | --- |
| `core` | Menu/UI, VK permissions, imported assets, every player's car, controls, trunk, mobile view, loader, JS unit tests | `node scripts/test-game.mjs --shard=core` |
| `simulation` | Physics, schedules, AI, food and forest pickup interactions, multiplayer and towing | `node scripts/test-game.mjs --shard=simulation` |
| `world` | Forest, winter, village/vineyard and desert, road terrain, crowd navigation and scenery budgets | `node scripts/test-game.mjs --shard=world` |

`npm test` runs all groups locally. Each script gets a fresh OS process and a finite (90s or 180s) limit. On failure, the runner prints the test's tail, continues other test cases, writes `.cache/test-results/<shard>.json`, and exits nonzero if *any* failed. CI runs the three shards on separate workers in parallel (`fail-fast: false`) so a stuck world generation test does not suppress physics and VK results. Screenshots are rendered from the `world` job even when a test failed (`!cancelled()`), then uploaded.

### Known red checks addressed in PR #78

1. Missing physical pivots and wheel metadata in the Granta model, causing `Nil.quaternion` + timeout: fixed in the game asset and assertions now fail fast.
2. VK Web safe-area test fixture only supported one event subscriber, masking the viewport subscriber: fixed bridge fixture.
3. Web physics probe quitting Godot while callbacks still read WebAudio: browser now controls scene lifetime.
4. Vineyard forest mushroom additions contradicted `test_woodland.gd`'s former assertion; differentiated the two ecosystems rather than removing the assertion.
5. Sequential test runner stopped at first failing subprocess; replaced with independently reported cases.
6. Coverage hole in main test runner for `test_room_origin.gd`; included in the manifest.

## Added P0 contracts

- `test_vehicle_contract.gd`: all ten selectable vehicles, wheel layout/radius and real rotation, visible mesh, selection identity, trunk slots.
- `test_vk_catalog_matrix.gd`: every stage and car from the catalog, each SKU's access before/after purchase, cross-SKU isolation, free guest access and standalone unrestricted mode.
- `test-catalog.test.mjs`: test inventory consistency, nonempty ownership groups, inclusion of security/UI-critical suites.

Existing `payments-vk.test.mjs`, `payments.integration.mjs`, `test_trunk.gd`, `test_niva_integration.gd`, `test_room.gd` and `test_canyon.gd` remain authoritative for server payment grants, trunk opening, network handshakes and canyon geometry, respectively.

## Coverage still missing (next priorities)

| Risk | Missing end-to-end proof | Suggested implementation |
| --- | --- | --- |
| P0 complete spectator journey | Menu → select car/stage → drive/park → unload camp → cook/eat → pack up → complete return | Playwright drive an exported Godot scene plus assertions on gameplay events |
| P0 real VK friend invite | Real VK request delivered to a **second user** and autojoins existing room | Manual release checklist in actual Android/iOS/desktop VK; synthetic Bridge unit tests remain |
| P1 multiplayer inventory | Two players concurrently pick up, transfer, stow and reconnect with foreign furniture | Worker room stress test + two Godot clients |
| P1 geometry | Continuously probe wheel, foot and terrain collisions across all stages, not just sampled points | Deterministic path sampling + collision sweeps over each road chunk |
| P1 mobile lifecycle | Background/resume during checkout, invites, room reconnect and rendering changes | Browser/real-device E2E with touch/pause events |
| P1 resource/performance budgets | Peak resident memory, loading duration and hitch/frame time on mobile per stage | Budgeted browser benchmark with saved measurements |
| P2 visual baselines | Rendered screenshots currently uploaded but not compared to reviewed references | Stable fixed-camera baselines + perceptual diffs and human review |
| P2 soak | Repeat multiple stages, full spectators, room recovery, cooking and cleanup for an hour | Scheduled long-duration job, not PR gate |

Do not delete failing tests or relax numerical requirements solely to get green CI. Classify each failure as product regression, stale requirement, test fixture error, environmental failure, or timeout. Fix the underlying issue, then change the test only if the behavior's expected contract has genuinely changed. New user-facing features must include both a fast focused test and an integration or E2E scenario when applicable.
