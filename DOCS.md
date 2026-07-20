# FamilyTalk — Документация бэкенд-слоя

Этот документ описывает **сетевой / сервисный (бэкенд) слой** iOS-приложения
FamilyTalk: классы из каталогов `FamilyTalk/Services/` и модели данных из
`FamilyTalk/Models/`. UI-слой (`FamilyTalk/Views/`) и слой представления
(`FamilyTalk/ViewModels/`) в этом документе **не рассматриваются**.

> Под «бэкендом» здесь понимается клиентский слой доступа к данным: HTTP-клиент,
> работа с реальным временем через Socket.IO, безопасное хранилище и модели,
> которыми обмениваются клиент и сервер. Сам серверный код в этом репозитории
> не находится — сервис общается с REST/WebSocket API по адресу `baseURL`.

## Как читать этот документ

Каждая тема ниже соответствует одному модулю бэкенда. Темы расписываются
по одной. Отметки статуса:

- `[x]` — тема расписана;
- `[ ]` — тема ещё не расписана.

## Темы по модулям

### Сервисы (`FamilyTalk/Services/`)

- [x] **NetworkService** — базовый HTTP-клиент, ядро всех REST-запросов
- [ ] **AuthService** — авторизация, сессия пользователя, хранение токена
- [ ] **KeychainService** — безопасное хранилище (access token) в Keychain
- [ ] **SocketService** — реальное время: сообщения, набор текста, сигналинг звонков (Socket.IO)
- [ ] **ChatService** — REST-операции с чатами и сообщениями
- [ ] **ContactsService** — REST-операции с контактами, поиском и профилем
- [ ] **CallService** — REST-история звонков

### Модели (`FamilyTalk/Models/`)

- [ ] **Модели данных** — `User`, `Chat`, `Message`, `CallLog`, `AuthResponse` и вложенные типы

---

## NetworkService

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — это единая точка выполнения всех REST-запросов к серверу.
Все остальные сервисы (`AuthService`, `ChatService`, `ContactsService`,
`CallService`) не работают с `URLSession` напрямую, а обращаются к общему
экземпляру `NetworkService.shared`. Модуль решает четыре задачи:

1. Собирает `URLRequest` (URL, метод, query-параметры, заголовки, тело).
2. Подставляет заголовок авторизации `Bearer <token>` для защищённых запросов.
3. Разбирает HTTP-ответ, приводит статус-коды к типизированным ошибкам.
4. Декодирует тело ответа из JSON в нужный `Decodable`-тип.

Это самый нижний уровень бэкенда: от него зависят почти все остальные модули,
а сам он не зависит ни от одного сервиса приложения.

### Публичный интерфейс

```swift
final class NetworkService {
    static let shared: NetworkService

    var baseURL: String            // по умолчанию "http://localhost:3000"
    private(set) var accessToken: String?

    func setAccessToken(_ token: String)
    func clearAccessToken()

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T
}
```

- **Синглтон.** Доступ только через `NetworkService.shared`; инициализатор
  приватный. Это гарантирует единый `baseURL`, единый токен и единый
  сконфигурированный `URLSession` на всё приложение.
- **`baseURL`** — базовый адрес сервера. Тот же адрес использует
  `SocketService` для WebSocket-подключения (см. соответствующую тему).
- **`accessToken`** — текущий токен доступа. Снаружи только читается
  (`private(set)`); меняется через `setAccessToken(_:)` / `clearAccessToken()`.

### Ключевой метод `request(...)`

Дженерик-метод, который возвращает уже декодированную модель `T`.
Тип `T` выводится из контекста присваивания:

```swift
// T выводится как [Chat] из объявления слева
let chats: ChatsResponse = try await network.request(endpoint: "/chats")
```

Параметры:

| Параметр | По умолчанию | Назначение |
|----------|--------------|------------|
| `endpoint` | — | Путь, добавляемый к `baseURL` (например `"/auth/me"`). |
| `method` | `"GET"` | HTTP-метод: `GET`, `POST`, `PATCH`, `DELETE`. |
| `queryItems` | `nil` | Query-параметры URL (например `?limit=50`). |
| `body` | `nil` | Тело запроса; любой `Encodable`, кодируется в JSON. |
| `requiresAuth` | `true` | Нужно ли добавлять заголовок `Authorization`. |

Порядок работы метода:

