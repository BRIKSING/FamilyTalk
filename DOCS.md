# FamilyTalk — Техническая документация (Backend / слой сервисов)

Документ описывает **бекенд-часть iOS-клиента** FamilyTalk: сетевой слой,
сервисы бизнес-логики и модели данных, через которые приложение общается с
серверным API (REST) и системой real-time событий (Socket.IO / WebRTC-сигналинг).

> Документируется только клиентский бекенд-слой (`Services/`, `Models/`).
> UI-слой (`Views/`) и презентационный слой (`ViewModels/`) в этот документ не входят.

## Архитектура слоёв

```
Views (SwiftUI)              ← не документируется здесь
   │
ViewModels (@Observable)     ← не документируется здесь
   │
┌──────────────── Backend-слой (этот документ) ────────────────┐
│  Services/                                                    │
│    NetworkService   — низкоуровневый HTTP-клиент (REST)       │
│    SocketService    — real-time события (Socket.IO)           │
│    KeychainService  — безопасное хранилище токена             │
│    AuthService      — авторизация и жизненный цикл сессии      │
│    ContactsService  — контакты, поиск, профиль, блокировки    │
│    ChatService      — чаты и сообщения (REST)                 │
│    CallService      — история звонков (REST)                  │
│  Models/                                                     │
│    User, AuthResponse, Chat, Message, CallLog               │
└──────────────────────────────────────────────────────────────┘
   │
Сервер (REST API + Socket.IO)
```

## Список модулей (темы документации)

Ниже — план документирования бекенд-модулей. По мере готовности темы
отмечаются как выполненные.

- [x] **NetworkService** — базовый HTTP-клиент (REST), аутентификация запросов, обработка ошибок
- [ ] **KeychainService** — безопасное хранение токена доступа в iOS Keychain
- [ ] **AuthService** — вход, восстановление и завершение сессии
- [ ] **ContactsService** — контакты, синхронизация, поиск, профиль, блокировки
- [ ] **ChatService** — чаты и сообщения (REST-операции)
- [ ] **CallService** — история звонков
- [ ] **SocketService** — real-time события (сообщения, набор текста, WebRTC-сигналинг)
- [ ] **Models** — модели данных (User, AuthResponse, Chat, Message, CallLog)

---

## NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`
**Тип:** `final class` — синглтон (`NetworkService.shared`)

### Назначение

`NetworkService` — это единая точка входа для всех **REST-запросов** к серверу.
Он инкапсулирует `URLSession`, формирование запроса, добавление JWT-токена
авторизации, разбор HTTP-ответа, декодирование JSON и преобразование ошибок в
типизированный `NetworkError`. Все остальные сервисы (`AuthService`,
`ContactsService`, `ChatService`, `CallService`) обращаются к серверу
**исключительно через него** — прямых обращений к `URLSession` в кодовой базе
быть не должно.

### Место в архитектуре и взаимосвязи

```
AuthService ─┐
ContactsService ─┤
ChatService  ─┼──►  NetworkService.shared.request(...)  ──►  URLSession  ──►  Сервер (REST)
CallService  ─┘                    │
                                   ├── использует accessToken для заголовка Authorization
                                   └── при 401 шлёт Notification .networkUnauthorized
```

- **Зависит от:** только от `Foundation` (`URLSession`, `JSONDecoder`,
  `JSONEncoder`). Не зависит ни от одного другого сервиса — это самый нижний
  уровень стека, поэтому у него нет входящих зависимостей от бизнес-логики.
- **Используется:** всеми REST-сервисами приложения.
- **Связь с `AuthService`:** `AuthService` устанавливает токен
  (`setAccessToken`) после входа и очищает его (`clearAccessToken`) при выходе.
  В обратную сторону `NetworkService` уведомляет систему о неавторизованном
  ответе через `NotificationCenter` (см. ниже), на что `AuthService`
  подписывается и выполняет автоматический `logout()`.
- **Связь с `SocketService`:** напрямую не связан, но `SocketService` читает
  `NetworkService.shared.baseURL`, чтобы подключиться к тому же хосту.

### Публичный интерфейс

| Член | Сигнатура | Описание |
| --- | --- | --- |
| `shared` | `static let shared` | Единственный экземпляр (синглтон). |
| `baseURL` | `var baseURL: String` | Базовый адрес сервера. По умолчанию `http://localhost:3000`. Меняется на реальный адрес бекенда при конфигурации. |
| `accessToken` | `private(set) var accessToken: String?` | Текущий JWT. Только для чтения извне. |
| `setAccessToken(_:)` | `func setAccessToken(_ token: String)` | Устанавливает токен, который будет добавляться в заголовок `Authorization`. |
| `clearAccessToken()` | `func clearAccessToken()` | Сбрасывает токен (при выходе из аккаунта). |
| `request(...)` | `func request<T: Decodable>(...) async throws -> T` | Основной обобщённый метод выполнения запроса. |

