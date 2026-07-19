# FamilyTalk — Техническая документация (Backend / сетевой слой)

Документ описывает **бэкенд-слой iOS-клиента FamilyTalk** — сервисы, которые
общаются с сервером (REST + Socket.IO), и модели данных, приходящие с сервера.
UI-слой (`Views/`) и связывающий его код (`ViewModels/`) в этом документе **не
рассматриваются**.

Документация ведётся по модулям. Каждый модуль расписывается отдельным этапом.
Ниже — индекс модулей со статусом. По мере готовности статус меняется с
`⬜ TODO` на `✅ Готово`.

## Архитектура бэкенд-слоя (обзор)

```
┌──────────────────────────────────────────────────────────────┐
│                      ViewModels (frontend)                     │
└───────────────┬───────────────────────────────┬──────────────┘
                │ REST (запрос/ответ)            │ realtime (события)
        ┌───────▼────────┐               ┌───────▼─────────┐
        │  *Service (REST)│               │  SocketService  │
        │  Auth / Chat /  │               │  (Socket.IO)    │
        │  Contacts / Call│               │  чат + звонки   │
        └───────┬────────┘               └───────┬─────────┘
                │ использует                      │ токен из
        ┌───────▼────────┐               ┌───────▼─────────┐
        │ NetworkService │◄──── токен ────│  AuthService    │
        │ (HTTP-транспорт)│               │  KeychainService│
        └────────────────┘               └─────────────────┘
                │ Codable
        ┌───────▼────────┐
        │     Models      │  User, Chat, Message, CallLog, ...
        └────────────────┘
```

Ключевые принципы:

- **Единая точка транспорта.** Все REST-запросы идут через синглтон
  `NetworkService.shared`. Он держит `baseURL`, access-token и настроенный
  `JSONDecoder`.
- **Сервисы предметной области.** `AuthService`, `ChatService`,
  `ContactsService`, `CallService` — тонкие обёртки над `NetworkService`,
  каждая отвечает за свою группу эндпоинтов.
- **Realtime отдельно.** Мгновенные события (новые сообщения, набор текста,
  сигналинг звонков) идут не через REST, а через `SocketService` поверх
  Socket.IO.
- **Хранение секретов.** Токен доступа хранится в Keychain
  (`KeychainService`), профиль пользователя — в `UserDefaults`.

## Индекс модулей

| # | Модуль | Файл | Назначение | Статус |
|---|--------|------|------------|--------|
| 1 | **NetworkService** | `Services/NetworkService.swift` | HTTP-транспорт: сборка запросов, авторизация, декодирование, ошибки | ✅ Готово |
| 2 | KeychainService | `Services/KeychainService.swift` | Безопасное хранение access-token в Keychain | ⬜ TODO |
| 3 | AuthService | `Services/AuthService.swift` | Логин, сессия, восстановление и logout | ⬜ TODO |
| 4 | ChatService | `Services/ChatService.swift` | REST по чатам и сообщениям | ⬜ TODO |
| 5 | ContactsService | `Services/ContactsService.swift` | Контакты, поиск, блокировки, профиль | ⬜ TODO |
| 6 | CallService | `Services/CallService.swift` | История звонков (REST) | ⬜ TODO |
| 7 | SocketService | `Services/SocketService.swift` | Realtime: чат-события и WebRTC-сигналинг | ⬜ TODO |
| 8 | Модели данных | `Models/*.swift` | Codable-модели ответов сервера | ⬜ TODO |

---

## 1. NetworkService — HTTP-транспорт

**Файл:** `FamilyTalk/Services/NetworkService.swift`
**Тип:** `final class NetworkService` (синглтон `NetworkService.shared`)

### Назначение

`NetworkService` — единственная точка, через которую iOS-клиент делает
**REST-запросы к серверу**. Модуль решает четыре задачи:

1. Собирает `URLRequest` (URL, метод, query-параметры, тело, заголовки).
2. Подставляет заголовок авторизации `Authorization: Bearer <token>`.
3. Декодирует JSON-ответ в нужный `Decodable`-тип.
4. Приводит все сетевые сбои к единому типу ошибки `NetworkError`.

Это фундамент всего бэкенд-слоя: остальные сервисы (`AuthService`,
`ChatService`, `ContactsService`, `CallService`) не работают с `URLSession`
напрямую, а вызывают `NetworkService.shared.request(...)`.

