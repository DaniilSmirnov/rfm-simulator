# Rally Fans Simulator — VK Mini Apps / Games integration

Status: design specification  
Target: a dedicated VK build that coexists with the current standalone web build  
Repository: `DaniilSmirnov/rfm-simulator`

## 1. Goal

Add VK Mini Apps / Games as a separate distribution target without coupling the core Godot game to VK-specific APIs.

The VK build must support:

- VK Mini Apps initialization through VK Bridge.
- Authenticated VK users.
- Player nickname taken from the VK profile shortname (`screen_name`).
- Per-item paid content.
- Server-side ownership / entitlements.
- Achievements with persistent progress.
- Existing multiplayer rooms.
- A separate VK build artifact, while preserving the current standalone build unchanged.

Paid content is sold individually and permanently:

- stages / rally special stages;
- player cars;
- characters;
- clothing;
- camp / gameplay items.

No premium currency is required for the first version.

## 2. Architectural rule

VK is a platform adapter, not a game dependency.

The game must talk to a small stable interface:

```text
Godot
  |
  v
RallyPlatform
  |-----------------------------|
  |                             |
standalone adapter          VK adapter
                                |
                             VK Bridge
                                |
                    Rally Fans backend / Worker
                                |
                  users / purchases / achievements
```

VK-specific calls must not be scattered through GDScript.

Recommended browser API:

```js
window.RallyPlatform = {
  target: "vk" | "standalone",
  ready(),
  getProfile(),
  getEntitlements(),
  buy(sku),
  getAchievements(),
  reportAchievementEvent(type, payload),
  inviteFriends(),
};
```

The standalone adapter must keep the existing behavior and return a local/anonymous profile with no paid-content restrictions unless a separate standalone account system is introduced later.

## 3. Separate build

Current build remains:

```bash
npm run build
```

Output:

```text
dist/
```

Add:

```bash
npm run build:vk
```

Output:

```text
dist-vk/
```

Recommended implementation:

- refactor the current `scripts/build-web.mjs` into shared build logic;
- keep `npm run build` backward compatible;
- add either `scripts/build-vk.mjs` or a target flag such as `--target=vk`;
- export Godot only once per build invocation;
- apply platform-specific web-shell post-processing after the common Godot export;
- copy VK-only JS only to `dist-vk/`;
- do not load VK Bridge in the standalone build.

Suggested files:

```text
web/platform/
  platform-base.js
  platform-standalone.js
  platform-vk.js

server/
  auth-vk.mjs
  store.mjs
  achievements.mjs

game/data/
  store_catalog.json
  achievements.json

scripts/
  build-web.mjs
  build-vk.mjs            # optional wrapper

dist/                     # standalone
dist-vk/                  # VK
```

Use a pinned npm dependency for `@vkontakte/vk-bridge` and ship the tested dependency with the VK build. Do not rely on an unpinned CDN at runtime.

## 4. VK application bootstrap

VK build startup order:

1. Load the VK adapter.
2. Call `VKWebAppInit`.
3. Read the raw VK launch query from `window.location.search`.
4. Send the complete signed launch params to the backend.
5. Backend verifies the VK launch signature.
6. Backend resolves the player profile and returns an application session.
7. Load entitlements and achievements.
8. Start the Godot game.
9. Pass the resolved profile, entitlements and achievements into the game.

The game should not start paid-content-sensitive UI before the platform session has either succeeded or entered an explicit error/offline state.

## 5. Authentication and identity

### 5.1 Source of identity

The trusted user identifier is:

```text
platform = vk
platform_user_id = vk_user_id
```

`vk_user_id` is trusted only after the backend validates the launch signature.

Never trust a client-supplied user ID without the signed launch params.

### 5.2 Launch signature verification

VK supplies launch parameters containing values such as:

```text
vk_app_id
vk_user_id
vk_platform
vk_language
vk_ts
...
sign
```

Backend verification:

1. Take only query parameters whose names start with `vk_`.
2. Sort by key.
3. URL-encode in the VK-compatible canonical form.
4. Calculate HMAC-SHA256 using the VK app protected secret.
5. Encode as URL-safe Base64 without padding.
6. Compare using a timing-safe comparison with `sign`.
7. Reject invalid or stale requests according to the session policy.

The protected VK app key must exist only as a Worker secret / server secret.

