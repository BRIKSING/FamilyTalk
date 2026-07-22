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
| ✅ | **AuthService** | `Services/AuthService.swift` | Авторизация, сессия и восстановление входа |
| ✅ | **KeychainService** | `Services/KeychainService.swift` | Безопасное хранение токена в Keychain |

### Доменные сервисы (REST API)

| Статус | Модуль | Файл | Назначение |
|--------|--------|------|------------|
| ✅ | **ChatService** | `Services/ChatService.swift` | Чаты и сообщения (создание, история, редактирование) |
| ✅ | **ContactsService** | `Services/ContactsService.swift` | Контакты, поиск, блокировки, профиль |
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

---

## AuthService

**Файл:** `FamilyTalk/Services/AuthService.swift`
**Тип:** `final class`, `@Observable` · синглтон (`AuthService.shared`)

### Назначение

`AuthService` — это **центр управления сессией пользователя**. Модуль отвечает за
полный жизненный цикл авторизации и является единственным местом, где сходятся
все связанные с входом операции:

1. **Вход.** Выполняет `POST /auth/login`, получает access-токен и профиль
   пользователя.
2. **Хранение сессии.** Сохраняет токен в Keychain, а профиль — в `UserDefaults`,
   чтобы при следующем запуске приложения не заставлять пользователя логиниться
   заново.
3. **Восстановление сессии.** При старте приложения (в `init`) поднимает
   сохранённую сессию: подставляет токен в `NetworkService` и переподключает сокет.
4. **Выход.** Централизованно очищает токен, профиль, состояние и рвёт
   WebSocket-соединение — как по инициативе пользователя, так и автоматически при
   протухшем токене.

`AuthService` держит два наблюдаемых (`@Observable`) свойства состояния, на которые
опирается весь UI, чтобы решить, показывать экран входа или основной интерфейс:

```swift
private(set) var currentUser: User?        // текущий профиль (nil, если не авторизован)
private(set) var isAuthenticated: Bool     // флаг «пользователь вошёл»
```

### Связи с другими модулями

`AuthService` — это **дирижёр** для трёх других бэкенд-модулей. Он ничего не
делает с сетью или хранилищем сам, а координирует их:

```
                          ┌──────────────────────────────┐
                          │          AuthService          │
                          │            (.shared)          │
                          └───────────────┬───────────────┘
          save/load/delete "access_token" │
                    ┌───────────────┬──────┴───────┬────────────────────┐
                    ▼               ▼               ▼                    ▼
            KeychainService   NetworkService   SocketService        UserDefaults
             (токен на диск)  (Bearer-токен)  connect/disconnect   (профиль User)
                                    ▲
                                    │ Notification .networkUnauthorized (HTTP 401)
                                    └──────────────► logout()  (автоматический выход)
```

- **`KeychainService`** — безопасное хранилище токена. `AuthService` вызывает
  `save`/`load`/`delete` по ключу `"access_token"`. Только `AuthService` знает про
  этот ключ; остальные модули токен через Keychain не трогают.
- **`NetworkService`** — получает токен через `setAccessToken(_:)` при входе и
  восстановлении, теряет через `clearAccessToken()` при выходе. Именно так все
  доменные REST-сервисы начинают/перестают ходить с авторизацией.
- **`SocketService`** — управляется отсюда: `connect(token:)` вызывается после
  входа и при восстановлении сессии, `disconnect()` — при выходе. Сам сокет токен
  не хранит и время жизни соединения не решает — это ответственность `AuthService`.
- **`UserDefaults`** — кэш профиля `User` (ключ `"current_user"`) в виде JSON.
  Позволяет мгновенно показать пользователя при холодном старте, не дожидаясь сети.
- **Обратная связь по `401`.** В `init` модуль подписывается на нотификацию
  `Notification.Name.networkUnauthorized`, которую публикует `NetworkService` при
  HTTP `401`. Обработчик выполняет `logout()` на главном потоке. Так протухший
  токен приводит к выходу без прямой зависимости `NetworkService → AuthService`.
- **Модели `AuthResponse` / `LoginRequest`** (`Models/AuthResponse.swift`) —
  контракт эндпоинта `/auth/login`: тело запроса и структура ответа
  (`accessToken` + `user`).
- **Потребитель (фронтенд).** `AuthViewModel` вызывает `login`/`logout`/`fetchMe`
  и наблюдает `isAuthenticated` — но это уже презентационный слой и в этом
  документе не рассматривается.

### Публичный API

