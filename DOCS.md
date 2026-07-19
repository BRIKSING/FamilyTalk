# DOCS.md — Техническая документация бэкенд-слоя FamilyTalk (iOS)

Документация сетевого/сервисного слоя приложения FamilyTalk. Под «бэкендом» здесь
понимается data/service-слой iOS-клиента (`FamilyTalk/Services` и `FamilyTalk/Models`) —
то, что инкапсулирует общение с сервером, хранение сессии и real-time события.
Слои `Views/` и `ViewModels/` (фронтенд) здесь **не документируются**.

## Архитектура слоя

```
ViewModels ──> Services ──> NetworkService ──> URLSession ──> REST API
                  │              │
                  │              └──> Notification (.networkUnauthorized)
                  ├──> KeychainService (токен)
                  └──> SocketService (real-time, Socket.io)
```

Все сервисы — синглтоны (`static let shared`) и общаются с сервером исключительно
через единый `NetworkService`. Авторизационный токен хранится в Keychain и
подставляется в каждый запрос автоматически.

## Темы по модулям (этапы документирования)

- [x] **NetworkService** — базовый HTTP-клиент (async/await, JSON, авторизация, ошибки)
- [ ] **KeychainService** — безопасное хранилище токена
- [ ] **AuthService** — авторизация, сессия, восстановление входа
- [ ] **SocketService** — real-time события через Socket.io
- [ ] **ContactsService** — контакты, поиск, блокировки
- [ ] **ChatService** — чаты и сообщения
- [ ] **CallService** — история звонков и сигналинг
- [ ] **Models** — модели данных (User, Chat, Message, CallLog, AuthResponse)

---

## NetworkService

Файл: `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — единая точка входа для всех HTTP-запросов к REST API.
Это тонкий обобщённый (generic) клиент поверх `URLSession`, который берёт на себя:

- сборку URL из `baseURL` + endpoint + query-параметров;
- сериализацию тела запроса в JSON и десериализацию ответа в любой `Decodable`;
- подстановку заголовка авторизации `Bearer <token>`;
- единообразную обработку HTTP-ошибок через типизированный `NetworkError`;
- централизованную реакцию на `401 Unauthorized` (broadcast через `NotificationCenter`);
- корректный разбор дат ISO 8601 (с дробными секундами и без них).

Реализован как синглтон: `NetworkService.shared`. Все остальные сервисы держат
ссылку `private let network = NetworkService.shared` и не создают собственных
`URLSession`.

### Публичный интерфейс

| Член | Тип | Описание |
|------|-----|----------|
| `shared` | `NetworkService` | Единственный экземпляр (синглтон). |
| `baseURL` | `String` | Базовый адрес сервера. По умолчанию `http://localhost:3000`. Задаётся при конфигурации. |
| `accessToken` | `String?` (`private(set)`) | Текущий токен доступа. Меняется только через методы ниже. |
| `setAccessToken(_:)` | `(String) -> Void` | Установить токен для последующих запросов. |
| `clearAccessToken()` | `() -> Void` | Сбросить токен (например, при logout). |
| `request(endpoint:method:queryItems:body:requiresAuth:)` | `async throws -> T` | Выполнить запрос и вернуть декодированный ответ типа `T: Decodable`. |

#### Сигнатура основного метода

```swift
func request<T: Decodable>(
    endpoint: String,                 // путь, напр. "/auth/login"
    method: String = "GET",           // HTTP-метод
    queryItems: [URLQueryItem]? = nil,// query-параметры
    body: (any Encodable)? = nil,     // тело запроса (кодируется в JSON)
    requiresAuth: Bool = true         // подставлять ли Bearer-токен
) async throws -> T
```

Возвращаемый тип `T` выводится из контекста присваивания — это ключевая идиома
использования (см. примеры ниже).

### Обработка ошибок — `NetworkError`

