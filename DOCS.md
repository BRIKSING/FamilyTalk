# FamilyTalk — Техническая документация бэкенда (клиентский слой)

Документ описывает **бэкенд-слой iOS-клиента** FamilyTalk: сетевые сервисы,
слой доступа к данным и модели, через которые приложение общается с
серверным API (REST + Socket.IO). UI-слой (`Views/`, `ViewModels/`) в этом
документе **не описывается**.

> Стек: Swift 6, `async/await`, `@Observable`, Swift Package Manager.
> Базовый URL сервера настраивается в `NetworkService.baseURL`
> (по умолчанию `http://localhost:3000`).

## Архитектура бэкенд-слоя

```
                     ┌──────────────────────────┐
   ViewModels  ─────▶│   Сервисы (Services/)    │
                     ├──────────────────────────┤
                     │ AuthService              │
                     │ ChatService              │
                     │ ContactsService          │──▶ NetworkService ──▶ REST API
                     │ CallService              │        (HTTP)
                     │ SocketService            │──────────────────▶ Socket.IO
                     │ KeychainService          │        (WebSocket)
                     └──────────────────────────┘
                                 │
                                 ▼
                     ┌──────────────────────────┐
                     │    Модели (Models/)      │
                     │ User, Chat, Message,     │
                     │ CallLog, AuthResponse    │
                     └──────────────────────────┘
```

- **`NetworkService`** — единая точка выполнения REST-запросов (HTTP).
- **`SocketService`** — двунаправленный real-time канал (Socket.IO) для
  сообщений и сигналинга звонков.
- Остальные сервисы (`AuthService`, `ChatService`, `ContactsService`,
  `CallService`) — доменные обёртки над `NetworkService`.
- **`KeychainService`** — безопасное хранилище токена доступа.
- **Модели** — `Codable`-структуры, отражающие DTO серверного API.

## Список тем (модулей)

