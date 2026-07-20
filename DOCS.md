# FamilyTalk — Техническая документация бэкенда

Документация серверно-взаимодействующего слоя iOS-приложения **FamilyTalk**
(семейный мессенджер с текстовыми чатами, голосовыми и видеозвонками).

> **Область документа.** Здесь описывается только «бэкенд» клиента — слой,
> отвечающий за сеть, real-time-события, хранение сессии и модели данных
> (каталоги `FamilyTalk/Services/` и `FamilyTalk/Models/`). UI-слой
> (`Views/`, `ViewModels/`) документируется отдельно и здесь не рассматривается.

## Общая архитектура

```
┌─────────────────────────────────────────────────────────┐
│                    UI (Views / ViewModels)               │  ← фронтенд
├─────────────────────────────────────────────────────────┤
│  AuthService   ChatService   ContactsService  CallService│  ← доменные сервисы
│                    SocketService (real-time)             │
├─────────────────────────────────────────────────────────┤
│   NetworkService (REST/HTTP)      KeychainService        │  ← инфраструктура
├─────────────────────────────────────────────────────────┤
│                    Models (DTO / доменные типы)          │
└─────────────────────────────────────────────────────────┘
```

- **NetworkService** — единая точка выполнения REST-запросов поверх `URLSession`.
- **SocketService** — двунаправленный канал Socket.IO для сигналинга звонков и
  событий чата в реальном времени.
- **Доменные сервисы** (`AuthService`, `ChatService`, `ContactsService`,
  `CallService`) инкапсулируют конкретные группы эндпоинтов и возвращают
  типизированные модели.
- **KeychainService** — безопасное хранилище токена доступа.
- **Models** — `Codable`-структуры, общие для REST и Socket-слоёв.

Все сервисы реализованы как синглтоны (`static let shared`) и общаются с сервером
через один общий `NetworkService.shared` (единый `baseURL` и `accessToken`).

---

## Дорожная карта документации (модули бэкенда)

Отмечайте `[x]`, когда модуль расписан. Документируется по одному модулю за этап.

- [x] **NetworkService** — HTTP-клиент, обработка ошибок, авторизация запросов
- [ ] **KeychainService** — безопасное хранение токена в iOS Keychain
- [ ] **AuthService** — вход, сессия, восстановление и выход
- [ ] **SocketService** — real-time события (сигналинг звонков и чат)
- [ ] **ChatService** — REST API чатов и сообщений
- [ ] **ContactsService** — REST API контактов, поиска и профиля
- [ ] **CallService** — история звонков (REST)
- [ ] **Models** — доменные модели данных (`User`, `Chat`, `Message`, `CallLog`, …)

---

## Модуль: NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — низкоуровневый HTTP-клиент и **единственная** точка, через
которую весь клиент выполняет REST-запросы к бэкенду. Модуль решает четыре задачи:

1. Формирование `URLRequest` (базовый URL, путь, query-параметры, JSON-тело).
2. Прозрачное добавление заголовка авторизации `Authorization: Bearer <token>`.
3. Декодирование JSON-ответа в любой `Decodable`-тип (включая единую стратегию
   разбора дат ISO 8601).
4. Единообразная обработка HTTP-ошибок и особый случай `401 Unauthorized`.

### Взаимосвязи с другими модулями

| Направление | Модуль | Характер связи |
|-------------|--------|----------------|
| ← использует | `AuthService` | вызывает `request(...)` для `/auth/*`, задаёт/сбрасывает токен |
| ← использует | `ChatService`, `ContactsService`, `CallService` | все REST-вызовы идут через `request(...)` |
| ← читает | `SocketService` | берёт `NetworkService.shared.baseURL` как адрес Socket.IO-сервера |
| → уведомляет | `AuthService` | шлёт нотификацию `.networkUnauthorized` при `401`, по которой `AuthService` делает `logout()` |

Схематично поток авторизации:

```
NetworkService  ──401──▶  NotificationCenter(.networkUnauthorized)  ──▶  AuthService.logout()
```

Такой развязанный через `NotificationCenter` контракт позволяет любому запросу
инициировать разлогин, не завися напрямую от `AuthService`.

### Публичный интерфейс

```swift
final class NetworkService {
    static let shared: NetworkService

    var baseURL: String                 // адрес бэкенда, по умолчанию "http://localhost:3000"
    private(set) var accessToken: String?

    func setAccessToken(_ token: String)
    func clearAccessToken()

    func request<T: Decodable>(
        endpoint: String,               // путь, например "/chats"
        method: String = "GET",         // HTTP-метод
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,   // будет сериализовано в JSON
        requiresAuth: Bool = true       // добавлять ли Bearer-токен
    ) async throws -> T
}
```

Дополнительно модуль экспортирует:

- `enum NetworkError` — типизированные ошибки сети (`LocalizedError`).
- `Notification.Name.networkUnauthorized` — событие «сессия недействительна».

### Обработка ошибок

`request(...)` бросает `NetworkError`:

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | не удалось собрать URL из `baseURL + endpoint` |
| `.invalidResponse` | ответ не является `HTTPURLResponse` |
| `.unauthorized` | HTTP-статус `401` (дополнительно шлётся нотификация) |
| `.httpError(statusCode:body:)` | статус вне диапазона `200...299` |
| `.decodingError(Error)` | тело не декодируется в ожидаемый тип `T` |
| `.unknown(Error)` | прочие ошибки |

У каждого кейса есть локализованное `errorDescription` (русский текст), пригодное
для показа в UI.

### Ключевые детали реализации

- **Таймаут** запроса — `30` секунд (`timeoutIntervalForRequest`).
- **Даты.** Кастомная `dateDecodingStrategy` разбирает ISO 8601 как с дробными
  долями секунды, так и без них. Та же логика продублирована в `SocketService`,
  чтобы даты из REST и из сокета парсились одинаково.
- **Content-Type.** Для всех запросов проставляется `application/json`.
- **Авторизация.** Заголовок `Bearer` добавляется только если `requiresAuth == true`
  **и** токен установлен. Для публичных эндпоинтов (например, вход) передавайте
  `requiresAuth: false`.

### Как использовать

**1. Настроить адрес сервера** (обычно один раз при старте приложения):

```swift
NetworkService.shared.baseURL = "https://api.familytalk.example"
```

**2. GET-запрос с query-параметрами** — тип результата задаётся через возвращаемое
значение (type inference):

```swift
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

**3. POST с JSON-телом:**

```swift
struct CreateChat: Encodable { let type = "DIRECT"; let targetUserId: String }

let chat: Chat = try await NetworkService.shared.request(
    endpoint: "/chats",
    method: "POST",
    body: CreateChat(targetUserId: userId)
)
```

**4. Публичный запрос без авторизации:**

```swift
let response: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: name),
    requiresAuth: false
)
```

**5. Установка/сброс токена** (обычно вызывает `AuthService`, но контракт таков):

```swift
NetworkService.shared.setAccessToken(token)   // после входа
NetworkService.shared.clearAccessToken()       // при выходе
```

### На что обратить внимание

- Метод дженерик по `T: Decodable`: **всегда** аннотируйте тип принимающей
  переменной, иначе компилятор не выведет `T`.
- Для запросов без тела ответа (например, `DELETE`) заведите лёгкий тип-обёртку
  `struct OkResponse: Codable { let ok: Bool }` и декодируйте в него — так делают
  `ChatService` и `ContactsService`.
- Обработку `401` централизованно делать не нужно: подпишитесь на
  `.networkUnauthorized`, если требуется своя реакция; штатный разлогин уже
  обеспечивает `AuthService`.