```swift
static let shared: AuthService              // единственный экземпляр

private(set) var currentUser: User?         // профиль (nil, если не вошёл)
private(set) var isAuthenticated: Bool      // вошёл ли пользователь

// POST /auth/login → сохраняет сессию, поднимает сокет, возвращает профиль
func login(phone: String, displayName: String) async throws -> User

// GET /auth/me → обновляет currentUser актуальными данными с сервера
func fetchMe() async throws -> User

// Полный выход: чистит токен, профиль, состояние и рвёт сокет
@MainActor func logout()
```

Приватные `saveSession(_:)`, `restoreSession()` — внутренняя механика хранения и
восстановления, снаружи недоступны.

### Как использовать

**1. Вход по телефону и отображаемому имени:**

```swift
do {
    let user = try await AuthService.shared.login(
        phone: "+79991234567",
        displayName: "Дмитрий"
    )
    // сессия уже сохранена, сокет поднят — можно переходить в приложение
} catch let error as NetworkError {
    print(error.errorDescription ?? "Ошибка входа")
}
```

**2. Обновить профиль текущего пользователя:**

```swift
let fresh = try await AuthService.shared.fetchMe()   // GET /auth/me
```

**3. Выйти из аккаунта:**

```swift
await MainActor.run { AuthService.shared.logout() }
```

**4. Реагировать на состояние авторизации в UI (через `@Observable`):**

```swift
if AuthService.shared.isAuthenticated {
    MainTabView()
} else {
    AuthView()
}
```

### Детали реализации, важные для интеграции

- **Восстановление в `init`.** `restoreSession()` вызывается в приватном `init`
  синглтона. Он поднимает сессию **только** если в Keychain есть токен, а в
  `UserDefaults` — декодируемый профиль; иначе тихо остаётся в разлогиненном
  состоянии. Из этого следует: первое обращение к `AuthService.shared` уже
  проставляет `isAuthenticated` и переподключает сокет.
- **Порядок при входе (`saveSession`).** Строго: сохранить токен в Keychain →
  отдать токен в `NetworkService` → закэшировать профиль в `UserDefaults` →
  выставить `currentUser`/`isAuthenticated` → поднять сокет. Тот же порядок
  повторяется в `restoreSession()` (без записи, только чтение).
- **Порядок при выходе (`logout`).** Удалить токен из Keychain → убрать профиль из
  `UserDefaults` → очистить токен в `NetworkService` → `disconnect()` сокета →
  обнулить `currentUser`/`isAuthenticated`. Метод помечен `@MainActor`, так как
  меняет наблюдаемое состояние.
- **Потокобезопасность.** Мутации состояния и запись сессии выполняются на главном
  потоке: сетевые методы `login`/`fetchMe` асинхронны, но обновление свойств
  завёрнуто в `await MainActor.run { ... }`. Обработчик `.networkUnauthorized`
  также перекидывает `logout()` на `@MainActor`.
- **`login` не требует токена.** Запрос идёт с `requiresAuth: false` — на момент
  входа токена ещё нет.
- **Отписка от нотификации.** Ссылка на наблюдателя хранится в
  `unauthorizedObserver`; так как это синглтон на всё время жизни приложения,
  явного удаления наблюдателя нет.

### Точки расширения

- **Refresh-токен.** Сейчас единственный access-токен; при `401` — полный выход.
  Если появится refresh-flow, `saveSession`/`restoreSession` и обработчик `401` —
  правильное место, чтобы хранить второй токен и продлевать сессию, не разлогинивая
  пользователя.
- **Хранение профиля.** Профиль лежит в `UserDefaults` как JSON. При росте объёма
  или требований к безопасности его можно перенести в Keychain или локальную БД,
  не меняя публичный API.
- **Мультиаккаунт.** Ключи (`"access_token"`, `"current_user"`) сейчас фиксированы;
  для нескольких аккаунтов их логично параметризовать идентификатором пользователя.

---

## KeychainService

**Файл:** `FamilyTalk/Services/KeychainService.swift`
**Тип:** `final class` · синглтон (`KeychainService.shared`)
**Зависимость:** системный фреймворк `Security` (Keychain Services API)

### Назначение

`KeychainService` — это **тонкая обёртка над системным Keychain iOS/macOS** для
безопасного хранения секретов в виде пар «ключ → строка». В отличие от
`UserDefaults`, данные Keychain шифруются системой и защищены на уровне ОС,
поэтому именно сюда кладётся **access-токен** пользователя.

Модуль сознательно **минималистичен**: он не знает про бизнес-логику, токены или
профили. Его API — три операции над строковыми значениями:

1. **`save`** — записать строку по ключу (перезаписывая существующую).
2. **`load`** — прочитать строку по ключу (или `nil`, если её нет).
3. **`delete`** — удалить значение по ключу.

Все записи создаются с классом `kSecClassGenericPassword` и общим атрибутом
сервиса `kSecAttrService = "FamilyTalk"`, а роль конкретного «имени поля» играет
`kSecAttrAccount` (это и есть переданный `key`). Такая пара
`(service, account)` однозначно адресует запись в Keychain.

### Связи с другими модулями

```
        save/load/delete "access_token"
   AuthService ───────────────────────────►  KeychainService
     (.shared)                                   (.shared)
                                                    │
                                                    ▼
                                       Security.framework (Keychain)
                                        kSecClassGenericPassword
                                        service = "FamilyTalk"
                                        account = <key>
```

- **Единственный потребитель — `AuthService`.** Только он обращается к
  `KeychainService`, и только по ключу `"access_token"`:
  - при входе/сохранении сессии — `save(key: "access_token", value: token)`;
  - при восстановлении сессии в `init` — `load(key: "access_token")`;
  - при выходе (`logout`) — `delete(key: "access_token")`.
- **Ключ знает только `AuthService`.** `KeychainService` не хранит и не «понимает»
  ключей — он оперирует любой строкой. Знание о том, что токен лежит под
  `"access_token"`, инкапсулировано в `AuthService`; остальные модули к Keychain не
  обращаются вовсе.
- **Отношение к `NetworkService`/`SocketService`.** Эти модули получают токен как
  значение (через `setAccessToken(_:)` / `connect(token:)`) и **не читают** его из
  Keychain напрямую. Единственный «мост» между защищённым хранилищем и рантайм-
  токеном — `AuthService`.

### Публичный API

```swift
static let shared: KeychainService              // единственный экземпляр

func save(key: String, value: String)           // записать/перезаписать строку
func load(key: String) -> String?               // прочитать строку (nil, если нет)
func delete(key: String)                         // удалить запись
```

Всё, что нужно для интеграции, — это три метода выше. Атрибут сервиса
(`"FamilyTalk"`) и класс записи заданы внутри и снаружи не настраиваются.

### Как использовать

**1. Сохранить секрет (например, токен после логина):**

```swift
KeychainService.shared.save(key: "access_token", value: response.accessToken)
```

**2. Прочитать секрет при старте приложения:**

```swift
if let token = KeychainService.shared.load(key: "access_token") {
    NetworkService.shared.setAccessToken(token)   // сессию можно восстановить
} else {
    // токена нет — показываем экран входа
}
```

**3. Удалить секрет при выходе:**

```swift
KeychainService.shared.delete(key: "access_token")
```

### Детали реализации, важные для интеграции

- **`save` = «upsert».** Перед добавлением метод всегда вызывает `SecItemDelete`
  по той же паре `(service, account)`, а затем `SecItemAdd`. Это устраняет ошибку
  `errSecDuplicateItem`: повторный `save` по существующему ключу спокойно
  перезаписывает значение, а не падает.
- **Хранятся только UTF-8 строки.** Значение кодируется через
  `value.data(using: .utf8)`; при чтении данные декодируются обратно в `String`.
  Для бинарных данных модуль в текущем виде не предназначен.
- **Молчаливая обработка ошибок.** `save`/`delete` **не** возвращают статус, а
  `load` возвращает `nil` при любой неудаче (нет записи, ошибка Keychain, битые
  данные). Коды возврата `OSStatus` от `SecItem*` не пробрасываются наружу — API
  сознательно «best-effort». Для сценариев, где важно отличать «нет значения» от
  «ошибка доступа», этого недостаточно (см. точки расширения).
- **Область видимости записи.** Атрибут доступности (`kSecAttrAccessible`) явно не
  задан, поэтому применяется системное значение по умолчанию. Записи привязаны к
  сервису `"FamilyTalk"` и не конфликтуют с чужими Keychain-элементами.
- **Синглтон без состояния.** У класса нет изменяемых полей — он безопасен для
  вызова из любого места; вся синхронизация обеспечивается самим Keychain Services.

### Точки расширения

- **Проброс ошибок.** Сейчас операции «глотают» `OSStatus`. При необходимости
  диагностики (например, различать пустой Keychain и отказ доступа) методы можно
  сделать `throws` или возвращать `Result`, не меняя вызовы в `AuthService`
  радикально.
