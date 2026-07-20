# FamilyTalk — Техническая документация (Backend / слой данных)

Документация описывает **бекенд-слой iOS-приложения**: сетевой клиент, сервисы,
работающие с REST API и WebSocket-сервером, а также модели данных.
UI-слой (`Views`) и презентационная логика (`ViewModels`) в этом документе
**не рассматриваются**.

Под «бекендом» здесь понимается всё, что обеспечивает обмен данными с сервером
и их хранение на устройстве:

```
FamilyTalk/
├── Services/     ← сетевой клиент, REST-сервисы, WebSocket, Keychain
└── Models/       ← Codable-модели, которыми обмениваются клиент и сервер
```

Приложение общается с сервером двумя способами:

* **REST (HTTP)** — запросы «запрос/ответ»: авторизация, история, списки,
  редактирование. Идёт через `NetworkService`.
* **WebSocket (Socket.IO)** — события реального времени: новые сообщения,
  статус набора текста, сигналинг звонков. Идёт через `SocketService`.

---

## Темы (модули)

Каждая тема расписывается в отдельном разделе ниже. Отмеченные `[x]` — уже
задокументированы, `[ ]` — ожидают документирования.

### Backend
- [x] **1. Networking Core** — `Services/NetworkService.swift` — базовый HTTP-клиент и обработка ошибок
- [ ] **2. Authentication** — `Services/AuthService.swift`, `Models/AuthResponse.swift` — вход, сессия, авто-логаут
- [ ] **3. Secure Storage** — `Services/KeychainService.swift` — хранение токена в Keychain
- [ ] **4. Realtime / Socket** — `Services/SocketService.swift` — WebSocket-события чата и звонков
- [ ] **5. Chat API** — `Services/ChatService.swift` — чаты и сообщения (REST)
- [ ] **6. Contacts API** — `Services/ContactsService.swift` — контакты, поиск, блокировки, профиль
- [ ] **7. Calls API** — `Services/CallService.swift` — история звонков (REST)
- [ ] **8. Data Models** — `Models/*.swift` — `User`, `Chat`, `Message`, `CallLog` и др.

### Frontend (не документируется в этом файле)
- Views / ViewModels — UI-слой, вне области бекенд-документации.

---

## 1. Networking Core — `NetworkService`

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### Назначение

`NetworkService` — это единая точка выполнения всех REST-запросов к серверу.
Модуль скрывает от остального кода детали работы с `URLSession`: сборку URL,
установку заголовков, подстановку токена авторизации, проверку HTTP-статусов и
декодирование JSON. Любой сервис, которому нужен HTTP, обращается только к
`NetworkService` и получает уже готовую типизированную модель.

Это самый нижний уровень бекенд-слоя: от него зависят все остальные сервисы,
а сам он не зависит ни от одного из них.

### Состав модуля

Файл содержит три части:

1. **`NetworkError`** — перечисление ошибок сети (`LocalizedError`).
2. **`Notification.Name.networkUnauthorized`** — событие «сервер вернул 401».
3. **`NetworkService`** — сам клиент (singleton).

### `NetworkError`

Типизированные ошибки, которые может вернуть любой запрос. Все сообщения
локализованы на русский язык через `errorDescription`.

| Кейс | Когда возникает |
|------|-----------------|
| `invalidURL` | Не удалось собрать URL из `baseURL + endpoint`. |
| `invalidResponse` | Ответ не является `HTTPURLResponse`. |
| `unauthorized` | Сервер вернул `401` (токен истёк/невалиден). |
| `httpError(statusCode:body:)` | Любой статус вне диапазона `200...299`. |
| `decodingError(Error)` | Тело ответа не удалось декодировать в ожидаемый тип. |
| `unknown(Error)` | Прочие непредвиденные ошибки. |

### Публичный интерфейс

```swift
final class NetworkService {
    static let shared = NetworkService()

    var baseURL: String                 // адрес сервера, по умолчанию http://localhost:3000
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

#### Свойства

* **`shared`** — singleton. Во всём приложении используется один экземпляр,
  чтобы `baseURL` и `accessToken` были общими для всех сервисов.
* **`baseURL`** — базовый адрес сервера. По умолчанию `http://localhost:3000`;
  этот же адрес использует `SocketService` для WebSocket-подключения.
* **`accessToken`** — JWT-токен доступа. Хранится в памяти и добавляется в
  заголовок `Authorization`. Только для чтения снаружи; изменяется через методы
  ниже.

#### Управление токеном

* **`setAccessToken(_:)`** — задать токен (вызывается после успешного логина или
  при восстановлении сессии).
* **`clearAccessToken()`** — сбросить токен (при выходе из аккаунта).

> Сам `NetworkService` **не** сохраняет токен на диск — это ответственность
> `AuthService` + `KeychainService`. Здесь токен живёт только в оперативной памяти.

