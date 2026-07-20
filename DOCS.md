# FamilyTalk — Техническая документация (Backend)

Документация описывает **бэкенд-слой iOS-клиента** FamilyTalk — то есть код,
который отвечает за работу с сетью, реальным временем, хранением данных и
доменными моделями. UI-слой (`Views/`, `ViewModels/`) в этом документе
намеренно **не** рассматривается.

Под «бэкендом клиента» здесь понимаются:

- `FamilyTalk/Models/` — доменные модели (DTO), которыми обмениваемся с сервером;
- `FamilyTalk/Services/` — сервисы: сеть, сокеты, авторизация, хранилище.

> **Как читать документ.** Каждый модуль описан по единой схеме:
> *назначение → зависимости → публичный API → как использовать → важные нюансы*.
> Раздел «Темы по модулям» ниже — это оглавление и трекер статуса. Незакрытые
> темы (`[ ]`) документируются по одной, сверху вниз.

---

## Темы по модулям (статус документирования)

| # | Модуль | Файлы | Статус |
|---|--------|-------|--------|
| 1 | **Сетевой слой (Network Layer)** | `Services/NetworkService.swift` | [x] Готово |
| 2 | Доменные модели (Domain Models) | `Models/*.swift` | [ ] |
| 3 | Авторизация и сессия (Auth & Session) | `Services/AuthService.swift`, `Services/KeychainService.swift` | [ ] |
| 4 | Чаты и сообщения (REST) | `Services/ChatService.swift` | [ ] |
| 5 | Реалтайм-слой (Socket.IO) | `Services/SocketService.swift` | [ ] |
| 6 | Звонки (Calls) | `Services/CallService.swift` | [ ] |
| 7 | Контакты и пользователи | `Services/ContactsService.swift` | [ ] |

---

## 1. Сетевой слой — `NetworkService`

**Файл:** `FamilyTalk/Services/NetworkService.swift`

### 1.1. Назначение

`NetworkService` — это единая точка входа для всех **REST-запросов** к бэкенду.
Через него проходит любой HTTP-вызов приложения: авторизация, чаты, сообщения,
контакты, история звонков. Сервис инкапсулирует:

- сборку `URLRequest` (базовый URL, метод, query-параметры, JSON-тело);
- подстановку токена авторизации (`Bearer`);
- декодирование JSON-ответа в типизированную модель (`Decodable`);
- единый разбор ошибок и HTTP-статусов;
- глобальную реакцию на `401 Unauthorized`.

Важно: **реалтайм-события (сообщения, звонки, «печатает…») идут не через
`NetworkService`, а через `SocketService`** (Socket.IO). `NetworkService`
отвечает только за «классический» запрос-ответ по HTTP.

### 1.2. Место в архитектуре и зависимости

`NetworkService` — это **низкоуровневый фундамент**. От него зависят все
остальные сервисы, но сам он не зависит ни от одного из них:

```
AuthService ─┐
ChatService ─┤
CallService ─┼──▶ NetworkService ──▶ URLSession ──▶ Backend (HTTP :3000)
ContactsSvc ─┤
   ...       ─┘
```

- **Зависит от:** только от `Foundation` / `URLSession`.
- **От него зависят:** `AuthService`, `ChatService`, `CallService`,
  `ContactsService` (каждый держит ссылку `private let network = NetworkService.shared`).
- **Связь с `AuthService`:** двусторонняя, но слабая и через уведомления, а не
  через прямую ссылку:
  - `AuthService` вызывает `setAccessToken(_:)` / `clearAccessToken()`, чтобы
    сообщить сети текущий токен;
  - `NetworkService` при ответе `401` шлёт `NotificationCenter`-уведомление
    `.networkUnauthorized`, на которое `AuthService` подписан и делает `logout()`.
  Таким образом сетевой слой ничего не знает про модель авторизации — он лишь
  сигнализирует «токен больше не валиден».

### 1.3. Публичный API

