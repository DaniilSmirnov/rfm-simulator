# VK Bridge, авторизация и отдельный Cloudflare Worker

## Что реализовано

VK Bridge 3.0.2 включён только в VK-артефакт. Инициализация: `VKWebAppInit` → `POST /api/vk/session` → проверка HMAC-SHA256 подписи, App ID и `vk_ts` → серверный `users.get(fields=screen_name)` → запуск Godot с подтверждённым ником. Имена и фамилии из профиля не используются. Если shortname отсутствует, ник `vk<id>`.

Допустимая давность запуска — 1 час, допустимое опережение времени — 60 секунд. Сессия подписана отдельным секретом и действует 1 час. Браузер хранит токен в памяти и добавляет Authorization только к запросам комнат того же origin, включая heartbeat и выход. VK Worker проверяет сессию и задаёт ник при создании/присоединении к комнате. При истечении сессии нужно закрыть и снова открыть приложение через VK; автоматического обновления пока нет.

Платежи, покупки, постоянные аккаунты и достижения в этот этап не входят. Всё существующее содержимое временно доступно (`mode: unrestricted`); это не реализация платных entitlements.

## Две независимые сборки

| Параметр | Обычная игра | VK Mini App |
|---|---|---|
| Worker | `rfm-simulator` | `rfm-simulator-vk` |
| Конфигурация | `wrangler.jsonc` | `wrangler.vk.jsonc` |
| Сборка | `npm run build` | `npm run build:vk` |
| Артефакт | `dist/` | `dist-vk/` |
| Деплой | `npm run deploy` | `npm run deploy:vk` |
| Авторизация | Анонимная | Подписанный запуск VK |
| Комнаты | Namespace обычного Worker | Отдельный namespace VK Worker |

Worker одновременно раздаёт файлы через Workers Static Assets и обслуживает `/api/*`. Это конфигурация Workers, а не отдельный Pages-проект. Godot экспортируется существующим минимальным шаблоном, без его замены.

`npm run build:vk:prototype` создаёт только тестовый `dist-vk-prototype/`: он не предназначен для публикации как настоящее VK-приложение.

## 1. Подготовить VK-приложение

В кабинете разработчика VK создайте/выберите тестовое Mini App. Получите:

- числовой ID приложения;
- защищённый ключ приложения для проверки подписи запуска;
- сервисный ключ доступа того же приложения для серверного `users.get`.

В `wrangler.vk.jsonc` уже задан `vars.VK_APP_ID: "54809523"`. ID приложения не секрет. При смене приложения замените его на новый числовой ID. Оставьте `PLATFORM: "vk"`. Если меняете название Worker, используйте то же название при создании проекта в Cloudflare.

## 2. Создать отдельный Worker в Cloudflare

В **Workers & Pages** создайте Worker, подключите GitHub-репозиторий `DaniilSmirnov/rfm-simulator`. Настройте Workers Builds:

| Поле | Обычная игра | VK |
|---|---|---|
| Название Worker | `rfm-simulator` | `rfm-simulator-vk` |
| Root directory | корень репозитория | корень репозитория |
| Production branch | `main` | `main` после слияния PR |
| Build command | `npm ci && npm run build` | `npm ci && npm run build:vk` |
| Deploy command | `npm run deploy` | `npm run deploy:vk` |
| Node version | 22 | 22 |

При необходимости задайте `NODE_VERSION=22` в настройках сборки. Для проверки до слияния можно временно выбрать ветку `feature/vk-platform-prototype`, затем переключить обратно на `main`.

Для VK preview/non-production deploy command укажите `npx wrangler preview --config wrangler.vk.jsonc`, если используете preview-сборки. Настройте их секреты отдельно согласно выбранным preview settings; production-секреты не следует считать автоматически доступными в preview. Для первого запуска проще использовать один тестовый VK Worker и production URL.

Имя в Cloudflare должно совпадать с `name` выбранного Wrangler-файла. Каталог ассетов отдельно в панели не нужен: он задан в конфигурации. Binding `ASSETS`, класс `RallyRoom`, binding `ROOMS` и миграция SQLite Durable Objects уже описаны. Wrangler создаёт namespace при первом деплое. D1, KV и R2 для этого этапа не нужны.

## 3. Задать runtime-секреты

После создания Worker откройте **Settings → Variables and Secrets** и добавьте типом **Secret**:

| Имя | Значение |
|---|---|
| `VK_APP_SECRET` | Защищённый ключ приложения VK |
| `VK_SERVICE_TOKEN` | Сервисный ключ доступа VK |
| `VK_SESSION_SECRET` | Независимая случайная строка, минимум 32 случайных байта |