1. Собирает URL через `URLComponents(baseURL + endpoint)` и добавляет
   `queryItems`. При некорректном URL бросает `NetworkError.invalidURL`.
2. Ставит заголовок `Content-Type: application/json`.
3. Если `requiresAuth == true` **и** токен задан — добавляет
   `Authorization: Bearer <token>`. Если токена нет, запрос уходит без него
   (сервер вернёт 401, см. ниже).
4. Кодирует `body` в JSON (если он передан).
5. Выполняет запрос через общий `URLSession` (таймаут — 30 секунд).
6. Обрабатывает статус-код и декодирует ответ.

### Обработка ошибок

Все ошибки приводятся к типу `NetworkError` (соответствует `LocalizedError`,
`errorDescription` — на русском языке, пригоден для показа в UI):

| Случай | Ошибка |
|--------|--------|
| Некорректный URL | `.invalidURL` |
| Ответ — не `HTTPURLResponse` | `.invalidResponse` |
| Статус `401` | `.unauthorized` (+ уведомление, см. ниже) |
| Статус вне `200...299` | `.httpError(statusCode:body:)` |
| Ошибка декодирования JSON | `.decodingError(Error)` |
| Прочее | `.unknown(Error)` |

### Событие «неавторизован» (401)

При получении статуса `401` метод, помимо выбрасывания
`NetworkError.unauthorized`, публикует уведомление:

```swift
NotificationCenter.default.post(name: .networkUnauthorized, object: nil)
```

Имя `Notification.Name.networkUnauthorized` объявлено в этом же файле.
Это механизм **разрыва циклической зависимости**: `NetworkService` ничего не
знает про `AuthService`, но `AuthService` подписан на это уведомление и при его
получении выполняет `logout()` (сбрасывает сессию, отключает сокет). Таким
образом протухший токен автоматически приводит к выходу из аккаунта из любого
места приложения.

### Декодирование дат

`JSONDecoder` настроен на разбор дат в формате **ISO 8601**, причём
поддерживаются оба варианта — с дробными секундами (`.withFractionalSeconds`)
и без них. Сначала пробуется формат с дробными секундами, затем — без.
Если ни один не подошёл, бросается `DecodingError`. Аналогичная стратегия
продублирована в `SocketService` для payload'ов, приходящих по WebSocket.

### Взаимосвязи с другими модулями

```
                 setAccessToken / clearAccessToken
AuthService ───────────────────────────────────────▶ NetworkService
     ▲                                                     │
     │  .networkUnauthorized (при 401)                     │ request<T>(...)
     └─────────────────────────────────────────────────────┤
                                                            │
ChatService ─────────┐                                      │
ContactsService ─────┼──────  request<T>(...)  ────────────▶│──▶ Сервер (REST)
CallService ─────────┘                                      │
                                                            │
SocketService ── использует только baseURL ────────────────┘
```

- **Зависит от:** только от Foundation (`URLSession`, `URLComponents`,
  `JSONDecoder`/`JSONEncoder`, `NotificationCenter`). От сервисов приложения
  не зависит — это делает его самым низкоуровневым модулем.
- **От него зависят:** `AuthService`, `ChatService`, `ContactsService`,
  `CallService` — все делают запросы через `request(...)`.
- **`AuthService`** управляет токеном: после логина вызывает `setAccessToken`,
  при выходе — `clearAccessToken`; также подписан на `.networkUnauthorized`.
- **`SocketService`** использует только `baseURL` (для адреса WebSocket),
  но не метод `request`.

### Как использовать

Типовой вызов из сервиса — задать возвращаемый тип и путь:

```swift
// GET c авторизацией (по умолчанию requiresAuth = true)
let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")

// POST без авторизации, с телом запроса
let response: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false
)

// GET с query-параметрами
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

Рекомендации:

- **Не создавайте `URLSession` в сервисах** — всегда идите через
  `NetworkService.shared.request(...)`, чтобы получить единые заголовки,
  авторизацию, декодирование дат и обработку 401.
- **Возвращаемый тип должен быть `Decodable`.** Для «обёрток» ответа
  (`{ "chats": [...] }`) заводите приватную структуру-обёртку внутри
  конкретного сервиса (как это сделано в `ChatService`, `ContactsService`).
- **Ошибки** ловите как `NetworkError` и показывайте `errorDescription`;
  отдельно можно реагировать на `.unauthorized`, но обычно достаточно
  глобального обработчика в `AuthService`.
