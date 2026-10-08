# Implementation prompt — VK Mini Apps build for Rally Fans Map

Repository: https://github.com/DaniilSmirnov/rfm-simulator

## Актуальный план интеграции — 8 октября 2026

Бренд: **Rally Fans Map**. VK App ID: `54809523`.

### Выполнено

- Общий Cloudflare Worker: standalone `/`, VK `/vk/`; `npm run build` собирает оба маршрута. Отдельные команды `build:standalone` и `build:vk` сохранены.
- Минимальный VK Bridge, получение launch params из URL или Bridge, серверная проверка подписи и краткоживущая сессия. Пользователь подтвердил рабочую загрузку VK.
- Никнейм `screen_name` с техническим fallback `vk<id>`; общие комнаты без разделения по платформам.
- Подготовка товаров: единый `game/data/store_catalog.json`, 13 постоянных SKU, права в bootstrap через PlatformService.
- В VK бесплатны СУ 1 и машины 1–3. СУ 2–3 и машины 4–10 видны как закрытые; выбор и создание комнаты проверяются. Standalone сохраняет полный доступ.
- Гость может временно играть на СУ хозяина общей комнаты, но не получает право владения. Личные машины проверяются и при входе в комнату.
- Продажи выключены (`purchase_enabled: false`); платёжный Bridge и выдача покупок ещё не реализованы.

### Следующий шаг: постоянные аккаунты и права

1. Подготовить Cloudflare D1 отдельно от короткоживущих комнат: `users`, `orders`, `entitlements`; уникальные ключи `(platform, platform_user_id)`, идентификатор заказа провайдера и `(user_id, sku)`.
2. После проверенной авторизации находить аккаунт по числовому VK ID, обновлять кеш профиля и возвращать активные права из БД вместо текущего пустого списка.
3. Добавить защищённый endpoint обновления прав, обновление PlatformService и состояния селекторов; проверить восстановление после перезагрузки/смены устройства.
4. Переключить серверную проверку выбора на тот же источник прав. Каталог и SKU менять только совместимыми миграциями.

### После постоянных прав

- Проверить актуальный платёжный сценарий VK и настройки приложения; сопоставить SKU с товарами провайдера и ценами на сервере.
- Подписанные/проверенные уведомления оплаты, идемпотентные заказы и выдача прав в транзакции, повторное получение статуса при неоднозначном клиентском результате.
- Экран магазина и тестовый платёжный контур. Успех Bridge сам по себе никогда не выдаёт товар.
- Проверить отсутствие преимущества платных машин до включения продаж, затем отдельно протестировать desktop, Android, iOS и mobile web.
- Достижения и постоянный прогресс — отдельный последующий этап.

### Границы текущего этапа

Постоянных аккаунтов, хранения покупок, цен и реальной оплаты пока нет. Сервер возвращает VK-права `restricted` с пустым списком SKU. Каталог отделён от платёжных данных; `enabled` означает существующий контент, `purchase_enabled` — возможность продажи (сейчас везде false). Индексы `content_id` и SKU фиксированы: не переупорядочивать существующие модели/СУ без миграции. Проверки меню обеспечивают игровой UX, но не являются защитой скопированных клиентских ресурсов. Общий standalone остаётся открытым по принятому продуктовым правилу.


Read `docs/VK_MINI_APPS.md` completely before changing code.

## Goal

Implement a separate VK Mini Apps / Games build of Rally Fans Map while keeping the existing standalone build fully functional.

The implementation must include:

- separate `npm run build:vk`;
- VK Bridge bootstrap;
- server-side verification of VK launch params;
- persistent VK user account keyed by `vk_user_id`;
- in-game nickname from VK `screen_name`;
- individual paid products;
- server-side entitlements;
- achievements;
- existing multiplayer integration;
- tests and documentation.

Do not implement premium currency, subscriptions, loot boxes or pay-to-win mechanics.

## Product rules

Paid content categories:

1. stages;
2. player cars;
3. characters;
4. clothing;
5. items.

Every paid object is one independent permanent SKU.

Keep at least one free stage, car, base character and the functional base camp items required to play.

Paid cars must not provide a direct competitive advantage.

Default paid-stage multiplayer policy:

- the host must own a paid stage to create/select it;
- guests may join that host's room without owning the stage;
- guest access is temporary and does not grant ownership.

Keep this policy isolated behind one backend/game rule so it can be changed later.

## Architecture constraints

Do not call VK Bridge directly from arbitrary GDScript.

Add a platform abstraction:

```text
Godot -> PlatformService -> browser RallyPlatform -> platform adapter
```

Standalone and VK must be separate adapters.

Suggested browser surface:

```js
RallyPlatform.ready()
RallyPlatform.getProfile()
RallyPlatform.getEntitlements()
RallyPlatform.buy(sku)
RallyPlatform.getAchievements()
RallyPlatform.reportAchievementEvent(type, payload)
RallyPlatform.inviteFriends()
```

The current custom/minimal Godot engine is a project constraint. Do not replace it just to gain a different JS bridge. Use the narrowest communication mechanism compatible with the existing build.

## Build requirements

Preserve:

```bash
npm run build
# -> dist/
```

Add:

```bash
npm run build:vk
# -> dist-vk/
```

Requirements:

- reuse common Godot export/build code;
- do not duplicate the whole build pipeline;
- standalone output must not load VK Bridge;
- VK output must include VK adapter code and a pinned/tested `@vkontakte/vk-bridge`;
- do not depend on an unpinned CDN;
- keep current WASM and PCK validation;
- keep existing file-size checks;
- add tests proving build isolation.

## VK bootstrap

VK build startup:

1. load platform adapter;
2. `VKWebAppInit`;
3. capture raw `window.location.search`;
4. send signed launch params to `POST /api/vk/session`;
5. backend validates signature;
6. backend resolves user/profile;
7. fetch entitlements + achievements;
8. expose bootstrap data to Godot;
9. start gameplay.

Do not silently fall back to an anonymous VK user when signature verification fails. Show a clear startup error with technical details available through the existing diagnostics mechanism.

## Authentication

Server identity:

```text
platform = vk
platform_user_id = verified vk_user_id
```

Implement VK launch signature verification on the backend using the protected application key and HMAC-SHA256.

Only `vk_*` params take part in the signed payload; sort them as required by VK launch params.

Use timing-safe comparison.

Never ship the VK protected key to the browser.

Issue a short-lived application session after verification.

## Nickname requirement

The displayed in-game nickname must be the VK shortname: `screen_name`.

Do not use first + last name as the nickname.

Do not assume `VKWebAppGetUserInfo` contains `screen_name`.

Resolve it through VK API `users.get` with:

```text
user_ids=<verified vk_user_id>
fields=screen_name
```

Cache the profile server-side and periodically refresh it.

Account identity remains numeric `vk_user_id`, because shortname can change.

If VK returns no usable shortname, use deterministic fallback:

```text
vk<vk_user_id>
```

Do not make the fallback user-editable in the VK build.

Use the profile shortname in multiplayer display names.

## Paid content and entitlements

Introduce stable SKUs, e.g.:

```text
stage_winter_mountain_01
car_wagon_01
character_spectator_04
clothing_jacket_orange_01
item_chair_retro_01
```

SKU is immutable after release.

Separate game content metadata from provider/payment metadata.

Suggested game catalog:

```text
game/data/store_catalog.json
```

Fields:

```text
sku
type
content_id
title
description
preview
free
enabled
```

Backend is authoritative for ownership.

Add persistent orders + entitlements. Choose an appropriate Cloudflare-native persistent store; do not store permanent purchases inside the current short-lived multiplayer-room Durable Object state.

## Purchase flow

Use the supported VK game purchase flow through `VKWebAppShowOrderBox` where applicable.

Critical rule:

**Never grant an entitlement from the client-side Bridge success alone.**

Ownership must be confirmed by the server-side VK order flow/callback.

Implement:

- known-SKU validation;
- order status;
- idempotent order processing;
- idempotent entitlement grant;
- recovery/reconciliation after ambiguous client result;
- entitlement refresh after purchase attempt.

There have been recent platform reports of `VKWebAppShowOrderBox` producing a mobile-web client error even when the backend payment flow proceeds. Therefore client errors must not be interpreted as definitive payment failure until ownership is refreshed from the backend.

Add tests for duplicated callbacks and ambiguous client results.