- **Политика доступности.** Для контроля, когда токен доступен (только после
  разблокировки устройства, без синхронизации в iCloud и т. п.), стоит явно задать
  `kSecAttrAccessible` — например, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **Хранение не-строковых секретов.** Если появится потребность хранить бинарные
  данные или структуры (ключи шифрования, refresh-токен в составе объекта), обёртку
  можно расширить перегрузками для `Data`/`Codable`.
- **Биометрия.** Доступ к особо чувствительным записям можно защитить
  `SecAccessControl` (Face ID / Touch ID), задав его в query при `save`.

---

## ChatService

**Файл:** `FamilyTalk/Services/ChatService.swift`
**Тип:** `final class` · синглтон (`ChatService.shared`)
**Зависимость:** `NetworkService.shared` (весь транспорт идёт через него)

### Назначение

`ChatService` — это **доменный REST-сервис чатов и сообщений**. Он инкапсулирует
все «разовые» (request-response) операции с чатами поверх HTTP: получить список
чатов, создать личный или групповой чат, подгрузить историю сообщений
постранично, отредактировать и удалить сообщение.

Ключевая граница ответственности: **`ChatService` отвечает за REST, а не за
реальное время.** Отправка нового сообщения, подтверждения доставки/прочтения и
индикаторы набора текста идут **не** здесь, а через `SocketService` (WebSocket).
`ChatService` покрывает операции, у которых нет «живого» потока: начальную
загрузку списка чатов, догрузку старой истории (пагинация), правку и удаление уже
существующих сообщений, создание чата.

Как и другие доменные сервисы, модуль сам с сетью не работает — он строит путь и
тело запроса и делегирует выполнение в `NetworkService`, получая обратно уже
декодированную типобезопасную модель.

### Связи с другими модулями

```
   ChatViewModel ─────────► ChatService.shared
   ChatsListViewModel ────►    (.shared)
        (фронтенд)               │
                                 │ request<T>(endpoint, method, body, queryItems)
                                 ▼
                          NetworkService.shared ──► URLSession ──► REST API
                                 ▲
                                 │  токен (Bearer) уже проставлен AuthService
                                 │
   Модели-контракты: Chat, ChatMember, Message, MessageReplyPreview, User
```

- **Транспорт — `NetworkService`.** `ChatService` хранит
  `private let network = NetworkService.shared` и все вызовы делает через
  `network.request(...)`. Авторизация (заголовок `Authorization: Bearer <token>`),
  таймауты, проверка HTTP-статуса, разбор дат и маппинг ошибок в `NetworkError` —
  всё это происходит в `NetworkService`; `ChatService` про это ничего не знает.
- **Авторизация — косвенно через `AuthService`.** Все методы `ChatService` идут с
  `requiresAuth: true` (значение по умолчанию в `NetworkService`). Токен в
  `NetworkService` кладёт `AuthService` при входе/восстановлении сессии; при `401`
  централизованно происходит `logout()`. Сам `ChatService` в авторизацию не
  вмешивается.
- **Разделение с `SocketService`.** `ChatService` (REST) и `SocketService`
  (реалтайм) работают с одними и теми же моделями (`Message`, `Chat`), но покрывают
  разные сценарии. Типичный жизненный цикл экрана чата: `ChatService.fetchMessages`
  подгружает историю → `SocketService` доставляет новые сообщения/typing/ack «на
  лету». **Отправка** нового сообщения — задача `SocketService.sendMessage`, а
  **редактирование/удаление** уже отправленного — задача `ChatService`.
- **Модели-контракты.** Возвращаемые типы — `Chat` (`Models/Chat.swift`) и
  `Message` (`Models/Message.swift`) вместе с вложенными `ChatMember`,
  `MessageReplyPreview`, перечислениями `ChatType`/`MessageType` и профилем `User`.
  Эти же модели переиспользуются `SocketService` (событие `message:new` несёт
  `Message`) и презентационным слоем.
- **Потребители (фронтенд).** `ChatsListViewModel` (список чатов) и `ChatViewModel`
  (экран переписки) вызывают методы сервиса. Это презентационный слой и в данном
  документе подробно не рассматривается.

### Модель данных

Сервис оперирует двумя доменными моделями; их полезно знать при интеграции.

**`Chat`** (`Identifiable, Codable, Hashable`):

| Поле | Тип | Смысл |
|------|-----|-------|
| `id` | `String` | Идентификатор чата |
| `type` | `ChatType` | `.direct` (`"DIRECT"`) или `.group` (`"GROUP"`) |
| `name` | `String?` | Имя (для групп; у личных чатов обычно `nil`) |
| `avatarUrl` | `String?` | Аватар чата |
| `createdAt` | `Date` | Момент создания |
| `members` | `[ChatMember]` | Участники (у каждого опционально вложен `user: User?`) |
| `lastMessage` | `Message?` | Последнее сообщение (для превью в списке) |
| `unreadCount` | `Int` | Число непрочитанных |