### Взаимосвязи с другими модулями

| Направление | Модуль | Как связаны |
|-------------|--------|-------------|
| Использует | `Foundation.URLSession` | Выполняет HTTP-запросы |
| Использует | `Models/*` | Декодирует ответ в `Decodable`-модели |
| Используется | `AuthService` | Устанавливает/сбрасывает токен, шлёт `/auth/*` |
| Используется | `ChatService` | `/chats`, `/chats/:id/messages` |
| Используется | `ContactsService` | `/users/*` |
| Используется | `CallService` | `/calls/history` |
| Читает `baseURL` | `SocketService` | Берёт тот же `baseURL` для Socket.IO |
| Оповещает | `AuthService` | Через `Notification.Name.networkUnauthorized` при `401` |

### Публичный интерфейс

```swift
final class NetworkService {
    static let shared: NetworkService

    var baseURL: String                    // по умолчанию "http://localhost:3000"
    private(set) var accessToken: String?  // текущий Bearer-токен

    func setAccessToken(_ token: String)
    func clearAccessToken()

    func request<T: Decodable>(
        endpoint: String,                  // напр. "/chats"
        method: String = "GET",            // "GET" | "POST" | "PATCH" | "DELETE"
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,      // сериализуется в JSON-тело
        requiresAuth: Bool = true          // добавлять ли заголовок авторизации
    ) async throws -> T
}
```

#### `request(...)` — как использовать

Обобщённый метод: тип возвращаемого значения выводится из места вызова.
Вызывающий код указывает лишь эндпоинт, метод и (опционально) тело/параметры.

```swift
// GET со списком в ответе
let response: ChatsResponse = try await NetworkService.shared.request(
    endpoint: "/chats"
)

// POST с телом запроса
let chat: Chat = try await NetworkService.shared.request(
    endpoint: "/chats",
    method: "POST",
    body: CreateDirectChatRequest(targetUserId: userId)
)

// GET с query-параметрами
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)

// Публичный эндпоинт (без токена)
let auth: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: name),
    requiresAuth: false
)
```

### Поведение и детали реализации

- **Базовый URL.** `baseURL` по умолчанию `http://localhost:3000` (локальная
  разработка). Итоговый URL — `baseURL + endpoint`, поэтому `endpoint` всегда
  начинается со `/`.
- **Сессия.** `URLSession` с `timeoutIntervalForRequest = 30` секунд.
- **Заголовки.** Всегда ставится `Content-Type: application/json`. Если
  `requiresAuth == true` и токен есть — добавляется
  `Authorization: Bearer <token>`.
- **Тело.** Любое `Encodable` кодируется в JSON через `JSONEncoder`.
- **Декодирование дат.** `JSONDecoder` настроен на кастомную стратегию:
  сначала пытается разобрать ISO 8601 **с** долями секунды
  (`.withFractionalSeconds`), затем **без** них. Это важно, потому что сервер
  может присылать оба формата; тот же приём продублирован в `SocketService`.

### Обработка ошибок

Все сбои приводятся к типу `NetworkError: LocalizedError` (сообщения —
на русском, готовы для показа пользователю):

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | Не удалось собрать URL из `baseURL + endpoint` |
| `.invalidResponse` | Ответ не является `HTTPURLResponse` |
| `.unauthorized` | HTTP `401` |
| `.httpError(statusCode:body:)` | Код вне диапазона `200...299` |
| `.decodingError(_)` | Тело не разобралось в тип `T` |
| `.unknown(_)` | Прочие ошибки |

**Особый случай — `401`.** При получении `401` сервис публикует
уведомление `Notification.Name.networkUnauthorized` через `NotificationCenter`
и бросает `.unauthorized`. На это уведомление подписан `AuthService`: он
разлогинивает пользователя (чистит токен, отключает сокет). Так истёкшая
сессия обрабатывается централизованно, без дублирования в каждом сервисе.

### Замечания / потенциальные улучшения

- `NetworkService` — не `@Observable` и не изолирован в actor; `accessToken`
  мутируется из разных мест. Сейчас записи идут преимущественно с `@MainActor`
  (см. `AuthService.saveSession`), но при усложнении потоков стоит рассмотреть
  изоляцию токена.
- `baseURL` захардкожен под localhost — при переходе на реальный сервер это
  первое, что нужно вынести в конфигурацию окружения.
