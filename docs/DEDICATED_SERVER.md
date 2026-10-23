# Выделенный сервер комнаты

Выделенный сервер — это обычная Linux- или macOS-сборка игры, запущенная `--headless` на
своём хосте. Она создаёт комнату через тот же Worker и становится её хозяином:
считает СУ, экипажи, мир и машины гостей. Своего игрока у сервера нет, гости
его не видят. Интерфейса тоже нет: друзья заходят в комнату по ID, как к
обычному хозяину. Код режима: `game/scripts/net/dedicated.gd`.

Чем отличается от комнаты игрока:

- Комната не закрывается, когда хозяин уходит или блокирует телефон.
- ID комнаты может быть постоянным (`--room=A1B2C3`).
- Пока в комнате никого нет, день стоит на паузе и сервер почти не тратит CPU.
- Если день начался, а комната пустует `--idle-restart` секунд (по умолчанию 300),
  сервер начинает его заново под тем же ID. После потери связи — тоже.
- Сервер не занимает места: в комнате до `max_players` гостей (8).

Протокол, проверка покупок при входе и лимит снимка 64 КБ те же, что у
комнаты игрока.

## Ключ

Worker создаёт серверную комнату только по заголовку `X-Rally-Dedicated` с
секретом `DEDICATED_TOKEN`. Без заголовка поля `dedicated` и `room` из тела
запроса отбрасываются, с неверным ключом ответ 403.

```bash
openssl rand -hex 32            # новый ключ
npx wrangler secret put DEDICATED_TOKEN
```

На хосте сервера тот же ключ лежит в переменной окружения
`RALLY_DEDICATED_TOKEN` (не в аргументах: их видят все пользователи хоста).

## Запуск

```bash
npm run build:linux
docker build --build-context export=dist-linux -t rally-dedicated server/dedicated
docker run -d --restart=always --name rally-canyon \
  -e RALLY_DEDICATED_TOKEN=… rally-dedicated --stage=3 --room=C0FFEE
docker logs -f rally-canyon     # ROOM_CONNECTED C0FFEE host=true, затем статус раз в минуту
```

Без Docker: `./RallyFansSimulator.x86_64 --headless -- --dedicated --stage=3 --room=C0FFEE`
рядом с `server/dedicated/override.cfg` (без него release-сборка буферизует лог).

| Аргумент | По умолчанию | Что делает |
| --- | --- | --- |
| `--stage=N` | 0 | СУ комнаты (индекс в каталоге) |
| `--room=XXXXXX` | случайный | Постоянный ID: 6 символов 0–9, A–F |
| `--room-server=URL` | production Worker | Другой Worker (локальный, staging) |
| `--name=…` | «Сервер» | Имя хозяина в составе комнаты |
| `--max-fps=N` | 60 | Потолок кадров симуляции |
| `--idle-restart=S` | 300 | Перезапуск пустой комнаты; 0 — никогда |

## Запуск на Mac

Сервером может быть и Mac: серверная macOS-сборка игры, запущенная без окна.
Это отдельное приложение «SERVER Rally Fans Simulator» со своей иконкой
(цвета обычной поменяны местами, `game/branding/rfm-icon-server.svg`), его
легко отличить от игры в Мониторе системы. Пресет экспорта «macOS Server»
включает фичу `dedicated`: с ней сборка сама сбрасывает лог, `override.cfg` ей
не нужен. Скрипт `server/dedicated/run-macos.sh` не даёт Mac уснуть
(`caffeinate`) и поднимает сервер снова, если тот упал.

1. Ключ. Один раз создай его и положи в Worker (нужен `npx wrangler login`):

   ```bash
   openssl rand -hex 32 > ~/.rally-dedicated-token
   chmod 600 ~/.rally-dedicated-token
   npx wrangler secret put DEDICATED_TOKEN < ~/.rally-dedicated-token
   ```

   Скрипт читает ключ из `~/.rally-dedicated-token` или из
   `RALLY_DEDICATED_TOKEN`.
2. Сборка: `npm ci`, затем `npm run build:macos-server` (Godot 4.4.1 в
   `GODOT_BIN`). Получится `dist-macos-server/SERVER Rally Fans Simulator.zip`;
   скрипт сам распакует его рядом. Обычную сборку игры тоже можно запустить
   сервером: `RALLY_APP=путь/к/Rally Fans Simulator.app`, тогда скрипт положит
   в неё `override.cfg`.
3. Запуск, например Чарынский каньон под постоянным ID:

   ```bash
   server/dedicated/run-macos.sh --stage=3 --room=C0FFEE
   ```

   В логе появится `ROOM_CONNECTED C0FFEE host=true`, потом раз в минуту строка
   `[RFM dedicated] room=C0FFEE guests=0 …`. `Ctrl+C` останавливает сервер,
   и гости сразу видят «Комната закрыта»: Worker закрывает комнату, как только
   соединение сервера оборвалось.
   «Неверный ключ сервера» значит, что ключ на Mac не совпадает с секретом
   Worker. Чтобы сервер работал после закрытия терминала, запусти его в
   `tmux` или `screen`.
4. Игроки заходят как к другу: в игре кнопка «ВОЙТИ ПО ID» и ID комнаты
   (`C0FFEE`). Подходит веб-, VK- и нативная сборка той же версии, что и
   сервер. Сам сервер в комнате не виден.

Номера СУ для `--stage`: 0 Лесной перевал, 1 Зимний Турини, 2 Виноградники,
3 Чарынский каньон, 4 Финский лес, 5 Майншафт, 6 Поречье,
7 Асбестовский карьер (`game/data/stages.json`). Несколько комнат — несколько
копий скрипта с разными `--room`, по одному ядру на каждую.

Проверить всё локально, не трогая production: в одном терминале
`npx wrangler dev --local --var DEDICATED_TOKEN:test` (Worker ждёт папку
`dist`, хватит пустой), в другом
`RALLY_DEDICATED_TOKEN=test server/dedicated/run-macos.sh --stage=0 --room=C0FFEE --room-server=http://127.0.0.1:8787`.
Гость — обычная сборка игры (`npm run build:macos`) с окном:
`"dist-macos/Rally Fans Simulator.app/Contents/MacOS/Rally Fans Simulator" -- --room-server=http://127.0.0.1:8787`.

Один контейнер — одна комната: симуляция однопоточная и занимает одно ядро.
Нужны выделенные ядра; общие vCPU дешёвых тарифов дают просадки кадра.
Сервер надо выкатывать вместе с веб-сборкой: гость с другой версией протокола
в комнату не войдёт.

## Проверки

- `node scripts/test-dedicated.mjs`: локальный Worker, сервер с постоянным ID,
  нативный гость входит по ID, едет на симуляции сервера, не видит сервер;
  пустая комната перезапускается под тем же ID; неверный ключ получает 403.
  В CI это джоб «Dedicated server».
- Linux-сборка в CI собирает образ и проверяет, что он стартует.
- `tests/room-core.test.mjs`, `tests/room-socket.test.mjs`: правила Worker.

Прямой WebRTC-канал работает, если в сборку попала библиотека
`native/voice` для linux-x86_64 (так собирает CI). Без неё всё идёт через Worker.
