# P2PRooms: комнаты и прямой WebRTC для Godot 4

Сетевая прослойка из Rally Fans Simulator, вынесенная для других игр. Она работает
на том же сервере комнат (Cloudflare Worker + Durable Objects), что и ралли, по
тому же контракту.

Схема такая. Сервер только знает, кто в комнате, и пересылает настройку WebRTC
(offer, answer, ICE-кандидаты) через WebSocket комнаты. Вся игра идёт напрямую
между игроками по WebRTC data channel. Топология звезда: каждый гость связан с
хостом, хост со всеми. Гость отправляет пакеты хосту, хост рассылает их гостям.

У каждой связи два канала:

| Канал | Свойства | Для чего |
| --- | --- | --- |
| `reliable` | упорядоченный, с повторами | чат, команды, события, начальное состояние |
| `fast` | без порядка и без повторов | позиции, ввод: потерянный пакет заменяет следующий |

## Установка

1. Скопируйте `addons/p2p_rooms/` в свой проект. Класс `P2PRooms` появится сам
   (`class_name`), плагин включать не нужно.
2. Для десктопа и мобильных установите официальное расширение
   [webrtc-native](https://github.com/godotengine/webrtc-native/releases)
   (проверено с 1.1.0): распакуйте архив так, чтобы получилось
   `res://webrtc/webrtc.gdextension`. В веб-сборке WebRTC даёт браузер, ничего ставить не нужно.
3. Godot 4.4 (с 4.2+ тоже должно работать, проверено на 4.4.1).

## Быстрый старт

```gdscript
var rooms := P2PRooms.new()

func _ready() -> void:
	add_child(rooms)                    # до create_room()/join_room()
	rooms.app_protocol = 1_000_001      # номер вашей игры, см. ниже
	rooms.room_joined.connect(_on_joined)
	rooms.peer_connected.connect(_on_peer)
	rooms.message_received.connect(_on_message)
	rooms.room_failed.connect(func(error, status): print("Не вошёл: ", status, " ", error))
	rooms.room_closed.connect(func(reason): print("Комната закрыта: ", reason))

func host() -> void:
	rooms.create_room("Вася")

func join(id: String) -> void:
	rooms.join_room(id, "Петя")

func _on_joined(room_id: String, me: String, is_host: bool) -> void:
	print("Комната ", room_id)          # этот ID хост показывает друзьям

func _on_peer(peer_id: String) -> void:
	if rooms.is_host:
		rooms.send(peer_id, {"type": "welcome", "map": "forest"})

func _physics_process(_delta: float) -> void:
	if not rooms.is_host and rooms.is_peer_connected(rooms.host_id):
		rooms.send_to_host({"pos": $Player.position}, false)   # по fast

func _on_message(from: String, data, reliable: bool) -> void:
	print(from, " -> ", data)
```

Полный пример с лобби и чатом лежит в `example/lobby.gd`, это главная сцена этого проекта.

## API

### Настройки (`@export`)

| Свойство | По умолчанию | Что это |
| --- | --- | --- |
| `server_url` | `https://rally-fans-simulator.di-719.workers.dev` | Адрес сервера комнат, без `/` в конце |
| `app_protocol` | `1000001` | Номер протокола вашей игры. Войти можно только в комнату с тем же номером. Берите число от 1 000 000 и выше (ралли использует маленькие номера) и увеличивайте его, когда пакеты меняются несовместимо |
| `ice_servers` | STUN Cloudflare и Google | STUN/TURN для WebRTC |
| `membership_interval` | `1.0` | Как часто (сек) игрок отмечается на сервере |
| `connect_timeout` | `8.0` | Сколько секунд ждать открытия связи до повтора |
| `max_attempts`, `retry_delay` | `3`, `2.0` | Повторы связи гостя с хостом. После `max_attempts` неудач подряд пауза `retry_delay * 5` |
| `reconnect_window` | `45.0` | Сколько секунд переподключать сокет комнаты, прежде чем `room_closed` |
| `max_packet` | `16000` | Максимальный размер пакета в `send()`, байт |
| `connection_factory` | пусто | `Callable`, который возвращает объект с API `WebRTCPeerConnection`. Нужен для тестов или своего нативного бэкенда |

### Методы

| Метод | Что делает |
| --- | --- |
| `create_room(name)` | Создаёт комнату, вы становитесь хостом. Результат придёт сигналом `room_joined` или `room_failed` |
| `join_room(room_id, name)` | Входит в комнату по 6-символьному ID (`0-9A-F`, регистр не важен) |
| `leave_room()` | Выходит. Если выходит хост, комната закрывается у всех. `room_closed` не приходит |
| `send(peer_id, data, reliable = true) -> bool` | Шлёт любой Variant без объектов (`var_to_bytes`). `false`, если связь не открыта или пакет больше `max_packet` |
| `send_bytes(peer_id, bytes, reliable = true) -> bool` | Шлёт сырые байты. Получатель увидит `PackedByteArray` |
| `send_to_host(data, reliable = true) -> bool` | Для гостя: `send(host_id, ...)` |
| `broadcast(data, reliable = true)` | Во все открытые связи: хост шлёт всем гостям, гость хосту |
| `connected_peers() -> Array` | ID игроков с открытой связью |
| `is_peer_connected(peer_id) -> bool` | Открыта ли связь с игроком |
| `webrtc_available() -> bool` | Есть ли WebRTC в этой сборке. `create_room` и `join_room` сами проверяют и сообщают через `room_failed` |
| `server_time() -> float` | Часы сервера (Unix, сек) для общих таймеров |

### Свойства состояния (только чтение)

`room_id`, `player_id`, `host_id`, `is_host`, `joined`, `members`
(словарь `id -> {id, name, slot, host}`), `server_time_offset`.

### Сигналы

| Сигнал | Когда |
| --- | --- |
| `room_joined(room_id, player_id, is_host)` | Сокет комнаты открыт, вы в комнате |
| `room_failed(error, status)` | Создать или войти не вышло. `status` это HTTP-код: `404` нет комнаты, `409` комната полна или другой `app_protocol`, `429` слишком часто, `0` нет сети или WebRTC |
| `room_closed(reason)` | Комнаты больше нет: хост вышел, вас забыли или сервер недоступен дольше `reconnect_window` |
| `members_changed(members)` | Изменился состав. `members` это массив `{id, name, slot, host}` по порядку `slot` |
| `peer_connected(peer_id)` | Открылась прямая связь (у гостя только с хостом) |
| `peer_disconnected(peer_id)` | Связь закрылась. Гость сам переподключится, пока хост в комнате |
| `message_received(peer_id, data, reliable)` | Пришёл пакет. `reliable` показывает, по какому каналу |

### Что важно знать

- Гости не видят друг друга напрямую. Чтобы гость A узнал о госте B, хост
  пересылает. Отправителя хост берёт из `peer_id` связи, а не из пакета.
- Хост главный. Если он выходит или пропадает дольше 90 секунд, комната закрывается.
- До 8 игроков в комнате, включая хоста.
- Узел должен быть в дереве сцены до `create_room()` и `join_room()`.
- TURN нет. Игроки за строгим NAT (часть мобильных сетей, корпоративные сети)
  не свяжутся, сработает `peer_disconnected` и повторы. Можно добавить свой TURN в `ice_servers`.
- Веб-сборка работает только с того же домена, что и сервер: Worker отклоняет
  запросы с чужим `Origin` (403). Нативные сборки это не затрагивает.
- Ошибки сервера приходят по-русски, это тексты из ралли.

## Протокол сервера

Это нужно, только если вы пишете клиент не на Godot. Аддон делает всё это сам.

### HTTP

Все запросы `POST`, тело JSON, ответ JSON. Ошибка выглядит как `{"error": "текст"}` с HTTP-кодом.

| Запрос | Тело | Ответ |
| --- | --- | --- |
| `/api/rooms` | `{"name": "Вася", "protocol": 1000001}` | `{"room": "A1B2C3", "player", "token", "host": true, "slot", "socket": "wss://…/api/rooms/A1B2C3/socket"}` |
| `/api/rooms/<ID>/join` | `{"name": "Петя", "protocol": 1000001}` | `{"player", "token", "host": false, "slot", "socket"}` |
| `/api/rooms/<ID>/leave` | `{"token"}` | `{"left": true}` |

В ответах есть и поля ралли (`car_model`, `character`, `stage`), их можно не читать.

### WebSocket `socket`

Клиент → сервер:

```json
{"type": "hello", "id": 1, "token": "…"}
{"type": "sync", "id": 2, "state": {"pos": [0,0,0], "car": [0,0,0], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false}}
{"type": "signal", "to": "<player id>", "data": {"kind": "offer|answer|candidate", "session": 123, "sdp": "…", "media": "0", "index": 0, "name": "candidate:…"}}
```

- `hello` первым сообщением, не позже 10 секунд после подключения.
- `sync` раз в секунду: это отметка «я ещё здесь» и способ получить состав
  комнаты. Поле `state` обязательно в этом виде, его требует сервер ралли.
- `signal` сервер пересылает только между хостом и гостем этой комнаты. `data`
  он не разбирает, лимит 16 КБ.

Сервер → клиент:

```json
{"type": "hello", "id": 1, "player": "<ваш id>"}
{"type": "reply", "id": 2, "server_time": 1731240000000, "host": "<id хоста>", "players": [{"id", "name", "slot", …}], …}
{"type": "push", …то же, что reply, без id…}
{"type": "signal", "from": "<id>", "data": {…}}
{"type": "signal_error", "status": 404, "error": "…"}
{"type": "error", "id": 2, "status": 410, "error": "…"}
```

`push` приходит гостям сразу после `sync` хоста, а хосту после `sync` гостя.
Ошибки `401`, `404` и `410` значат, что комнаты для вас больше нет: сервер
закрывает сокет с кодом `4000 + status`.

### WebRTC

Гость создаёт offer для хоста. Обе стороны заранее создают два negotiated-канала
с одинаковыми параметрами:
`{"negotiated": true, "id": 1, "ordered": true}` (reliable) и
`{"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0}` (fast).
Первый байт каждого пакета: `0` значит дальше `var_to_bytes()`, `1` значит сырые байты.

### Лимиты

| Что | Лимит |
| --- | --- |
| Создание и вход в комнаты | 30 в минуту с одного IP |
| Все запросы к API | 6000 в минуту с одного IP |
| `sync` | 150 за 10 секунд на игрока |
| `signal` | 120 за 10 секунд на игрока, 16 КБ каждый |
| Сообщение в сокет | 64 КБ |
| Игроков в комнате | 8 |
| Тишина до исключения | 90 секунд, для хоста это закрытие комнаты |

## Проверка

`tests/run-e2e.mjs` из корня репозитория `rfm-simulator` поднимает `wrangler dev`,
запускает хоста и гостя в headless Godot с webrtc-native и гоняет пакеты по обоим
каналам:

```sh
npm ci
node libs/godot-p2p-rooms/tests/run-e2e.mjs
```

Контракт сервера, на который опирается аддон, проверяет
`tests/p2p-rooms-contract.test.mjs` в CI ралли, так что изменение сервера,
которое его сломает, будет видно сразу.

## Лицензия

MIT, как и Rally Fans Simulator.