У `Chat` есть удобные хелперы: `displayName(currentUserId:)` (для личного чата
берёт имя собеседника, для группы — `name`) и `otherUser(currentUserId:)`.
Равенство и хеш считаются **только по `id`**.

**`Message`** (`Identifiable, Codable, Equatable`):

| Поле | Тип | Смысл |
|------|-----|-------|
| `id` | `String` (var) | Идентификатор; изменяемый, чтобы заменить оптимистичный локальный id после ack |
| `chatId` | `String` | К какому чату относится |
| `senderId` | `String` | Автор |
| `type` | `MessageType` | `.text` (`"TEXT"`) или `.system` (`"SYSTEM"`) |
| `content` | `String?` | Текст (может быть `nil`, например у удалённого) |
| `replyToId` | `String?` | id сообщения, на которое отвечают |
| `editedAt` | `Date?` | Не `nil`, если сообщение редактировали (`isEdited`) |
| `deletedAt` | `Date?` | Не `nil`, если удалено (`isDeleted`) |
| `createdAt` | `Date` | Момент отправки |
| `sender` | `User?` | Вложенный профиль автора |
| `replyTo` | `MessageReplyPreview?` | Превью цитируемого сообщения |

Вычисляемое `displayContent` возвращает `"Сообщение удалено"` для удалённых и
`content ?? ""` в остальных случаях — удобно показывать в UI без доп. проверок.

### Публичный API

```swift
static let shared: ChatService                     // единственный экземпляр

// GET /chats — все чаты текущего пользователя
func fetchChats() async throws -> [Chat]

// POST /chats — создать личный чат с одним собеседником (type = "DIRECT")
func createDirectChat(targetUserId: String) async throws -> Chat

// POST /chats — создать групповой чат (type = "GROUP")
func createGroupChat(name: String, memberIds: [String]) async throws -> Chat

// GET /chats/:id/messages — страница истории (курсорная пагинация)
func fetchMessages(chatId: String, cursor: String? = nil, limit: Int = 50) async throws -> MessagesPage

// PATCH /chats/:id/messages/:msgId — отредактировать текст сообщения
func editMessage(chatId: String, messageId: String, content: String) async throws -> Message

// DELETE /chats/:id/messages/:msgId — удалить сообщение (у себя или у всех)
func deleteMessage(chatId: String, messageId: String, forAll: Bool = false) async throws
```

Тип **`MessagesPage`** — это публичная модель страницы истории:

```swift
struct MessagesPage: Codable {
    let items: [Message]        // сообщения страницы
    let nextCursor: String?     // курсор следующей страницы; nil — история закончилась
}
```

Обёртки запросов/ответов (`ChatsResponse`, `CreateDirectChatRequest`,
`CreateGroupChatRequest`, `EditMessageRequest`, `DeleteMessageRequest`) —
**приватные**: снаружи они не видны, наружу отдаются уже развёрнутые доменные
модели (`[Chat]`, `Chat`, `Message`).

### Как использовать

**1. Загрузить список чатов (например, при открытии вкладки «Чаты»):**

```swift
let chats = try await ChatService.shared.fetchChats()   // GET /chats
```

**2. Начать личный чат с пользователем:**

```swift
let chat = try await ChatService.shared.createDirectChat(targetUserId: user.id)
// перейти на экран chat
```

**3. Создать групповой чат:**

```swift
let group = try await ChatService.shared.createGroupChat(
    name: "Семья",
    memberIds: [user1.id, user2.id, user3.id]
)
```

**4. Постраничная подгрузка истории (бесконечный скролл вверх):**

```swift
var cursor: String? = nil
repeat {
    let page = try await ChatService.shared.fetchMessages(
        chatId: chat.id,
        cursor: cursor,
        limit: 50
    )
    display(page.items)
    cursor = page.nextCursor          // nil → истории больше нет
} while cursor != nil
```

**5. Редактирование и удаление:**

```swift
// изменить текст — вернётся обновлённое сообщение (editedAt заполнится)
let updated = try await ChatService.shared.editMessage(
    chatId: chat.id, messageId: message.id, content: "Исправленный текст"
)

// удалить только у себя
try await ChatService.shared.deleteMessage(chatId: chat.id, messageId: message.id)

// удалить у всех участников
try await ChatService.shared.deleteMessage(
    chatId: chat.id, messageId: message.id, forAll: true
)
```

