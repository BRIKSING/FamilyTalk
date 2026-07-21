# FamilyTalk — Техническая документация бэкенда

Этот документ описывает **бэкенд-слой iOS-приложения FamilyTalk** — то есть код,
отвечающий за работу с сетью, хранение данных, авторизацию и обмен данными в
реальном времени. Сюда **не** входят SwiftUI-экраны (`Views/`) и презентационная
логика (`ViewModels/`) — это фронтенд и в этом документе не рассматривается.

Документ ведётся по модулям. Каждый модуль расписывается отдельной темой так,
чтобы разработчику было понятно:

- **что** это за модуль и за что он отвечает;
- **как** он связан с другими модулями;
- **как** его использовать (публичный API и примеры).

---

## Карта модулей бэкенда

Легенда статуса: ✅ — расписано · ⬜ — ещё не расписано.

### Сетевой слой (Networking)

| Статус | Модуль | Файл | Назначение |
|--------|--------|------|------------|
| ✅ | **NetworkService** | `Services/NetworkService.swift` | Базовый HTTP/REST-клиент, транспорт для всех запросов |
| ✅ | **SocketService** | `Services/SocketService.swift` | Обмен событиями в реальном времени поверх Socket.IO |

### Авторизация и безопасность

| Статус | Модуль | Файл | Назначение |
|--------|--------|------|------------|
| ⬜ | **AuthService** | `Services/AuthService.swift` | Авторизация, сессия и восстановление входа |
| ⬜ | **KeychainService** | `Services/KeychainService.swift` | Безопасное хранение токена в Keychain |

### Доменные сервисы (REST API)

| Статус | Модуль | Файл | Назначение |
|--------|--------|------|------------|
| ⬜ | **ChatService** | `Services/ChatService.swift` | Чаты и сообщения (создание, история, редактирование) |
| ⬜ | **ContactsService** | `Services/ContactsService.swift` | Контакты, поиск, блокировки, профиль |
| ⬜ | **CallService** | `Services/CallService.swift` | История звонков |

### Слой данных (Models)

| Статус | Модуль | Файл | Назначение |
|--------|--------|------|------------|
| ⬜ | **Data Models** | `Models/*.swift` | Codable-модели: `User`, `Chat`, `Message`, `CallLog`, `AuthResponse` |

---

## NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`
**Тип:** `final class` · синглтон (`NetworkService.shared`)

### Назначение

`NetworkService` — это **фундамент всего бэкенд-слоя** и единственная точка, через
которую приложение общается с REST API по HTTP. Модуль решает три задачи:

1. **Транспорт.** Формирует `URLRequest` (URL, метод, заголовки, тело) и выполняет
   запрос через `URLSession` с помощью `async/await`.
2. **Авторизация запросов.** Хранит текущий access-токен и автоматически
   добавляет заголовок `Authorization: Bearer <token>` к запросам, которым нужна
   авторизация.
3. **Единообразная обработка ответов.** Проверяет HTTP-статус, декодирует JSON в
   типобезопасную модель `Decodable` и превращает любые сбои в понятную ошибку
   `NetworkError`.

Все доменные сервисы (`AuthService`, `ChatService`, `ContactsService`,
`CallService`) не работают с `URLSession` напрямую — они вызывают
`NetworkService`. Это значит, что единая логика заголовков, таймаутов, разбора
дат и обработки ошибок находится **в одном месте**.

### Связи с другими модулями

```
                        ┌─────────────────────┐
   AuthService ───────► │                     │
   ChatService ───────► │   NetworkService    │ ──► URLSession ──► REST API
   ContactsService ───► │      (.shared)      │
   CallService ───────► │                     │
                        └─────────┬───────────┘
                                  │ 401 Unauthorized
                                  ▼
                    NotificationCenter (.networkUnauthorized)
                                  │
                                  ▼
                          AuthService.logout()
```