```swift
final class NetworkService {
    static let shared: NetworkService          // синглтон

    var baseURL: String                        // по умолчанию "http://localhost:3000"
    private(set) var accessToken: String?      // только чтение снаружи

    func setAccessToken(_ token: String)       // установить Bearer-токен
    func clearAccessToken()                     // сбросить токен (logout)

    func request<T: Decodable>(
        endpoint: String,                       // например "/chats/\(id)/messages"
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
    ) async throws -> T
}
```

Единственный «рабочий» метод — `request(...)`. Это дженерик: тип возвращаемого
значения `T` выводится из контекста присваивания на стороне вызывающего кода.

#### Ошибки — `NetworkError`

Все ошибки нормализуются к единому перечислению `NetworkError: LocalizedError`:

| Кейс | Когда возникает |
|------|-----------------|
| `.invalidURL` | не удалось собрать `URL` из `baseURL + endpoint` |
| `.invalidResponse` | ответ не является `HTTPURLResponse` |
| `.unauthorized` | HTTP `401` (дополнительно шлётся `.networkUnauthorized`) |
| `.httpError(statusCode:body:)` | статус вне диапазона `200...299` |
| `.decodingError(Error)` | тело ответа не разобралось в `T` |
| `.unknown(Error)` | прочие ошибки транспорта |

У каждого кейса есть локализованное (русское) `errorDescription`, которое можно
показывать пользователю.

### 1.4. Как использовать

Сервисы более высокого уровня **не создают** запросы руками — они оборачивают
`request(...)` в доменные методы. Примеры из кодовой базы:

```swift
// GET с типизированным ответом
let chats: [Chat] = try await network.request(endpoint: "/chats")

// POST с телом запроса, без авторизации (логин)
let response: AuthResponse = try await network.request(
    endpoint: "/auth/login",
    method: "POST",
    body: LoginRequest(phone: phone, displayName: displayName),
    requiresAuth: false
)

// GET с query-параметрами (пагинация по курсору)
let page: MessagesPage = try await network.request(
    endpoint: "/chats/\(chatId)/messages",
    queryItems: [URLQueryItem(name: "limit", value: "50")]
)

// DELETE — если тело ответа не нужно, декодируем в маленький OkResponse
struct OkResponse: Codable { let ok: Bool }
let _: OkResponse = try await network.request(
    endpoint: "/users/\(id)/block",
    method: "DELETE"
)
```

**Рекомендация при добавлении нового эндпоинта:** создавайте доменный метод в
соответствующем сервисе (`ChatService`, `ContactsService`, …), а не вызывайте
`NetworkService.request` напрямую из ViewModel. Так вся сетевая логика остаётся
в слое сервисов.

### 1.5. Важные нюансы реализации

- **Авторизация.** Если `requiresAuth == true` и токен установлен, в заголовок
  добавляется `Authorization: Bearer <token>`. Публичные эндпоинты (логин)
  вызываются с `requiresAuth: false`.
- **Обработка `401`.** При статусе `401` сервис постит `.networkUnauthorized`
  через `NotificationCenter` и бросает `NetworkError.unauthorized`. Подписчик
  (`AuthService`) выполняет `logout()`. Это централизует «протух токен → выкинуть
  на экран логина».
- **Парсинг дат.** `JSONDecoder` настроен на кастомную стратегию: сначала
  пробуется ISO 8601 **с** дробными секундами (`.withFractionalSeconds`), затем
  **без** них. Это защищает от расхождений в формате дат, которые отдаёт сервер.
  Аналогичная стратегия продублирована в `SocketService` для сокет-payload’ов.
- **Таймаут.** `timeoutIntervalForRequest = 30` секунд на запрос.
- **Content-Type.** Для всех запросов выставляется `application/json`. Тело
  кодируется стандартным `JSONEncoder` (без спец-настроек дат — сервер ожидает
  ISO-строки, которые модели формируют сами).
- **Потокобезопасность.** `request(...)` — `async` и безопасен для вызова из
  любого контекста; побочные эффекты в UI вызывающая сторона должна
  переносить на `@MainActor`.

---
