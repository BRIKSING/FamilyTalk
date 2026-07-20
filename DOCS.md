# FamilyTalk — Техническая документация бэкенд-модулей

Документ описывает **клиентский бэкенд** приложения FamilyTalk — слой,
отвечающий за сеть, хранение данных, авторизацию, real-time события и модели
данных. UI-слой (SwiftUI `Views`) и презентационные `ViewModels` здесь **не**
документируются — только код, обеспечивающий бизнес-логику и взаимодействие с
сервером.

> **Как читать этот документ.** Каждая тема из списка ниже — отдельный модуль
> клиентского бэкенда. Темы расписываются по очереди; уже готовые отмечены
> `[x]`, ещё не описанные — `[ ]`. Для каждого модуля указано: что это, за что
> отвечает, с какими модулями связан и как его использовать.

## Архитектурный контекст

Приложение построено по паттерну **MVVM** с использованием `@Observable`
(Observation framework, iOS 17+). Слои взаимодействуют строго в одном
направлении:

```
Views (SwiftUI)
      │  читают состояние / вызывают методы
      ▼
ViewModels (@Observable, @MainActor)
      │  вызывают асинхронные методы
      ▼
Services  ──────────────┐
  ├─ NetworkService      │  единая точка HTTP-запросов (REST)
  ├─ AuthService         │  сессия и авторизация
  ├─ KeychainService     │  безопасное хранилище токена
  ├─ ChatService         │  REST-операции с чатами и сообщениями
  ├─ ContactsService     │  REST-операции с контактами и профилем
  ├─ CallService         │  REST-история звонков
  └─ SocketService       │  real-time события (Socket.IO)
      │                   │
      ▼                   ▼
Models (Codable-структуры: User, Chat, Message, CallLog, ...)
```

Все сетевые модули — **синглтоны** (`static let shared`) с приватным
инициализатором. Модели — value-типы (`struct`/`enum`), реализующие `Codable`.

---

## Список тем (модулей бэкенда)

- [x] 1. **NetworkService** — ядро HTTP-запросов (REST, авторизация, декодирование)
- [ ] 2. **KeychainService** — безопасное хранение токена в iOS Keychain
- [ ] 3. **AuthService** — управление сессией пользователя и авторизацией
- [ ] 4. **SocketService** — real-time события (сообщения, звонки, typing) через Socket.IO
- [ ] 5. **ChatService** — REST-операции с чатами и сообщениями
- [ ] 6. **ContactsService** — контакты, поиск, блокировки, профиль
- [ ] 7. **CallService** — REST-история звонков
- [ ] 8. **Models** — слой моделей данных (User, Chat, Message, CallLog и др.)

---

## 1. NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Что это

`NetworkService` — центральный HTTP-клиент приложения. Это **единственная**
точка, через которую все остальные сервисы отправляют REST-запросы к бэкенду.
Модуль инкапсулирует построение `URLRequest`, добавление заголовков авторизации,
выполнение запроса через `URLSession`, обработку HTTP-статусов и декодирование
JSON-ответа в типизированные модели.

Реализован как потокобезопасный синглтон:

```swift
final class NetworkService {
    static let shared = NetworkService()
    private init() { ... }
}
```

### За что отвечает

1. **Хранение конфигурации соединения**
   - `baseURL` (по умолчанию `http://localhost:3000`) — базовый адрес бэкенда.
     Меняется в одном месте перед запуском против реального сервера.
   - `accessToken` — текущий JWT-токен (доступен только на чтение снаружи:
     `private(set)`). Устанавливается через `setAccessToken(_:)` и очищается
     через `clearAccessToken()`.

2. **Единый универсальный метод запроса** — дженерик `request<T: Decodable>`,
   который возвращает уже декодированную модель:

   ```swift
   func request<T: Decodable>(
       endpoint: String,
       method: String = "GET",
       queryItems: [URLQueryItem]? = nil,
       body: (any Encodable)? = nil,
       requiresAuth: Bool = true
   ) async throws -> T
   ```

   - `endpoint` — путь, добавляемый к `baseURL` (например `/chats`).
   - `method` — HTTP-метод (`GET`, `POST`, `PATCH`, `DELETE`).
   - `queryItems` — query-параметры (например `?limit=50&cursor=...`).
   - `body` — тело запроса; любой `Encodable` кодируется в JSON.
   - `requiresAuth` — добавлять ли заголовок `Authorization: Bearer <token>`.
     Для публичных эндпоинтов (например `/auth/login`) передаётся `false`.