- **Потребители (кто вызывает):** `AuthService`, `ChatService`,
  `ContactsService`, `CallService`. Каждый из них хранит ссылку
  `private let network = NetworkService.shared` и вызывает метод `request(...)`.
- **`baseURL`** задаётся здесь (по умолчанию `http://localhost:3000`) и
  переиспользуется `SocketService` как адрес WebSocket-подключения
  (`NetworkService.shared.baseURL`).
- **Токен.** `AuthService` устанавливает токен через `setAccessToken(_:)` после
  логина или восстановления сессии и очищает его через `clearAccessToken()` при
  выходе. Сам `NetworkService` токен нигде не сохраняет на диск — за это отвечает
  `KeychainService`.
- **Событие разавторизации.** При получении HTTP `401` модуль публикует
  нотификацию `Notification.Name.networkUnauthorized`. На неё подписан
  `AuthService`, который в ответ выполняет `logout()`. Так протухший токен
  централизованно приводит к выходу из аккаунта без прямой зависимости между
  сервисами.

### Публичный API

#### Управление токеном

```swift
func setAccessToken(_ token: String)   // установить Bearer-токен для будущих запросов
func clearAccessToken()                // сбросить токен (при logout)
private(set) var accessToken: String?  // текущий токен (только чтение снаружи)
var baseURL: String                    // базовый адрес API (по умолчанию http://localhost:3000)
```

#### Основной метод запроса

```swift
func request<T: Decodable>(
    endpoint: String,                    // путь, например "/chats/\(id)/messages"
    method: String = "GET",              // HTTP-метод: GET/POST/PATCH/DELETE
    queryItems: [URLQueryItem]? = nil,   // query-параметры (?limit=50&cursor=...)
    body: (any Encodable)? = nil,        // тело запроса — кодируется в JSON
    requiresAuth: Bool = true            // добавлять ли заголовок Authorization
) async throws -> T
```

Метод — **дженерик по типу ответа** `T`. Тип возврата выводится из контекста
вызова, поэтому декодирование получается типобезопасным:

```swift
// Тип ответа выводится из аннотации переменной:
let response: AuthResponse = try await network.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false            // логин выполняется без токена
)
```

### Как использовать

**1. GET-запрос с авторизацией (токен добавляется автоматически):**

```swift
let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")
```

**2. GET с query-параметрами:**

