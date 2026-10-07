# Одна публикация: обычная игра и VK

## Адреса и сборка

Один Worker `rally-fans-simulator` публикует обе версии:

| Адрес | Назначение |
|---|---|
| `/` | Обычная игра, анонимный ник |
| `/vk/` | VK Bridge 3.0.2, авторизация и ник из `screen_name` |
| `/api/vk/session` | Проверка подписанных параметров запуска VK |
| `/api/rooms` и `/api/rooms/<id>/*` | Общие комнаты для обеих версий |

`npm run build` экспортирует оба варианта и складывает VK-сборку в `dist/vk/`. `npm run deploy` публикует весь `dist/` и общий API по `wrangler.jsonc`. `/vk` перенаправляется на `/vk/` с сохранением параметров запуска. Root shell не загружает VK Bridge; VK shell загружает свои относительные JS/WASM/PCK файлы из `/vk/`. Правила `_headers` применены к обоим наборам файлов.

Отдельные технические рельсы сохранены: `npm run build:standalone` → `dist/`, `npm run build:vk` → `dist-vk/`, `npm run build:vk:prototype` → `dist-vk-prototype/`. Они полезны для тестов; перед публикацией вызывайте `npm run build`, иначе `/vk/` не окажется в общем артефакте. `deploy:vk` и `dev:vk` теперь используют тот же Worker; отдельного `wrangler.vk.jsonc` больше нет. Mock-прототип не публикуется.

## Cloudflare

Используйте существующий Worker **rally-fans-simulator**, отдельный VK Worker создавать не нужно.

В Workers & Pages → существующий Worker → настройки Builds:

| Поле | Значение |
|---|---|
| Repository | `DaniilSmirnov/rfm-simulator` |
| Root directory | корень репозитория |
| Production branch | `main` после слияния PR |
| Node version | 22, при необходимости build variable `NODE_VERSION=22` |
| Build command | `npm ci && npm run build` |
| Deploy command | `npm run deploy` |

До слияния для тестового деплоя можно выбрать ветку `feature/vk-platform-prototype`. Для preview используйте `npx wrangler preview`; preview-секреты настраиваются отдельно, не считайте production-секреты автоматически доступными в preview.

`VK_APP_ID: "54809523"` уже задан в `wrangler.jsonc`. Имя Worker, binding `ASSETS`, существующие `ROOMS` и миграция SQLite Durable Objects сохраняются. Комнаты не разделены по платформам: человек с обычной версии и человек из VK могут входить по одному ID. Изменять namespace или создавать D1/KV/R2 не нужно.

В **Settings → Variables and Secrets** именно этого Worker добавьте **Secret**:

| Runtime secret | Значение |
|---|---|
| `VK_APP_SECRET` | Защищённый ключ приложения 54809523 |
| `VK_SERVICE_TOKEN` | Сервисный ключ доступа того же приложения; рекомендуется, но при его отсутствии/ошибке используется профиль VK Bridge после проверки подписанного user ID |
| `VK_SESSION_SECRET` | Независимая случайная строка, минимум 32 случайных байта |

Для генерации последнего секрета: `openssl rand -hex 32`. Если ключи были добавлены в отдельный `rfm-simulator-vk`, добавьте их заново в основной `rally-fans-simulator`: секреты разных Worker не общие. Секреты сборки не заменяют runtime secrets. Не помещайте ключи в JS, исходники или URL.

CLI-альтернатива:

```bash
npm ci
npx wrangler login
npx wrangler secret put VK_APP_SECRET
npx wrangler secret put VK_SERVICE_TOKEN
npx wrangler secret put VK_SESSION_SECRET
npm run build
npm run deploy
```

Каждая команда `secret put` интерактивно попросит значение. Эти команды автоматически в вашем Cloudflare-аккаунте не выполнялись.

## Настройки VK

В URL приложения 54809523 для поддерживаемых платформ укажите:

```text
https://<ваш-домен-существующего-Worker>/vk/
```

Например, для workers.dev: `https://rally-fans-simulator.<your-subdomain>.workers.dev/vk/`.

Открывайте приложение через [vk.com/app54809523](https://vk.com/app54809523). VK добавит подписанные параметры запуска. Прямая ссылка без параметров или вручную придуманные ID/подпись не авторизуют пользователя. Статика и `/api/vk/session` находятся на одном origin. Не добавляйте `X-Frame-Options: DENY/SAMEORIGIN` и CSP `frame-ancestors 'self'`: это мешает встраиванию.

## Поведение авторизации и общих комнат

Порядок: `VKWebAppInit` → launch params из URL (или `VKWebAppGetLaunchParams`, если query потерян контейнером) → HMAC-SHA256, App ID и `vk_ts` на сервере → `users.get(fields=screen_name)` с fallback на `VKWebAppGetUserInfo` только для того же подписанного user ID → подписанная часовая сессия → запуск Godot. Имена и фамилии не используются, при отсутствии shortname берётся `vk<id>`. Давность запуска ограничена часом, опережение — 60 секундами.

Сессия хранится только в памяти браузера. VK adapter добавляет `Authorization: Bearer ...` и `X-Rally-Platform: vk` только к запросам общего room API того же origin. Это относится к созданию, входу, sync, heartbeat и выходу. Сервер проверяет предъявленную сессию, а при создании/входе задаёт подтверждённый ник. Неверная/истёкшая сессия или VK-маркер без токена дают `401`, без автоматического перехода на анонимный профиль.

Запросы без сессии и VK-маркера допускаются как анонимные — это намеренное поведение общей платформы. Маркер сам по себе не доказательство личности. Публичный room API и анонимные участники общих комнат сохраняются; анонимный ник не является подтверждённым VK-аккаунтом. Доступ к существующей комнате по-прежнему определяется приватным room token, не платформой.

Через час нужно закрыть и повторно открыть приложение через VK. Платежи, постоянные аккаунты, достижения и платные entitlements пока не реализованы; текущий контент временно unrestricted.

## Проверка и диагностика

1. Откройте `/`: обычная версия запускается без VK и без ключей.
2. Откройте приложение через VK: загрузится `/vk/`, ник берётся из shortname и не редактируется.
3. Создайте комнату обычным клиентом и войдите из VK по тому же ID; повторите с VK-хозяином и обычным гостем.
4. Проверьте возврат из фона на VK Android/iOS и heartbeat.

Статусы `/api/vk/session`: `503` — базовая конфигурация не готова или одновременно нет рабочего service token и валидного Bridge-профиля; `401` — подпись, App ID или срок запуска; `502` — VK API не дал профиль и нет валидного Bridge fallback; `400` — формат запроса. Не пересылайте полный query запуска или session token. Ник и ID присутствуют в диагностике профиля, защищённые ключи и токены не выводятся.

CI `Platform builds` проверяет auth, отдельные артефакты и объединённый артефакт. Для него проверяются root и вложенный `/vk/` в desktop/mobile Chromium с настоящим Godot WASM. VK-тест использует синтетическую подпись, fixture VK API и stub Bridge; production-ключи и настоящий VK-контейнер проверяются после деплоя. GitHub CI ничего не публикует. Остальные игровые проверки по-прежнему пропускаются в текущей ветке.

Источники: [Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/), [runtime secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Static Assets](https://developers.cloudflare.com/workers/static-assets/binding/), [VK launch signature](https://github.com/VKCOM/vk-apps-launch-params/blob/master/examples/node.js).