### Обработка ошибок

Отдельного типа ошибок у `ChatService` нет — наружу пробрасываются те же
`NetworkError`, что и из `NetworkService` (см. раздел «NetworkService → Обработка
ошибок»). Шаблон вызова:

```swift
do {
    let chats = try await ChatService.shared.fetchChats()
    // ...
} catch let error as NetworkError {
    print(error.errorDescription ?? "Ошибка загрузки чатов")
}
```

### Детали реализации, важные для интеграции

- **Синглтон без состояния.** `ChatService.shared`, `init` приватный. Класс не
  хранит кэшей и изменяемого состояния — это чистый «фасад» над REST-эндпоинтами,
  поэтому безопасен для вызова из любого места.
- **`type` задаётся сервисом, а не вызывающим.** В `CreateDirectChatRequest` и
  `CreateGroupChatRequest` поле `type` (`"DIRECT"`/`"GROUP"`) захардкожено —
  вызывающему не нужно (и нельзя) его задавать: выбор делается выбором метода
  (`createDirectChat` vs `createGroupChat`).
- **Ограничение `limit`.** `fetchMessages` **зажимает** лимит: `min(limit, 100)`.
  Даже если запросить больше 100, уйдёт максимум 100 — учитывайте это при
  проектировании пагинации.
- **Курсорная пагинация.** Историю отдаёт `MessagesPage` с `nextCursor`. Признак
  конца — `nextCursor == nil`. Курсор непрозрачен для клиента: его не нужно
  разбирать, только передавать обратно в следующий запрос.
- **`deleteMessage` не возвращает значение.** Внутри используется локальная
  `OkResponse { ok: Bool }` только чтобы удовлетворить дженерик `NetworkService`
  (метод всегда декодирует тело в `Decodable`). Наружу метод — `async throws` без
  результата: успех = отсутствие брошенной ошибки.
- **`editMessage` возвращает обновлённое сообщение.** Сервер отдаёт актуальную
  версию с проставленным `editedAt`; используйте именно её для замены локальной
  копии, а не собирайте объект вручную.
- **Согласованность с реалтаймом.** После REST-операции (edit/delete) сервер, как
  правило, ещё и рассылает соответствующие события через сокет. Чтобы не применить
  одно изменение дважды, полагайтесь на идемпотентность по `id` сообщения при
  слиянии REST-ответа и события `SocketService`.

### Точки расширения

- **Пометка прочитанным / счётчики.** Сейчас `unreadCount` приходит в `Chat`, а
  отметка о прочтении идёт через сокет (`sendRead`). Если понадобится REST-эндпоинт
  «отметить чат прочитанным», его логично добавить сюда рядом с `fetchChats`.
- **Управление участниками группы.** Добавление/удаление участников, смена имени и
  аватара группового чата (`PATCH /chats/:id`) — естественное расширение сервиса.
- **Вложения.** Сейчас поддерживается только текст (`MessageType.text`). Отправка
  медиа (загрузка файла + сообщение с ссылкой) добавляется как отдельные методы,
  не ломая существующий API.
- **Кэширование.** Модуль намеренно без кэша. При необходимости офлайн-доступа
  слой кэша (память/БД) можно встроить в `ChatService`, оставив публичные сигнатуры
  неизменными.

---

## ContactsService

**Файл:** `FamilyTalk/Services/ContactsService.swift`
**Тип:** `final class` · синглтон (`ContactsService.shared`)
**Зависимости:** `NetworkService.shared` (транспорт) · системный фреймворк `CryptoKit` (SHA-256)

### Назначение

`ContactsService` — это **доменный REST-сервис адресной книги, поиска людей,
блокировок и собственного профиля**. Он покрывает все «разовые» (request-response)
операции вокруг пользователей приложения, у которых нет реалтайм-потока:

1. **Контакты.** Получить список контактов пользователя (`fetchContacts`) и
   синхронизировать их с телефонной книгой устройства (`syncContacts`).
2. **Поиск.** Найти пользователей по строке запроса — имени/username (`searchUsers`).
3. **Блокировки.** Заблокировать/разблокировать пользователя и получить список
   заблокированных (`blockUser`, `unblockUser`, `fetchBlocked`).
4. **Профиль.** Отредактировать собственный профиль — отображаемое имя, username,
   «о себе» (`updateProfile`, `PATCH /users/me`).