```swift
let page: MessagesPage = try await network.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

**3. POST с телом запроса:**

```swift
let chat: Chat = try await network.request(
    endpoint: "/chats",
    method: "POST",
    body: CreateDirectChatRequest(targetUserId: userId)
)
```

**4. Запрос без модели ответа** (когда важен только факт успеха) — заведите
локальную `Codable`-обёртку:

```swift
struct OkResponse: Codable { let ok: Bool }
let _: OkResponse = try await network.request(
    endpoint: "/users/\(id)/block",
    method: "POST"
)
```

### Обработка ошибок

Все сбои приводятся к типизированной ошибке `NetworkError`
(`Error, LocalizedError`), у которой есть человекочитаемое описание на русском
(`errorDescription`):

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | Не удалось собрать `URL` из `baseURL + endpoint` |
| `.invalidResponse` | Ответ не является `HTTPURLResponse` |
| `.unauthorized` | Статус `401` (дополнительно шлётся нотификация `.networkUnauthorized`) |
| `.httpError(statusCode:body:)` | Любой статус вне диапазона `200...299` |
| `.decodingError(Error)` | Тело успешного ответа не разобралось в тип `T` |
| `.unknown(Error)` | Прочие непредвиденные ошибки |

Рекомендуемый шаблон вызова:

```swift
do {
    let user: User = try await network.request(endpoint: "/auth/me")
    // ... использовать user
} catch let error as NetworkError {
    print(error.errorDescription ?? "Ошибка сети")
} catch {
    print(error.localizedDescription)
}
```

### Детали реализации, важные для интеграции

- **Синглтон.** Единственный экземпляр `NetworkService.shared`; `init` приватный.
  Это гарантирует общий токен и общую `URLSession` на всё приложение.
- **Таймаут.** `timeoutIntervalForRequest = 30` секунд на запрос.
- **Content-Type.** Всегда `application/json`; тело кодируется через `JSONEncoder`.
- **Разбор дат.** `JSONDecoder` использует кастомную стратегию, которая понимает
  ISO 8601 **как с дробными долями секунды, так и без них**. Это важно: серверные
  поля `Date` (`createdAt`, `lastSeen`, `editedAt` и т. п.) могут приходить в
  обоих форматах. Точно такая же стратегия продублирована в `SocketService` для
  событий реального времени — при изменении формата дат правьте оба места.
- **Проверка статуса.** Успехом считается диапазон `200...299`; всё остальное —
  ошибка. Статус `401` обрабатывается отдельно (см. выше).

### Точки расширения

- Обновление токена (refresh) сейчас не реализовано: при `401` пользователь
  разлогинивается. Если появится refresh-flow, его логично встроить именно здесь —
  перехватить `401`, обновить токен и повторить запрос.
- Логирование/метрики запросов также уместно добавить в единственный метод
  `request(...)`, не трогая доменные сервисы.

---

## SocketService

**Файл:** `FamilyTalk/Services/SocketService.swift`
**Тип:** `final class`, `@Observable`, `@unchecked Sendable` · синглтон (`SocketService.shared`)
**Зависимость:** библиотека `SocketIO` (socket.io-client-swift)

### Назначение

`SocketService` — это **канал реального времени** приложения. Если
`NetworkService` отвечает за разовые запрос-ответ по HTTP, то `SocketService`
держит **постоянное WebSocket-соединение** с сервером через Socket.IO и
обслуживает два потока событий, где данные приходят сами, без запроса:

1. **Сигналинг звонков (WebRTC).** Обмен offer/answer/ICE-кандидатами и
   командами завершения (`hangup`/`decline`) для установки P2P-звонка. Сам медиапоток
   идёт напрямую между устройствами — через сокет летят только служебные сообщения.
2. **События чата в реальном времени.** Новые сообщения, подтверждения доставки
   (`ack`), отметки о прочтении (`read`) и индикаторы набора текста (`typing`).

Модуль работает как **двунаправленный мост**:

- **Server → Client (входящие):** обработчики в `setupHandlers()` разбирают
  входящие события и публикуют их в наблюдаемые (`@Observable`) свойства. UI
  подписан на эти свойства через `.onChange(of:)` и реагирует на изменения.
- **Client → Server (исходящие):** методы группы `send…` сериализуют аргументы в
  словарь и отправляют его через сокет (`emit` / `emitWithAck`).

### Связи с другими модулями

```
                     token (после login/restore)
   AuthService ──────────────────────────────────►  connect(token:)
   AuthService ──────── logout() ─────────────────►  disconnect()
                                                          │
                                     ┌────────────────────┴─────────────────────┐
                                     │              SocketService                │
                                     │                (.shared)                  │
   Client → Server:                  │   emit / emitWithAck                      │   Server → Client:
   CallViewModel  ── sendOffer ─────►│ ◄──── URL = NetworkService.shared.baseURL │──► incomingCall/answeredCall/…
                     sendAnswer …    │        (WebSocket поверх Socket.IO)       │──► newMessage/messageAck/…
   ChatViewModel  ── sendMessage ───►│                                          │──► typingStart/typingStop
                     sendRead/typing │                                          │
                                     └───────────────────────────────────────────┘
                                                          │ @Observable свойства
                                                          ▼
                        Views (ChatView, ChatsListView, CallView, ContactsView)
                              .onChange(of: SocketService.shared.<event>)