| # | Модуль | Статус |
|---|--------|--------|
| 1 | [NetworkService — базовый REST-клиент](#1-networkservice--базовый-rest-клиент) | ✅ Готово |
| 2 | KeychainService — безопасное хранилище токена | ⏳ Не расписано |
| 3 | AuthService — аутентификация и сессия | ⏳ Не расписано |
| 4 | SocketService — real-time канал (Socket.IO) | ⏳ Не расписано |
| 5 | ChatService — REST API чатов и сообщений | ⏳ Не расписано |
| 6 | ContactsService — REST API контактов и пользователей | ⏳ Не расписано |
| 7 | CallService — история звонков | ⏳ Не расписано |
| 8 | Модели данных (Models/) | ⏳ Не расписано |

---

## 1. NetworkService — базовый REST-клиент

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — это единственная точка в приложении, через которую
выполняются все REST-запросы к серверу. Модуль инкапсулирует:

- построение URL и HTTP-запроса;
- подстановку JWT-токена в заголовок `Authorization`;
- сериализацию тела запроса и декодирование ответа (JSON);
- унифицированную обработку ошибок (`NetworkError`);
- централизованную реакцию на `401 Unauthorized`.

Доменные сервисы (`AuthService`, `ChatService`, `ContactsService`,
`CallService`) **не работают с `URLSession` напрямую** — они вызывают
`NetworkService.request(...)`. Благодаря этому логика авторизации, обработки
ошибок и парсинга дат живёт в одном месте.

### Взаимосвязи с другими модулями

| Связь | Описание |
|-------|----------|
| **Используется** сервисами `AuthService`, `ChatService`, `ContactsService`, `CallService` | Все REST-вызовы проходят через `request(...)`. |
| **Используется** `SocketService` | Берёт `NetworkService.shared.baseURL`, чтобы построить URL WebSocket-соединения. |
| **Хранит** `accessToken` | Токен задаётся из `AuthService` через `setAccessToken(_:)` и очищается через `clearAccessToken()`. Сам `NetworkService` токен нигде не персистит — за хранение отвечает `KeychainService`. |
| **Публикует** `Notification.Name.networkUnauthorized` | При ответе `401` рассылает уведомление; `AuthService` подписан на него и вызывает `logout()`. Это разрывает потенциальный цикл зависимостей `NetworkService → AuthService`. |
| **Зависит от** моделей (`Models/`) | Дженерик-параметр `T: Decodable` — это модель ответа (`User`, `Chat`, `AuthResponse` и т. д.). |

### Публичный интерфейс

```swift
final class NetworkService {
    static let shared = NetworkService()          // синглтон

    var baseURL = "http://localhost:3000"          // адрес сервера
    private(set) var accessToken: String?          // текущий JWT (только чтение снаружи)

    func setAccessToken(_ token: String)           // установить токен
    func clearAccessToken()                        // сбросить токен (при logout)

    func request<T: Decodable>(
        endpoint: String,                          // путь, напр. "/chats"
        method: String = "GET",                    // HTTP-метод
        queryItems: [URLQueryItem]? = nil,         // query-параметры
        body: (any Encodable)? = nil,              // тело запроса (кодируется в JSON)
        requiresAuth: Bool = true                  // добавлять ли Authorization
    ) async throws -> T                            // декодированный ответ
}
```

Доступ — только через синглтон `NetworkService.shared`. Прямая инициализация
запрещена (`private init`).

### Обработка ошибок

Все ошибки нормализуются в перечисление `NetworkError: LocalizedError` с
локализованными сообщениями (`errorDescription`):

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | Не удалось собрать `URL` из `baseURL + endpoint`. |
| `.invalidResponse` | Ответ не является `HTTPURLResponse`. |
| `.unauthorized` | HTTP `401`. Дополнительно рассылается `networkUnauthorized`. |
| `.httpError(statusCode:body:)` | Любой статус вне диапазона `200...299`. Тело ответа прикладывается как строка. |
| `.decodingError(Error)` | Тело успешного ответа не удалось декодировать в `T`. |
| `.unknown(Error)` | Прочие ошибки. |

### Декодирование дат

`JSONDecoder` настроен на **кастомную стратегию дат ISO 8601** и корректно
разбирает обе формы:

- с дробными секундами — `2026-04-23T10:15:30.123Z`;
- без дробных секунд — `2026-04-23T10:15:30Z`.

Если строку не удаётся распарсить — выбрасывается `DecodingError`. Такая же
стратегия продублирована в `SocketService` для payload'ов сокета.

### Обработка `401 Unauthorized`

Централизованный «разлогин»: при статусе `401` метод `request`
1. публикует `NotificationCenter.default.post(name: .networkUnauthorized)`,
2. выбрасывает `NetworkError.unauthorized`.

`AuthService` подписан на это уведомление в своём `init` и вызывает `logout()`
на главном потоке. Так любой протухший токен приводит к выходу из сессии без
прямой зависимости `NetworkService` от `AuthService`.

### Как использовать

**1. GET без параметров** (ответ обёрнут в структуру):

```swift
struct ChatsResponse: Codable { let chats: [Chat] }

let response: ChatsResponse = try await NetworkService.shared.request(
    endpoint: "/chats"
)
let chats = response.chats
```

**2. POST с телом запроса:**

```swift
struct LoginRequest: Codable { let phone: String; let displayName: String }

let auth: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: name),
    requiresAuth: false        // при логине токена ещё нет
)
```

**3. GET с query-параметрами (пагинация):**

```swift
var query = [URLQueryItem(name: "limit", value: "50")]
if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }

let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: query
)
```

**4. Обработка ошибок на стороне вызывающего кода:**

```swift
do {
    let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")
} catch let error as NetworkError {
    print(error.errorDescription ?? "Неизвестная ошибка")
} catch {
    // прочие ошибки
}
```

### Важные замечания для разработчика

- **Тип возвращаемого значения выводится из контекста.** `request` —
  дженерик по `T: Decodable`; тип аннотируется в месте вызова
  (`let x: SomeType = try await ...`), иначе компилятор не сможет вывести `T`.
- **Тайм-аут запроса — 30 секунд** (`timeoutIntervalForRequest`).
- **Заголовок `Content-Type: application/json`** ставится всегда;
  `Authorization: Bearer <token>` — только если `requiresAuth == true` и токен
  задан.
- **Токен в памяти не персистентен.** После перезапуска приложения его нужно
  восстановить из `KeychainService` и передать в `setAccessToken(_:)` — это
  делает `AuthService.restoreSession()`.
- Тело запроса кодируется через `JSONEncoder()` со стандартными настройками
  (даты в теле запроса, если они появятся, следует учитывать отдельно).