3. **Обработка ответа и ошибок.** Все сетевые ошибки нормализуются в единый
   типизированный enum `NetworkError: LocalizedError` с локализованными
   (русскоязычными) описаниями:

   | Кейс | Когда возникает |
   |------|-----------------|
   | `.invalidURL` | Не удалось собрать URL из `baseURL + endpoint` |
   | `.invalidResponse` | Ответ не является `HTTPURLResponse` |
   | `.unauthorized` | HTTP 401 (токен истёк / отсутствует) |
   | `.httpError(statusCode:body:)` | Любой статус вне диапазона `200...299` |
   | `.decodingError(Error)` | Не удалось декодировать тело в тип `T` |
   | `.unknown(Error)` | Прочие ошибки |

4. **Централизованная обработка 401.** При получении статуса `401` сервис
   публикует нотификацию `Notification.Name.networkUnauthorized` через
   `NotificationCenter` **и** бросает `NetworkError.unauthorized`. Это позволяет
   `AuthService` подписаться на событие и автоматически завершить сессию
   (разлогинить пользователя) независимо от того, какой именно запрос упал.

5. **Кастомное декодирование дат.** `JSONDecoder` настроен на разбор дат в
   формате **ISO 8601** — сначала с дробными секундами (`.withFractionalSeconds`),
   затем без них. Это делает клиент устойчивым к обоим вариантам, которые может
   вернуть сервер. `URLSession` сконфигурирован с таймаутом запроса **30 секунд**.

### Взаимосвязи с другими модулями

- **Зависит от:** только Foundation (`URLSession`, `URLComponents`,
  `JSONDecoder`/`JSONEncoder`, `NotificationCenter`). Внешних зависимостей нет.
- **Используется всеми REST-сервисами:** `AuthService`, `ChatService`,
  `ContactsService`, `CallService` держат ссылку
  `private let network = NetworkService.shared` и вызывают `network.request(...)`.
- **Связь с `AuthService`:**
  - `AuthService` вызывает `setAccessToken(_:)` / `clearAccessToken()` при
    входе, восстановлении и выходе из сессии.
  - `AuthService` подписан на `.networkUnauthorized` и при 401 автоматически
    выполняет `logout()`.
- **Связь с `SocketService`:** Socket.IO-соединение использует тот же
  `NetworkService.shared.baseURL` для построения URL, но передаёт данные
  **не** через `NetworkService` — real-time трафик идёт напрямую по WebSocket.
  То есть `baseURL` — общий источник истины для адреса бэкенда.

### Как использовать

**Простой GET с декодированием в модель.** Тип результата выводится из аннотации
переменной:

```swift
let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")
```

**GET с query-параметрами:**

```swift
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

**POST с телом запроса (публичный эндпоинт, без токена):**

```swift
let response: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false
)
```

**Запрос без содержательного тела ответа.** Сервер обычно возвращает `{ "ok": true }`;
объявите локальную структуру и проигнорируйте результат:

```swift
struct OkResponse: Codable { let ok: Bool }
let _: OkResponse = try await NetworkService.shared.request(
    endpoint: "/users/\(id)/block",
    method: "POST"
)
```

**Обработка ошибок** на стороне вызывающего (обычно во ViewModel):

```swift
do {
    let chats: [Chat] = try await ChatService.shared.fetchChats()
    // ...
} catch let error as NetworkError {
    self.errorMessage = error.errorDescription   // готовая локализованная строка
} catch {
    self.errorMessage = error.localizedDescription
}
```

### Замечания и ограничения

- `request` — `async throws`; вызывать его следует из асинхронного контекста
  (например `Task { }` во ViewModel). Метод сам по себе потокобезопасен для
  чтения токена, но запись токена (`setAccessToken`) выполняется из
  `AuthService` на главном акторе.
- Тип возвращаемого значения `T` **обязательно** должен быть `Decodable` и
  соответствовать структуре JSON-ответа, иначе будет брошен
  `NetworkError.decodingError`.
- Заголовок `Content-Type: application/json` добавляется всегда; заголовок
  `Authorization` — только когда `requiresAuth == true` и токен установлен.
- Изменение `baseURL` затрагивает и REST (`NetworkService`), и WebSocket
  (`SocketService`) — задавайте адрес один раз при старте приложения.