### 5.3 VK shortname as player nickname

Requirement:

> The in-game nickname is the user's VK shortname.

Do not derive the nickname from `first_name` / `last_name`.

`VKWebAppGetUserInfo` is useful for profile information but must not be the only source of the nickname because `screen_name` is not guaranteed in its common response shape.

Resolve the nickname with VK API:

```text
users.get
user_ids = vk_user_id
fields = screen_name
```

Store:

```json
{
  "platform": "vk",
  "platform_user_id": "123456",
  "nickname": "daniilsmirnov",
  "avatar_url": "...",
  "last_profile_sync_at": "..."
}
```

Profile data is a cache. Refresh it periodically and when the player starts a new authenticated session.

Fallback only if VK returns no usable `screen_name`:

```text
vk<vk_user_id>
```

The fallback is technical and should not be user-editable in the VK build.

### 5.4 Backend session

After launch verification return a short-lived application session token.

Recommended:

- opaque or signed token;
- short expiration;
- stored in JS memory, not persisted as authoritative identity;
- every protected API validates it;
- session resolves to `platform + platform_user_id`.

## 6. Paid content

### 6.1 Product types

Supported product types:

```text
stage
car
character
clothing
item
```

Every product is purchased separately.

Do not make bundles, premium currency or subscriptions a dependency of v1.

Every SKU is permanent and immutable.

Example:

```json
{
  "sku": "stage_winter_mountain_01",
  "type": "stage",
  "title": "Зимняя горная СУ",
  "content_id": "winter_mountain_01",
  "enabled": true
}
```

The visible name may change; `sku` must never change after release.

### 6.2 Free baseline

The game must remain playable without a purchase.

At minimum keep free:

- one stage;
- one player car;
- one base character;
- enough clothing for the base character;
- one functional variant of every item required by the core gameplay loop.

Paid items may add variety but must not be required to complete the basic rally spectator loop.

### 6.3 Ownership model

Backend is the source of truth.

```text
entitlements
  user_id
  sku
  source
  external_order_id
  granted_at
  revoked_at
```

Client-side storage, Godot save files, query parameters and VK Bridge purchase success are not sufficient proof of ownership.

A user owns a product only when the server has a valid entitlement.

### 6.4 Purchase flow

Preferred Direct Games flow where supported:

```text
Player presses Buy
    |
    v
VK adapter -> VKWebAppShowOrderBox
    |
    v
VK payment/order flow
    |
    v
server-side VK order notification/callback
    |
    v
idempotently create order + entitlement
    |
    v
client refreshes /api/me/entitlements
    |
    v
item becomes owned
```

The client must not grant content based only on the resolved Bridge promise.

The order callback must be idempotent. Duplicate notifications must never create duplicate grants or inconsistent order state.

Recent VK Bridge issue reports show that `VKWebAppShowOrderBox` can behave differently on mobile web even when the payment reaches the payment backend. Therefore the integration must test Desktop VK, VK Android, VK iOS and mobile web separately, and the UI must be able to recover ownership by refreshing entitlements after an ambiguous client-side error.

### 6.5 Product catalog

Keep the game's content definition independent from the provider's payment metadata.

Recommended separation:

```text
game/data/store_catalog.json
  sku
  type
  content_id
  title
  description
  preview
  free
  enabled

server/provider catalog
  sku
  vk_item_id
  current price / provider metadata
```

The backend validates that a requested provider item maps to a known enabled SKU.

### 6.6 Stage multiplayer rule

Recommended default rule:

- a player must own a paid stage to select it or create a room on it;
- guests may join a room whose host owns that stage;
- guest access does not grant a permanent entitlement;
- a guest still sees the stage as locked outside that hosted room.

Implement the policy behind one server-side rule so it can be changed later without rewriting the client.

### 6.7 Cars, characters, clothing and items

These are personal entitlements.

A player may use only owned content.

Paid cars must not be objectively stronger than free cars. They may differ in visuals, sound and driving character, but monetization must not create a direct competitive advantage.

Paid camp items must have a free functional equivalent when the item type is required by gameplay.

## 7. Store UI

Add a Store screen with tabs:

```text
СУ
Машины
Персонажи
Одежда
Предметы
```

Product states:

```text
free
available
purchasing
owned
equipped
unavailable
error
```