#### Сигнатура `request`

```swift
func request<T: Decodable>(
    endpoint: String,                 // путь, добавляется к baseURL, например "/auth/me"
    method: String = "GET",           // HTTP-метод: "GET" | "POST" | "PATCH" | "DELETE" ...
    queryItems: [URLQueryItem]? = nil,// query-параметры (?q=...&limit=...)
    body: (any Encodable)? = nil,     // тело запроса; кодируется в JSON
    requiresAuth: Bool = true         // добавлять ли заголовок Authorization
) async throws -> T
```

Тип результата `T` выводится из контекста присваивания — вызывающий код
указывает ожидаемую модель, а метод декодирует ответ в неё.

### Поведение

1. **Сборка URL.** `baseURL + endpoint` разбирается через `URLComponents`; при
   наличии `queryItems` они добавляются в строку запроса. Некорректный URL →
   `NetworkError.invalidURL`.
2. **Заголовки.** Всегда ставится `Content-Type: application/json`. Если
   `requiresAuth == true` и токен установлен — добавляется
   `Authorization: Bearer <token>`.
3. **Тело.** Если передан `body`, он кодируется в JSON стандартным
   `JSONEncoder`.
4. **Выполнение** через `URLSession` с таймаутом запроса **30 секунд**.
5. **Разбор ответа:**
   - Ответ не `HTTPURLResponse` → `NetworkError.invalidResponse`.
   - **HTTP 401** → публикуется `Notification.Name.networkUnauthorized` и
     выбрасывается `NetworkError.unauthorized`. Это единая точка обработки
     «протухшей» сессии.
   - Код вне диапазона `200...299` →
     `NetworkError.httpError(statusCode:body:)` с телом ответа (для диагностики).
   - Успех → тело декодируется в `T`; ошибка декодирования оборачивается в
     `NetworkError.decodingError`.

### Обработка дат (важно для совместимости с сервером)

`JSONDecoder` настроен на **кастомную стратегию дат**: сначала пытается
разобрать ISO 8601 **с дробными секундами** (`.withFractionalSeconds`), затем —
без них. Это позволяет корректно принимать метки времени сервера в обоих
форматах (`2026-04-23T10:15:30.123Z` и `2026-04-23T10:15:30Z`). Если строку не
удаётся распарсить — выбрасывается `DecodingError`.

> Примечание: `SocketService` использует **точно такую же** стратегию дат в
> своём собственном декодере для единообразного разбора payload'ов.

### Типы ошибок — `NetworkError`

`enum NetworkError: Error, LocalizedError` с человекочитаемым
`errorDescription` (на русском), пригодным для показа в UI:

| Кейс | Когда возникает |
| --- | --- |
| `.invalidURL` | Не удалось собрать URL из `baseURL + endpoint`. |
| `.invalidResponse` | Ответ не является `HTTPURLResponse`. |
| `.unauthorized` | Сервер вернул 401 (сессия недействительна). |
| `.httpError(statusCode:body:)` | Любой не-2xx код (кроме 401). |
| `.decodingError(Error)` | Тело ответа не декодируется в ожидаемую модель. |
| `.unknown(Error)` | Резерв для прочих ошибок. |

### Механизм оповещения о разлогине

```swift
extension Notification.Name {
    static let networkUnauthorized = Notification.Name("networkUnauthorized")
}
```

При получении **401** сервис публикует это уведомление. `AuthService`
подписан на него и при получении выполняет `logout()` на главном потоке.
Таким образом, любой запрос из любого сервиса, натолкнувшийся на истёкший
токен, автоматически приводит к выходу пользователя из аккаунта — обработку не
нужно дублировать в каждом вызывающем месте.

### Как использовать

**GET с типизированным ответом:**

```swift
struct MePayload: Decodable { let id: String; let displayName: String }

let me: MePayload = try await NetworkService.shared.request(
    endpoint: "/auth/me"
)
```

**POST с телом, без авторизации (например, вход):**

```swift
let response: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false
)
```

**GET с query-параметрами:**

```swift
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

**Запрос без ожидаемого содержимого** (когда сервер возвращает `{ "ok": true }`):

```swift
struct OkResponse: Decodable { let ok: Bool }
let _: OkResponse = try await NetworkService.shared.request(
    endpoint: "/users/\(id)/block",
    method: "POST"
)
```

### Замечания и ограничения

- **Не потокобезопасен для конкурентной записи токена.** Токен ожидается
  устанавливать/сбрасывать из главного потока (что и делает `AuthService`).
- **Обновление токена (refresh) не реализовано** на уровне сети: при 401
  происходит разлогин, а не «тихое» продление сессии.
- Настройка `baseURL` — единственная обязательная точка конфигурации перед
  запуском против реального сервера.

---

*Документ ведётся по мере покрытия модулей. Следующая тема: `KeychainService`.*
