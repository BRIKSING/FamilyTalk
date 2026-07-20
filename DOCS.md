# FamilyTalk — Документация бекенд-модулей

Документ описывает бекенд-слой iOS-приложения **FamilyTalk** (сетевые сервисы,
работа с хранилищем, realtime-транспорт и модели данных). Документация
пополняется по одной теме за итерацию. Фронтенд-слой (`Views/`, `ViewModels/`)
в этот документ не входит.

## Оглавление тем (по модулям)

Ниже — список тем бекенда. Отмеченные `[x]` уже расписаны, `[ ]` — ожидают
документирования.

- [x] **NetworkService** — базовый HTTP-транспорт, авторизация запросов, обработка ошибок
- [ ] **KeychainService** — безопасное хранение токена доступа в Keychain
- [ ] **AuthService** — аутентификация, жизненный цикл сессии
- [ ] **SocketService** — realtime-транспорт (WebSocket), доставка событий
- [ ] **ChatService** — REST-операции над чатами и сообщениями
- [ ] **CallService** — REST-операции над звонками и историей вызовов
- [ ] **ContactsService** — REST-операции над контактами
- [ ] **Models** — доменные модели данных (`User`, `Chat`, `Message`, `CallLog`, `AuthResponse`)

---

## NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — это единая точка входа для всех HTTP-запросов к бекенду.
Модуль инкапсулирует конфигурацию `URLSession`, сборку `URLRequest`,
подстановку токена авторизации, разбор HTTP-статусов и декодирование JSON в
доменные модели. Все остальные сетевые сервисы (`AuthService`, `ChatService`,
`CallService`, `ContactsService`) работают поверх него и не создают запросы
самостоятельно.

Это синглтон: доступ осуществляется через `NetworkService.shared`.

### Публичный интерфейс

| Член | Тип | Описание |
| --- | --- | --- |
| `shared` | `static NetworkService` | Единственный экземпляр сервиса. |
| `baseURL` | `var String` | Базовый адрес API. По умолчанию `http://localhost:3000`. |
| `accessToken` | `private(set) String?` | Текущий Bearer-токен. Меняется только через методы ниже. |
| `setAccessToken(_:)` | `func` | Устанавливает токен для последующих авторизованных запросов. |
| `clearAccessToken()` | `func` | Сбрасывает токен (например, при выходе из аккаунта). |
| `request(endpoint:method:queryItems:body:requiresAuth:)` | `async throws -> T` | Универсальный дженерик-метод выполнения запроса. |

### Основной метод `request`

```swift
func request<T: Decodable>(
    endpoint: String,
    method: String = "GET",
    queryItems: [URLQueryItem]? = nil,
    body: (any Encodable)? = nil,
    requiresAuth: Bool = true
) async throws -> T
```

Параметры:

- `endpoint` — путь, дописываемый к `baseURL` (например, `"/auth/me"`).
- `method` — HTTP-метод (`"GET"`, `"POST"`, …). По умолчанию `GET`.
- `queryItems` — необязательные query-параметры URL.
- `body` — необязательное тело запроса; кодируется в JSON через `JSONEncoder`.
- `requiresAuth` — если `true` (по умолчанию) и токен установлен, в заголовок
  `Authorization` подставляется `Bearer <token>`.

Возвращаемый тип `T` выводится из контекста вызова — метод сам декодирует ответ
в нужную `Decodable`-модель.

### Обработка ошибок

Ошибки транспорта описаны перечислением `NetworkError` (`LocalizedError`,
локализованные сообщения на русском):

| Case | Когда возникает |
| --- | --- |
| `.invalidURL` | Не удалось собрать `URL` из `baseURL + endpoint`. |
| `.invalidResponse` | Ответ не является `HTTPURLResponse`. |
| `.unauthorized` | HTTP-статус `401`. |
| `.httpError(statusCode:body:)` | Любой статус вне диапазона `200...299`. |
| `.decodingError(Error)` | Ошибка декодирования тела ответа в `T`. |
| `.unknown(Error)` | Прочие непредвиденные ошибки. |

### Декодирование дат

`JSONDecoder` настроен на кастомную стратегию дат: сначала пытается разобрать
ISO 8601 **с** дробными секундами (`.withFractionalSeconds`), затем — **без**
них. Это позволяет корректно принимать метки времени от бекенда в обоих
форматах.

### Взаимосвязи с другими модулями

- **`AuthService`** вызывает `setAccessToken` / `clearAccessToken` при входе и
  выходе и выполняет запросы `/auth/login`, `/auth/me` через `request`.
- **`ChatService`, `CallService`, `ContactsService`** используют `request` для
  всех своих REST-операций.
- **Событие `.networkUnauthorized`** — при получении статуса `401`
  `NetworkService` публикует нотификацию `Notification.Name.networkUnauthorized`
  через `NotificationCenter`. На неё подписан `AuthService`, который при этом
  автоматически завершает сессию (`logout`). Так централизованно
  обрабатывается протухший токен.

### Пример использования

```swift
// GET с авторизацией — тип результата выводится из аннотации.
let me: User = try await NetworkService.shared.request(endpoint: "/auth/me")

// POST без авторизации и с телом запроса.
let response: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: name),
    requiresAuth: false
)

// GET с query-параметрами.
let chats: [Chat] = try await NetworkService.shared.request(
    endpoint: "/chats",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

### Замечания по эксплуатации

- Значение `baseURL` по умолчанию указывает на локальный сервер разработки
  (`http://localhost:3000`) — перед сборкой на устройство его нужно заменить на
  адрес рабочего API.
- Таймаут запроса — 30 секунд (`timeoutIntervalForRequest`).
- Подписку на `.networkUnauthorized` держит `AuthService`; при добавлении новых
  сервисов не требуется дублировать обработку `401` — она уже централизована.