Required UX:

- show a lock on non-owned selectable content;
- show `Купить` for an available SKU;
- show `Куплено` for an entitlement;
- show `Используется` for currently selected content;
- after purchase, refresh entitlements from the server;
- after reload/reinstall/device change, purchases restore from the server automatically.

Do not persist ownership only in local storage.

## 8. Achievements

Achievements are an application-level feature backed by our server.

Do not depend on a platform-native achievement API for the core system.

VK score / leaderboard integration can be added separately later.

### 8.1 Achievement definition

```json
{
  "id": "first_rally_car",
  "title": "Первый экипаж",
  "description": "Посмотреть первый прошедший экипаж",
  "hidden": false,
  "target": 1
}
```

Achievement IDs are permanent.

### 8.2 Persistence

```text
achievement_progress
  user_id
  achievement_id
  value
  unlocked_at
  updated_at
```

Backend is authoritative.

### 8.3 Event model

The game emits semantic events, not arbitrary unlock commands:

```text
rally_car_passed
stage_completed
camp_item_placed
kebab_cooked
plov_cooked
racer_recovered
beer_consumed
camp_packed
room_joined
room_hosted
```

Example:

```json
{
  "type": "racer_recovered",
  "event_id": "uuid",
  "payload": {
    "stage_id": "forest_01"
  }
}
```

Backend maps events to achievement progress.

Use event IDs for idempotency where an event can be retried.

### 8.4 Initial achievement set

Suggested starter achievements:

| ID | Title | Condition |
|---|---|---|
| `first_rally_car` | Первый экипаж | See the first rally car |
| `full_stage` | До последнего экипажа | Finish a complete rally session |
| `first_kebab` | Шашлык готов | Cook kebab |
| `first_plov` | Казан работает | Cook plov |
| `first_recovery` | Трос пригодился | Recover a rally car |
| `camp_master` | Лагерь разбит | Place the required base camp setup |
| `pack_everything` | Ничего не забыли | Pack the camp after the rally |
| `first_multiplayer` | С друзьями веселее | Join a multiplayer room |
| `host_multiplayer` | Организатор выезда | Host a multiplayer room |

Avoid achievements that require a purchase.

### 8.5 Achievement UI

Add:

- achievement list;
- locked/unlocked state;
- progress where relevant;
- unlock toast;
- unlock time for completed achievements.

The unlock toast must not pause the game.

## 9. Godot integration

Godot must not import or know VK Bridge.

Create one bridge node/service in GDScript, for example:

```text
PlatformService
```

Responsibilities:

- receive platform bootstrap data from JavaScript;
- expose current profile;
- expose `is_owned(sku)`;
- request purchase;
- receive entitlement refresh;
- report semantic achievement events;
- emit signals when profile/ownership/achievements change.

Suggested signals:

```gdscript
signal profile_ready(profile)
signal entitlements_changed(skus)
signal purchase_started(sku)
signal purchase_finished(sku, success, error)
signal achievement_unlocked(id)
```

If the custom/minimal engine build cannot use a normal Godot JavaScript bridge API, keep the existing repository constraint and implement the narrowest compatible communication mechanism in the generated web shell. Do not replace the custom engine solely to add VK.

## 10. Backend API

Suggested endpoints:

```text
POST /api/vk/session
GET  /api/me
GET  /api/me/entitlements
GET  /api/me/achievements

GET  /api/store/catalog

POST /api/achievements/events

POST /api/vk/orders
```

Optional:

```text
POST /api/me/refresh-profile
POST /api/store/reconcile
```

All `/api/me/*`, purchase reconciliation and achievement mutation endpoints require an authenticated application session.

## 11. Data model

Logical schema:

```text
users
  id
  platform
  platform_user_id
  nickname
  avatar_url
  created_at
  last_seen_at
  last_profile_sync_at

products
  sku
  type
  content_id
  enabled

orders
  id
  user_id
  provider
  provider_order_id
  sku
  status
  created_at
  updated_at

entitlements
  user_id
  sku
  source
  provider_order_id
  granted_at
  revoked_at

achievements
  id
  target
  hidden

achievement_progress
  user_id
  achievement_id
  value
  unlocked_at
  updated_at

achievement_events
  user_id
  event_id
  type
  created_at
```