## Store UI

Add an in-game Store screen:

```text
СУ
Машины
Персонажи
Одежда
Предметы
```

Each product state:

```text
free
available
purchasing
owned
equipped
unavailable
error
```

Locked content must be visible in selectors where useful but clearly marked and not usable without entitlement.

Purchase completion refreshes server entitlements.

A new device/reload must restore all purchases from the server.

## Achievements

Implement our own server-authoritative achievement system.

Do not make core achievement logic depend on VK leaderboard/score APIs.

Game reports semantic events; backend derives progress/unlocks.

Initial events:

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

Use `event_id` for idempotency where events can retry.

Initial achievements:

```text
first_rally_car
full_stage
first_kebab
first_plov
first_recovery
camp_master
pack_everything
first_multiplayer
host_multiplayer
```

Do not create achievements that require buying something.

Add an achievements screen and non-blocking unlock toast.

Persist progress and unlock time server-side.

## Backend API

Implement or equivalent:

```text
POST /api/vk/session

GET  /api/me
GET  /api/me/entitlements
GET  /api/me/achievements

GET  /api/store/catalog

POST /api/achievements/events

POST /api/vk/orders
```

Protect all user-specific endpoints with the application session.

Rate-limit auth, achievement mutation and purchase reconciliation.

## Multiplayer

Do not use VK shortname as the multiplayer/database primary identifier.

Use:

```text
stable player/account id -> verified VK account
display name             -> screen_name
```

Room creation and join must continue working with standalone clients according to the current compatibility design.

If protocol changes are necessary, version them and cover migration/backward compatibility with tests.

## Security

Mandatory:

- server-side launch signature validation;
- secret only in Worker secrets;
- no trust in client user ID;
- no trust in client screen_name;
- no trust in client price;
- no trust in client ownership;
- no entitlement from Bridge promise alone;
- idempotent order callbacks;
- stable numeric VK ID as account identity;
- sanitize profile strings rendered to HTML;
- no permanent ownership only in localStorage or VK Storage.

## Tests

Add unit/integration tests for:

### Build
- standalone build still works;
- VK build exists separately;
- VK assets absent from standalone;
- existing WASM/PCK checks retained.

### Auth
- valid signature;
- invalid signature;
- altered user id;
- missing sign;
- shortname resolution;
- shortname change does not create a new account.

### Store
- free vs paid access;
- entitlement restore;
- fake client success cannot unlock;
- duplicate callback;
- unknown SKU;
- disabled SKU;
- paid-stage host/guest rule.

### Achievements
- progress;
- one-time unlock;
- idempotent duplicate events;
- persistence.

### Multiplayer
- VK shortname displayed;
- stable user identity independent of shortname;
- room flow still works.

Run all existing tests as well.

## Compatibility / platform smoke test matrix

Document manual verification for:

- VK desktop web;
- VK Android app;
- VK iOS app;
- VK mobile web;
- normal standalone web deployment.

Explicitly test purchase flow separately on every VK surface.

## Implementation process

1. Inspect the current architecture first.
2. Write a short implementation plan before code.
3. Work in a dedicated branch, e.g. `feature/vk-mini-apps`.
4. Prefer small atomic commits.
5. Keep standalone behavior intact after every stage.
6. Add tests together with each subsystem.
7. Do a self-review of security, payment idempotency and build isolation.
8. Open a PR to `main` with:
   - architecture summary;
   - endpoints added;
   - persistence choice;
   - build commands;
   - required VK secrets/settings;
   - test results;
   - manual VK test checklist;
   - known platform limitations.

## Definition of done

Do not call the task complete until all of the following are true:

- `npm run build` still builds standalone.
- `npm run build:vk` builds a separate VK artifact.
- VK Bridge exists only in VK artifact.
- verified VK launch params create a stable account.
- nickname comes from `screen_name`.
- paid stages/cars/characters/clothing/items use separate SKUs.
- entitlements are server-authoritative.
- purchase callbacks are idempotent.
- purchase restoration works.
- achievements persist server-side.
- VK nickname is visible in multiplayer.
- paid-stage host/guest rule is enforced.
- existing tests remain green.
- new auth/store/achievement/build tests are green.
- documentation lists every required VK dashboard setting and Worker secret.