```

- **Управление жизненным циклом — `AuthService`.** Соединение поднимается **не**
  здесь, а в `AuthService`: после успешного логина или восстановления сессии
  вызывается `connect(token:)`, а при `logout()` — `disconnect()`. `SocketService`
  сам токен нигде не хранит — получает его аргументом.
- **Адрес подключения — из `NetworkService`.** `connect(token:)` берёт
  `NetworkService.shared.baseURL` как URL WebSocket-сервера. То есть REST и
  WebSocket ходят на **один и тот же хост**; менять адрес нужно в одном месте — в
  `NetworkService`.
- **Разбор дат продублирован с `NetworkService`.** Приватный `static let decoder`
  использует ту же кастомную стратегию ISO 8601 (с дробными долями секунды и без),
  что и `NetworkService`. При изменении формата дат правьте **оба** места.
- **Потребители исходящих методов:**
  - `CallViewModel` → `sendOffer`, `sendAnswer`, `sendIceCandidate`, `sendHangup`,
    `sendDecline`;
  - `ChatViewModel` → `sendMessage`, `sendRead`, `sendTypingStart`, `sendTypingStop`.
- **Потребители входящих событий (UI):** `CallView`, `ContactsView` (звонки),
  `ChatView`, `ChatsListView` (сообщения/typing) подписываются на свойства через
  `.onChange(of:)`.
- **`CallService`** (REST, история звонков) **не** участвует в сигналинге — offer/
  answer/hangup идут только через `SocketService`.

### Модели событий (payloads)

Входящие события представлены отдельными `Equatable`-структурами — это
типобезопасная «граница» между сырыми словарями сокета и остальным приложением:

| Структура | Событие сервера | Поля |
|-----------|-----------------|------|
| `IncomingCallEvent` | `call:incoming` | `callId`, `initiatorId`, `type: CallType`, `sdp` |
| `CallAnsweredEvent` | `call:answered` | `callId`, `sdp` |
| `IceCandidateEvent` | `call:ice-candidate` | `callId`, `fromUserId`, `candidate`, `sdpMid?`, `sdpMLineIndex?`, `usernameFragment?` |
| `CallHangupEvent` | `call:hangup` / `call:declined` | `callId` |
| `NewMessageEvent` | `message:new` | `message: Message` (+ вычисляемое `chatId`) |
| `MessageAckEvent` | `message:ack` | `messageId`, `chatId` |
| `MessageReadEvent` | `message:read` | `chatId`, `messageId`, `userId`, `readAt: Date` |
| `TypingEvent` | `typing:start` / `typing:stop` | `chatId`, `userId` |

### Публичный API

#### Соединение

```swift
private(set) var isConnected: Bool          // текущее состояние подключения
func connect(token: String)                 // поднять WebSocket (вызывает AuthService)
func disconnect()                           // разорвать соединение (вызывает AuthService при logout)
```

`connect` настраивает `SocketManager` c авто-переподключением (`reconnects(true)`,
бесконечные попытки `reconnectAttempts(-1)`, пауза `reconnectWait(2)`),
принудительным WebSocket-транспортом и заголовком `Authorization: Bearer <token>`.

#### Наблюдаемые события (Server → Client)

Каждое свойство — «почтовый ящик» последнего события. UI читает его в `.onChange`
и **сбрасывает в `nil`** после обработки, чтобы не обработать одно событие дважды:

```swift
// Звонки:
var incomingCall:  IncomingCallEvent?
var answeredCall:  CallAnsweredEvent?
var iceCandidate:  IceCandidateEvent?
var remoteHangup:  CallHangupEvent?
var remoteDeclined: CallHangupEvent?

// Чат:
var newMessage:  NewMessageEvent?
var messageAck:  MessageAckEvent?
var messageRead: MessageReadEvent?
var typingStart: TypingEvent?
var typingStop:  TypingEvent?
```

#### Исходящие методы — звонки (Client → Server)

```swift
func sendOffer(targetUserId: String, sdp: String, type: CallType)
func sendAnswer(callId: String, targetUserId: String, sdp: String)
func sendIceCandidate(callId: String, targetUserId: String, candidate: String,
                      sdpMid: String?, sdpMLineIndex: Int?, usernameFragment: String?)