A Cloudflare-native persistence layer can be selected during implementation. Do not overload the existing short-lived room Durable Object storage with permanent purchases or achievement ownership.

## 12. Multiplayer identity

Replace generated/local display names with the authenticated profile nickname in the VK build.

Network payload must use:

```text
player_id = internal session/user identifier
display_name = VK screen_name
```

Never use the shortname itself as a database primary key because the user may change it.

The stable account key remains `vk_user_id`.

## 13. Security requirements

Mandatory:

- VK protected key only on the server.
- Verify signed VK launch params server-side.
- Never trust `vk_user_id`, `screen_name`, ownership or prices from the client.
- Never grant an entitlement from the Bridge success callback alone.
- Make payment callbacks idempotent.
- Validate SKU against the server catalog.
- Rate-limit auth, payment reconciliation and achievement event endpoints.
- Sanitize nickname before rendering in HTML.
- Use the stable numeric VK user ID as account identity.
- Do not expose provider secrets in `dist-vk/`.
- Do not store permanent entitlements only in VK Storage or localStorage.

## 14. Tests

### Build

- `npm run build` still creates the standalone artifact.
- `npm run build:vk` creates `dist-vk/`.
- standalone output does not include VK Bridge.
- VK output includes only the required VK adapter assets.
- both outputs pass the existing WebAssembly/PCK integrity checks.

### Auth

- valid launch params authenticate;
- invalid signature is rejected;
- altered `vk_user_id` is rejected;
- missing signature is rejected;
- nickname uses `screen_name`;
- profile shortname change updates cached nickname without changing the account;
- fallback nickname is deterministic.

### Store

- free SKU works without entitlement;
- paid SKU is locked without entitlement;
- valid purchase callback grants once;
- duplicate callback stays idempotent;
- fake client-side purchase success grants nothing;
- ownership restores on a new session/device;
- disabled/unknown SKU cannot be purchased;
- paid stage host policy is enforced.

### Achievements

- event increments expected progress;
- duplicate idempotent event does not double count;
- unlock occurs once;
- purchase is never required by an achievement;
- achievement persistence survives a new session.

### Compatibility

Smoke-test at least:

- VK desktop web;
- VK Android app;
- VK iOS app;
- VK mobile web;
- standalone web build.

Pay special attention to `VKWebAppShowOrderBox` behavior on mobile web.

## 15. Definition of done

The VK integration is complete when:

1. `npm run build` behaves as before.
2. `npm run build:vk` produces a deployable VK artifact.
3. VK Bridge is initialized only in the VK build.
4. A VK user is authenticated through verified launch params.
5. The game displays the user's VK `screen_name` as their nickname.
6. Re-entering the app resolves the same account by `vk_user_id`.
7. Store catalog shows stages, cars, characters, clothing and items.
8. Every paid product is an individual permanent purchase.
9. Purchases are granted only by server-confirmed ownership.
10. Owned content survives reload/device change.
11. Multiplayer shows VK shortnames.
12. Achievements persist server-side and unlock from semantic game events.
13. Existing standalone multiplayer and gameplay are not regressed.
14. Unit/integration tests cover auth, purchase idempotency, entitlements, achievements and build isolation.

## 16. VK setup checklist

Before production release:

- Create/configure the VK Mini App / game entry.
- Set the production URL to the deployed VK build.
- Configure a separate development URL/environment.
- Store the protected app secret in Worker secrets.
- Configure the payment/order callback URL required by the selected VK game monetization flow.
- Register every production SKU with a stable provider item identifier.
- Test purchases in the VK test environment before enabling real payments.
- Verify desktop, Android, iOS and mobile web separately.
- Complete VK moderation requirements and policies visible in the developer dashboard at release time.

## 17. References used for this design

- VK Bridge: https://github.com/VKCOM/vk-bridge
- VK API schema: https://github.com/VKCOM/vk-api-schema
- VK Mini Apps launch-params signature example: https://github.com/VKCOM/vk-apps-launch-params
- VK API `users.get` supports the `screen_name` field in the current public schema.
- VK Bridge exposes Direct Games methods including `VKWebAppShowOrderBox`, `VKWebAppShowInviteBox` and `VKWebAppShowLeaderBoardBox`.

VK platform behavior and monetization requirements can change. Re-check the live VK developer dashboard and current documentation immediately before enabling production payments.