### Ключевой метод: `request(...)`

Универсальный дженерик-метод для любого REST-запроса. Возвращаемый тип `T`
выводится из контекста вызова.

**Параметры:**

* `endpoint` — путь, дописываемый к `baseURL` (например, `/chats`).
* `method` — HTTP-метод: `"GET"` (по умолчанию), `"POST"`, `"PATCH"`, `"DELETE"`.
* `queryItems` — query-параметры (например, `?limit=50&cursor=...`).
* `body` — тело запроса, любой `Encodable`. Кодируется в JSON.
* `requiresAuth` — если `true` (по умолчанию), добавляется заголовок
  `Authorization: Bearer <token>`. Для публичных эндпоинтов (логин) передаётся
  `false`.

**Что делает метод по шагам:**

1. Собирает `URLComponents` из `baseURL + endpoint`, добавляет `queryItems`.
2. Ставит заголовок `Content-Type: application/json`.
3. Если `requiresAuth == true` и токен есть — добавляет `Authorization`.
4. Кодирует `body` в JSON (если передан).
5. Выполняет запрос через `URLSession` (`async/await`).
6. **Особый случай `401`:** публикует уведомление `.networkUnauthorized` и
   бросает `NetworkError.unauthorized` (см. ниже про авто-логаут).
7. Любой статус вне `200...299` → `NetworkError.httpError` (с телом ответа).
8. Успешный ответ декодируется в `T` кастомным `JSONDecoder`.

### Особенности реализации

* **Разбор дат.** `JSONDecoder` настроен на кастомную стратегию, которая парсит
  ISO 8601 **и с дробными секундами, и без них**. Это важно, потому что сервер
  может присылать `2026-04-23T10:00:00.123Z` или `2026-04-23T10:00:00Z`.
  Точно такая же стратегия продублирована в `SocketService` для payload’ов
  WebSocket.
* **Тайм-аут.** Запрос по умолчанию прерывается через 30 секунд
  (`timeoutIntervalForRequest = 30`).
* **Единый JSON-контракт.** Тела запросов и ответов — всегда JSON.

### Механизм авто-логаута (`.networkUnauthorized`)

Когда сервер отвечает `401` (токен истёк), `NetworkService` рассылает
`NotificationCenter`-уведомление `.networkUnauthorized`.

`AuthService` подписан на это уведомление и в ответ выполняет `logout()`.
Так реализован автоматический выход при протухшем токене, при этом
`NetworkService` ничего не знает об `AuthService` — связь односторонняя и
слабая (через `NotificationCenter`).

```
NetworkService ──(401)──▶ NotificationCenter ──▶ AuthService.logout()
```

### Взаимосвязи с другими модулями

| Модуль | Роль в связке |
|--------|---------------|
| `AuthService` | Логинится и восстанавливает сессию; задаёт/сбрасывает токен; слушает `.networkUnauthorized`. |
| `ChatService`, `ContactsService`, `CallService` | Оборачивают конкретные эндпоинты, вызывая `request(...)`. |
| `SocketService` | Не использует `request(...)`, но берёт у `NetworkService` `baseURL` для WebSocket-подключения. |
| Модели (`Models/*`) | Выступают типами `T` при декодировании ответов и телами запросов. |

Схема зависимостей (стрелка — «использует»):

```
AuthService ─┐
ChatService ─┤
ContactsService ─┼──▶ NetworkService ──▶ URLSession
CallService ─┘
SocketService ──▶ NetworkService.baseURL (только адрес)
```

### Как использовать

**Пример 1. GET с типизированным ответом.**

```swift
// Ответ автоматически декодируется в ChatsResponse
let response: ChatsResponse = try await NetworkService.shared.request(
    endpoint: "/chats"
)
```

**Пример 2. POST с телом и без авторизации (логин).**

```swift
let auth: AuthResponse = try await NetworkService.shared.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: name),
    requiresAuth: false
)
```

**Пример 3. GET с query-параметрами.**

```swift
let page: MessagesPage = try await NetworkService.shared.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)
```

**Пример 4. Обработка ошибок.**

```swift
do {
    let user: User = try await NetworkService.shared.request(endpoint: "/auth/me")
} catch let error as NetworkError {
    // error.errorDescription уже локализован на русский
    print(error.errorDescription ?? "Ошибка")
}
```

### Важно при использовании

* Метод дженерик — **обязательно указывайте ожидаемый тип** результата
  (`let x: SomeType = try await ...`), иначе компилятор не сможет вывести `T`.
* Не обращайтесь к `URLSession` напрямую из сервисов — весь HTTP идёт через
  `NetworkService`, чтобы единообразно работали токен, даты и обработка ошибок.
* Токен в памяти теряется при перезапуске приложения; его восстановление —
  задача `AuthService` (тема 2).
