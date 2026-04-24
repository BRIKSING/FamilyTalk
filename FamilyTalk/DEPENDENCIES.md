# Swift Package Dependencies

## Добавление Socket.io Client

### Через Xcode:

1. File → Add Package Dependencies...
2. Введите URL: `https://github.com/socketio/socket.io-client-swift.git`
3. Version: `16.1.0` или выше
4. Add to Target: **FamilyTalk**

### Через Package.swift (если используется):

```swift
dependencies: [
    .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.1.0")
]
```

---

## Структура Socket.io событий для ADMessenger

Основываясь на типичной архитектуре мессенджера:

### События авторизации:
- `authenticate` (client → server) — авторизация с JWT
- `authenticated` (server → client) — подтверждение авторизации

### События присутствия:
- `user:online` (server → client) — пользователь онлайн
- `user:offline` (server → client) — пользователь оффлайн

### События сообщений:
- `message:send` (client → server) — отправка сообщения
- `message:new` (server → client) — новое сообщение
- `message:delivered` (server → client) — доставлено
- `message:read` (client → server) — прочитано
- `typing:start` / `typing:stop` (client ↔ server)

### События звонков (WebRTC signaling):
- `call:init` (client → server) — инициация звонка
- `call:offer` (server → client) — SDP offer
- `call:answer` (client → server) — SDP answer
- `call:ice-candidate` (client ↔ server) — ICE candidates
- `call:reject` (client → server) — отклонить звонок
- `call:end` (client → server) — завершить звонок
- `call:incoming` (server → client) — входящий звонок
- `call:accepted` (server → client) — звонок принят
- `call:ended` (server → client) — звонок завершён

---

После добавления пакета перезапустите Xcode.