Ключевая приватная особенность модуля — **синхронизация контактов идёт по хешам, а
не по «сырым» номерам**. Перед отправкой каждый телефонный номер локально хешируется
алгоритмом **SHA-256** (`CryptoKit`), и на сервер уходят только шестнадцатеричные
хеши. Так сервер может сматчить контакты между пользователями, **не получая и не
храня открытые номера телефонов** из адресной книги — это осознанное решение в
пользу приватности.

Как и остальные доменные сервисы, `ContactsService` сам с сетью не работает: он
строит путь, query-параметры и тело запроса и делегирует выполнение в
`NetworkService`, получая обратно уже декодированные типобезопасные модели `User`.

### Связи с другими модулями

```
   ContactsViewModel ────────► ContactsService.shared
     (фронтенд)                    │
                                   │ request<T>(endpoint, method, body, queryItems)
                                   ▼
                            NetworkService.shared ──► URLSession ──► REST API
                                   ▲
                                   │  токен (Bearer) уже проставлен AuthService
                                   │
   Локально:  phoneNumbers ──[ SHA-256 (CryptoKit) ]──► hashes ──► POST /users/contacts/sync
   Модель-контракт: User
```

- **Транспорт — `NetworkService`.** Сервис хранит
  `private let network = NetworkService.shared` и все вызовы делает через
  `network.request(...)`. Авторизация, таймауты, проверка HTTP-статуса, разбор дат
  и маппинг ошибок в `NetworkError` — всё это происходит в `NetworkService`;
  `ContactsService` про это ничего не знает.
- **Авторизация — косвенно через `AuthService`.** Все методы идут с
  `requiresAuth: true` (значение по умолчанию в `NetworkService`). Токен в
  `NetworkService` кладёт `AuthService`; при `401` централизованно происходит
  `logout()`. Сам `ContactsService` в авторизацию не вмешивается.
- **`CryptoKit` — локальное хеширование.** Единственный «не сетевой» участник:
  приватный `sha256(_:)` превращает номер в hex-строку SHA-256. Открытые номера за
  пределы устройства не уходят.
- **Модель-контракт — `User`** (`Models/User.swift`). Все методы возвращают либо
  `User`, либо `[User]`. Это та же модель, что используется в `AuthService`
  (профиль), `ChatService`/`SocketService` (автор сообщения, участники чата), —
  единый доменный тип пользователя на всё приложение.
- **Пересечение с чатами.** Найденный или синхронизированный `User` — типичная
  «точка входа» в переписку: по `user.id` затем вызывается
  `ChatService.createDirectChat(targetUserId:)`. Сам `ContactsService` чаты не
  создаёт — он только отдаёт пользователей.
- **Потребитель (фронтенд).** `ContactsViewModel` вызывает `fetchContacts` и
  `searchUsers` и наблюдается экраном `ContactsView`. Это презентационный слой и в
  данном документе подробно не рассматривается.

### Модель данных

Сервис оперирует единственной доменной моделью — **`User`**
(`Identifiable, Codable, Equatable`):

| Поле | Тип | Смысл |
|------|-----|-------|
| `id` | `String` | Идентификатор пользователя |
| `displayName` | `String` | Отображаемое имя |
| `phone` | `String?` | Телефон (может отсутствовать в выдаче) |
| `username` | `String?` | Уникальный ник (`@username`) |
| `avatarUrl` | `String?` | Ссылка на аватар |
| `bio` | `String?` | «О себе» |
| `lastSeen` | `Date?` | Момент последней активности |

У `User` есть два вычисляемых свойства для UI, полезных при работе с контактами:

- **`isOnline`** — `true`, если с `lastSeen` прошло меньше 30 секунд.
- **`lastSeenText`** — человекочитаемая строка активности на русском
  (`"только что"`, `"5 мин назад"`, `"2 ч назад"`, либо дата `dd.MM.yyyy`).

### Публичный API

```swift
static let shared: ContactsService                 // единственный экземпляр

// GET /users/contacts — список контактов пользователя
func fetchContacts() async throws -> [User]

// POST /users/contacts/sync — синхронизация по SHA-256-хешам номеров;
// возвращает контакты, найденные среди пользователей приложения
func syncContacts(phoneNumbers: [String]) async throws -> [User]

// GET /users/search?q= — поиск пользователей по имени/username
func searchUsers(query: String) async throws -> [User]

// POST /users/:id/block — заблокировать пользователя
func blockUser(id: String) async throws

// DELETE /users/:id/block — разблокировать пользователя
func unblockUser(id: String) async throws

// GET /users/blocked — список заблокированных пользователей
func fetchBlocked() async throws -> [User]

// PATCH /users/me — обновить собственный профиль (любое подмножество полей)
func updateProfile(displayName: String? = nil,
                   username: String? = nil,
                   bio: String? = nil) async throws -> User
```