Пример генерации последнего секрета локально: `openssl rand -hex 32`.

Это секреты исполняющегося Worker, а не Build variables/secrets. ID приложения задавайте в `wrangler.vk.jsonc`: Wrangler-конфигурация остаётся источником обычных vars при последующих деплоях. Не добавляйте секреты в исходники, JS, URL приложения или логи. Если первый деплой произошёл без секретов, приложение покажет ошибку авторизации — добавьте секреты и повторите запуск.

Альтернатива через CLI (каждая команда интерактивно попросит значение):

```bash
npm ci
npx wrangler login
npx wrangler secret put VK_APP_SECRET --config wrangler.vk.jsonc
npx wrangler secret put VK_SERVICE_TOKEN --config wrangler.vk.jsonc
npx wrangler secret put VK_SESSION_SECRET --config wrangler.vk.jsonc
npm run build:vk
npm run deploy:vk
```

Если Worker ещё не создан, первый `npm run deploy:vk` после сборки создаст его; затем добавьте секреты и повторите деплой. Ничего из этих команд автоматически в вашем аккаунте не выполнялось.

## 4. Указать адрес в VK

После деплоя получите HTTPS URL вида `https://rfm-simulator-vk.<your-subdomain>.workers.dev/` или назначьте custom domain. Укажите этот адрес в настройках URL Mini App для поддерживаемых платформ. Статические файлы и `/api/vk/session` должны находиться на одном origin.

Открывайте приложение через ссылку `https://vk.com/app54809523` под аккаунтом с доступом к тестовому приложению. VK добавляет подписанные параметры запуска; вручную придумывать `vk_user_id` и `sign` нельзя. Прямая ссылка на Worker без параметров не авторизует пользователя.

Не включайте для VK страницы `X-Frame-Options: DENY/SAMEORIGIN` или CSP `frame-ancestors 'self'`: это блокирует встраивание. Текущий шаблон однопоточный и не требует добавлять COOP/COEP для SharedArrayBuffer.

## 5. Проверить первый запуск

1. В desktop VK, VK Android и VK iOS откройте приложение через VK.
2. Дождитесь запуска игры; поле ника должно показывать shortname и не редактироваться.
3. Создайте комнату и подключитесь другим аккаунтом; видимые ники должны соответствовать аккаунтам VK.
4. На телефоне уйдите в фон и вернитесь; проверьте сохранение комнаты через heartbeat.
5. Проверьте, что обычный Worker продолжает работать анонимно и не загружает `vk-bridge.js`.

Если запуск не удался, смотрите статус запроса `/api/vk/session`:

- `503`: не настроен App ID/один из трёх секретов или временная серверная ошибка;
- `401`: неверная подпись, другой App ID, устаревшие/некорректные параметры — откройте заново через VK;
- `502`: VK API недоступен, токен не подходит или не вернул нужный профиль;
- `400`: неправильный формат запроса.

Не пересылайте полный query запуска или session token в отчёте. Ник и ID пользователя попадают в текущую диагностику профиля игры; защищённые ключи и токены в неё не выводятся.

## CI и пределы проверки

Workflow `Platform builds` имеет отдельную проверку авторизации и три параллельные сборочные джобы: standalone, vk, vk-prototype. Каждая проверяет изоляцию артефакта и desktop/mobile обмен в экспортированном WASM. Для standalone/VK дополнительно выполняется `wrangler deploy --dry-run`. Артефакты: `web-standalone`, `web-vk`, `web-vk-prototype`. Деплой делает Cloudflare Builds; GitHub workflow ничего не публикует и не требует production-секретов.

VK browser-тест использует синтетическую подписанную строку, fixture ответа VK API и stub `VKWebAppInit` — при этом проверяются настоящий серверный модуль авторизации, bearer и Godot WASM. Он не заменяет запуск с реальными ключами внутри VK. Остальные игровые/визуальные тесты продолжают пропускаться в этой ветке; вне её действуют прежние правила общего workflow.

Официальные источники:

- [VK: пример проверки подписи запуска](https://github.com/VKCOM/vk-apps-launch-params/blob/master/examples/node.js)
- [VK: схема users.get](https://github.com/VKCOM/vk-api-schema/blob/master/users/methods.json)
- [Cloudflare: Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)
- [Cloudflare: runtime secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare: Static Assets binding](https://developers.cloudflare.com/workers/static-assets/binding/)