Метод `request` бросает только `NetworkError` (`LocalizedError`, с русскими
`errorDescription`):

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | Не удалось собрать URL из `baseURL` + endpoint. |
| `.invalidResponse` | Ответ не является `HTTPURLResponse`. |
| `.unauthorized` | Сервер вернул `401`. Дополнительно рассылается уведомление (см. ниже). |
| `.httpError(statusCode:body:)` | Любой статус вне диапазона `200...299`. Тело ответа передаётся строкой. |
| `.decodingError(Error)` | Ответ не удалось декодировать в `T`. |
| `.unknown(Error)` | Прочие ошибки. |

### Побочный эффект: реакция на 401

При получении `401` сервис **до** выброса ошибки публикует уведомление:

```swift
NotificationCenter.default.post(name: .networkUnauthorized, object: nil)
```

Имя `Notification.Name.networkUnauthorized` объявлено в этом же файле. На него
подписан `AuthService`, который выполняет `logout()` — так протухший токен
приводит к автоматическому выходу из сессии по всему приложению. Это единственная
точка, где сетевой слой связан с бизнес-логикой (через слабую связь — уведомление).

### Разбор дат

`JSONDecoder` настроен на кастомную стратегию дат: сначала пробуется ISO 8601 с
дробными секундами (`.withFractionalSeconds`), затем без них. Благодаря этому
поля вроде `createdAt`, `lastSeen`, `timestamp` в моделях декодируются как `Date`
независимо от точности, которую отдаёт сервер.

### Взаимосвязи с другими модулями

- **Потребители** (все через `NetworkService.shared`): `AuthService`,
  `ContactsService`, `ChatService`, `CallService`. Каждый вызывает `request(...)`
  для своих endpoint'ов.
- **`AuthService`** дополнительно вызывает `setAccessToken` / `clearAccessToken`
  при входе/выходе и подписан на `.networkUnauthorized`.
- **`SocketService`** читает `NetworkService.shared.baseURL`, чтобы подключить
  Socket.io к тому же хосту.
- **Модели** (`User`, `Chat`, `Message`, ...) — это типы `T`, в которые
  десериализуются ответы.
- **Зависимости самого модуля**: только `Foundation` (`URLSession`,
  `JSONDecoder`/`JSONEncoder`, `NotificationCenter`). Внешних пакетов нет.

### Как использовать

**1. Конфигурация при старте приложения** (один раз задать адрес сервера):

```swift
NetworkService.shared.baseURL = "https://api.familytalk.example.com"
```

**2. GET без тела** — тип ответа задаётся аннотацией переменной:

```swift
let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")
```

**3. POST с телом** (`body` — любой `Encodable`), для публичного endpoint'а
без токена:

```swift
let response: AuthResponse = try await network.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false
)
```

**4. GET с query-параметрами**:

```swift
let items = [URLQueryItem(name: "q", value: query)]
let response: UsersResponse = try await network.request(
    endpoint: "/users/search",
    queryItems: items
)
```

**5. Запрос без осмысленного тела ответа** (сервер отвечает `{ "ok": true }`) —
используйте служебную модель и `_`:

```swift
let _: OkResponse = try await network.request(
    endpoint: "/users/\(id)/block",
    method: "POST"
)
```

**6. Обработка ошибок**:

```swift
do {
    let user: User = try await network.request(endpoint: "/auth/me")
} catch let error as NetworkError {
    print(error.errorDescription ?? "Ошибка сети")
}
```

### Замечания и ограничения

- Нет автоматического refresh токена: на `401` сессия просто завершается.
- Нет retry-логики при сетевых сбоях — вызывающий код обрабатывает ошибку сам.
- `body` кодируется свежим `JSONEncoder()` со стандартной стратегией дат (даты
  уходят как ISO 8601 по умолчанию Foundation); настроен под кастомную стратегию
  только декодер.
- Таймаут запроса — 30 секунд (`timeoutIntervalForRequest`).

---

*Документируется по модулям. Следующая тема: **KeychainService**.*