Обёртки запросов/ответов (`ContactsResponse`, `UsersResponse`, `OkResponse`,
`ContactSyncRequest`, `UpdateProfileRequest`) — **приватные**: снаружи они не видны,
наружу отдаются уже развёрнутые доменные типы (`[User]`, `User`).

### Как использовать

**1. Загрузить контакты (например, при открытии вкладки «Контакты»):**

```swift
let contacts = try await ContactsService.shared.fetchContacts()   // GET /users/contacts
```

**2. Синхронизировать телефонную книгу (номера хешируются автоматически):**

```swift
// phoneNumbers — «сырые» номера из адресной книги устройства;
// наружу уходят только их SHA-256-хеши
let matched = try await ContactsService.shared.syncContacts(
    phoneNumbers: ["+79991234567", "+79997654321"]
)
// matched — пользователи FamilyTalk, найденные среди контактов
```

**3. Найти пользователя и начать с ним чат:**

```swift
let found = try await ContactsService.shared.searchUsers(query: "дмитрий")
if let user = found.first {
    let chat = try await ChatService.shared.createDirectChat(targetUserId: user.id)
}
```

**4. Заблокировать / разблокировать и посмотреть список блокировок:**

```swift
try await ContactsService.shared.blockUser(id: user.id)
let blocked = try await ContactsService.shared.fetchBlocked()
try await ContactsService.shared.unblockUser(id: user.id)
```

**5. Обновить собственный профиль (передаются только меняющиеся поля):**

```swift
// изменить только «о себе», не трогая имя и username
let me = try await ContactsService.shared.updateProfile(bio: "Люблю горы")
```

### Обработка ошибок

Отдельного типа ошибок у `ContactsService` нет — наружу пробрасываются те же
`NetworkError`, что и из `NetworkService` (см. раздел «NetworkService → Обработка
ошибок»). Шаблон вызова:

```swift
do {
    let contacts = try await ContactsService.shared.fetchContacts()
    // ...
} catch let error as NetworkError {
    print(error.errorDescription ?? "Ошибка загрузки контактов")
}
```

### Детали реализации, важные для интеграции

- **Синглтон без состояния.** `ContactsService.shared`, `init` приватный. Класс не
  хранит кэшей и изменяемого состояния — это чистый «фасад» над REST-эндпоинтами,
  поэтому безопасен для вызова из любого места.
- **Приватность синхронизации.** `syncContacts` **никогда** не отправляет открытые
  номера: каждый номер проходит через `sha256(_:)` (SHA-256 из `CryptoKit`,
  результат — hex-строка в нижнем регистре). Сервер матчит контакты по хешам. Если
  меняете формат/нормализацию номера — делайте это **до** хеширования и одинаково на
  клиенте и сервере, иначе хеши не совпадут.
- **`updateProfile` — частичное обновление.** Все параметры опциональны и по
  умолчанию `nil`. Передавайте только те поля, которые действительно меняются; поля
  со значением `nil` кодируются в тело запроса как есть — согласуйте с сервером
  семантику `null` (сброс поля vs «не трогать»), если это важно.
- **`block`/`unblock` не возвращают значения.** Внутри используется локальная
  `OkResponse { ok: Bool }` только чтобы удовлетворить дженерик `NetworkService`
  (метод всегда декодирует тело в `Decodable`). Наружу методы — `async throws` без
  результата: успех = отсутствие брошенной ошибки.
- **Поиск нечувствителен к тому, как фильтрует UI.** `searchUsers` уходит на сервер
  (`GET /users/search?q=`). Локальная фильтрация уже загруженного списка
  (по `displayName`/`username`) — задача презентационного слоя (`ContactsViewModel`),
  а не сервиса.

### Точки расширения

- **Пагинация поиска/контактов.** Сейчас `fetchContacts`/`searchUsers` возвращают
  плоский список. При росте объёмов сюда логично добавить курсорную пагинацию по
  аналогии с `ChatService.fetchMessages`.
- **Аватар профиля.** `updateProfile` меняет текстовые поля; загрузка изображения
  аватара (upload + `avatarUrl`) — естественное расширение рядом с ним.
- **Нормализация номеров.** Единая нормализация телефонов (E.164) перед хешированием
  повысит долю совпадений при `syncContacts` — её уместно встроить в `sha256`-конвейер.
- **Кэширование.** Модуль намеренно без кэша. Список контактов/блокировок при
  необходимости офлайн-доступа можно кэшировать внутри сервиса, не меняя публичный API.
