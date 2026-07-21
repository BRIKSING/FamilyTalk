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
| ⬜ | **SocketService** | `Services/SocketService.swift` | Обмен событиями в реальном времени поверх Socket.IO |

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