func sendHangup(callId: String, targetUserId: String)
func sendDecline(callId: String, targetUserId: String)
```

#### Исходящие методы — чат (Client → Server)

```swift
// Отправка сообщения с подтверждением сервера (Socket.IO ack, таймаут 5 c).
// completion(true) — сервер принял; completion(false) — нет соединения или таймаут.
func sendMessage(chatId: String, content: String, replyToId: String? = nil,
                 completion: ((Bool) -> Void)? = nil)

func sendRead(chatId: String, messageId: String)
func sendTypingStart(chatId: String)
func sendTypingStop(chatId: String)
```

### Как использовать

**1. Поднять/разорвать соединение (обычно этим занимается только `AuthService`):**

```swift
SocketService.shared.connect(token: response.accessToken)   // после логина
SocketService.shared.disconnect()                           // при выходе
```

**2. Отправить сообщение и отреагировать на подтверждение (оптимистичный UI):**

```swift
SocketService.shared.sendMessage(chatId: chat.id, content: text) { success in
    if success {
        // пометить локальное сообщение как доставленное
    } else {
        // показать статус ошибки/повторной отправки
    }
}
```

**3. Подписаться на входящее событие в SwiftUI и сбросить его после обработки:**

```swift
.onChange(of: SocketService.shared.newMessage) { _, event in
    guard let event else { return }
    viewModel.append(event.message)
    SocketService.shared.newMessage = nil   // важно: сброс, чтобы не обработать повторно
}
```

**4. Индикатор набора текста:**

```swift
SocketService.shared.sendTypingStart(chatId: chat.id)   // пользователь начал печатать
SocketService.shared.sendTypingStop(chatId: chat.id)    // остановился/отправил
```

### Детали реализации, важные для интеграции

- **Потокобезопасность.** Класс помечен `@unchecked Sendable`, потому что
  `socket.io-client-swift` не поддерживает Swift 6 Sendable. Инвариант держится
  вручную: **все мутации наблюдаемых свойств выполняются на `DispatchQueue.main`**.
  Обработчики сокета приходят с фонового потока и всегда переключаются на главный.
- **`@ObservationIgnored`.** Служебные объекты (`manager`, `socket`, `decoder`)
  исключены из наблюдения `@Observable` — на них UI не подписывается.
- **Модель «событие → свойство → сброс в nil».** Свойства хранят *последнее*
  событие. Ответственность за сброс (`= nil`) лежит на UI после обработки. Если не
  сбрасывать — событие может «залипнуть» и обработаться повторно при следующем
  изменении.
- **Гварды на соединение.** Приватный `emit(...)` и `sendMessage(...)` проверяют
  `isConnected`: без активного соединения событие не отправляется (а `sendMessage`
  сразу вызывает `completion(false)`).
- **`emitWithAck` только для `sendMessage`.** Только отправка сообщения ждёт
  подтверждения сервера (таймаут 5 c). Остальные `send…` — «выстрелил и забыл».
- **Разбор `candidate`.** Для `call:ice-candidate` вложенный словарь `candidate`
  разбирается вручную (строка + опциональные `sdpMid`/`sdpMLineIndex`/
  `usernameFragment`).

### Точки расширения

- **Единая обёртка события.** Сейчас каждый обработчик руками достаёт поля из
  словаря. При росте числа событий можно ввести общий типобезопасный декодер
  (по аналогии с `decode(_:from:)`, который уже используется для `message:new`).
- **Реконнект и восстановление состояния.** Авто-переподключение включено на
  уровне транспорта, но прикладного «догона» пропущенных событий после
  переподключения нет — при необходимости это добавляется здесь.
- **Наблюдаемость.** Логирование сейчас отключено (`.log(false)`); диагностику
  соединения/событий логично включать/собирать в `setupHandlers()`.
