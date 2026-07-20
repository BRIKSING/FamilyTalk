# FamilyTalk — Техническая документация бэкенда

Этот документ описывает **бэкенд-слой** iOS-приложения FamilyTalk: доменные
модели, сетевые сервисы, слой ViewModels и вспомогательные утилиты. Цель —
чтобы разработчик мог понять назначение каждого модуля, его связи с другими
модулями и способ использования, не читая весь исходный код.

> **Область документирования.** Здесь документируется только бэкенд-код
> (`Models/`, `Services/`, `ViewModels/`, `Utilities/`). Слой представления
> (`Views/`, SwiftUI-экраны и компоненты) намеренно не описывается.

## Архитектура (общая картина)

```
Views (SwiftUI)          ← слой представления (не документируется здесь)
   │  @Environment / @Bindable
   ▼
ViewModels (@Observable) ← состояние экранов, вызывают сервисы
   │
   ▼
Services                 ← бизнес-логика и работа с сетью
   │  NetworkService (HTTP)  •  SocketService (real-time)  •  KeychainService (хранилище)
   ▼
Models (Codable)         ← доменные модели, общие для всех слоёв
```

Ключевые принципы: MVVM, `@Observable` для ViewModels, `async/await` для
сетевых вызовов, единый `NetworkService` как HTTP-ядро и `SocketService`
для real-time событий.

## Индекс тем (по модулям)

| # | Тема (модуль) | Слой | Статус |
|---|---------------|------|--------|
| 1 | Модели данных (`Models/`) | Данные | ✅ Задокументировано |
| 2 | `NetworkService` — HTTP-ядро | Сеть | ⬜ Не задокументировано |
| 3 | `KeychainService` — безопасное хранилище | Сеть/хранилище | ⬜ Не задокументировано |
| 4 | `AuthService` — авторизация | Сервисы | ⬜ Не задокументировано |
| 5 | `ChatService` — чаты и сообщения | Сервисы | ⬜ Не задокументировано |
| 6 | `CallService` — звонки | Сервисы | ⬜ Не задокументировано |
| 7 | `ContactsService` — контакты | Сервисы | ⬜ Не задокументировано |
| 8 | `SocketService` — real-time события | Сеть | ⬜ Не задокументировано |
| 9 | ViewModels (`ViewModels/`) | Состояние | ⬜ Не задокументировано |
| 10 | Утилиты (`Utilities/MockData`) | Вспомогательное | ⬜ Не задокументировано |

> Легенда: ✅ — тема расписана ниже; ⬜ — тема запланирована, но ещё не расписана.

---

## 1. Модели данных (`Models/`)

### Назначение

Модуль `Models/` содержит **доменные модели** — структуры данных, которыми
оперирует всё приложение. Это единый «язык» между сетевым слоем и UI: сервисы
декодируют в эти типы JSON-ответы бэкенда, ViewModels хранят их в своём
состоянии, а Views отображают.

Все модели — это `struct` (value types) и соответствуют требованиям Swift 6:
неизменяемые (`let`) поля для серверных идентификаторов и изменяемые (`var`)
для полей, которые обновляются локально (например, оптимистичные сообщения).

### Файлы модуля

| Файл | Основные типы | Отвечает за |
|------|---------------|-------------|
| `User.swift` | `User` | Профиль пользователя, online-статус |
| `AuthResponse.swift` | `AuthResponse`, `LoginRequest` | DTO авторизации |
| `Chat.swift` | `Chat`, `ChatMember`, `ChatType` | Чат и его участники |
| `Message.swift` | `Message`, `MessageReplyPreview`, `MessageType` | Сообщение и ответ-цитата |
| `CallLog.swift` | `CallLog`, `CallType`, `CallStatus` | Запись о звонке |

### Описание типов

#### `User` (`User.swift`)

Профиль пользователя. Соответствует `Identifiable`, `Codable`, `Equatable`.

| Поле | Тип | Примечание |
|------|-----|------------|
| `id` | `String` | Идентификатор с сервера (неизменяемый) |
| `displayName` | `String` | Отображаемое имя |
| `phone` | `String?` | Номер телефона |
| `username` | `String?` | Никнейм для поиска |
| `avatarUrl` | `String?` | URL аватара |
| `bio` | `String?` | О себе |
| `lastSeen` | `Date?` | Время последней активности |

Вычисляемые свойства (бизнес-логика на клиенте):

- `isOnline: Bool` — `true`, если `lastSeen` был менее 30 секунд назад.
- `lastSeenText: String` — человекочитаемая строка присутствия
  («только что», «N мин назад», «N ч назад», иначе дата `dd.MM.yyyy`).

#### `AuthResponse` и `LoginRequest` (`AuthResponse.swift`)

DTO (Data Transfer Objects) для авторизации:

- `LoginRequest { phone, displayName }` — тело запроса `POST /auth/login`.
- `AuthResponse { accessToken, user }` — ответ сервера: JWT-токен доступа и
  профиль вошедшего пользователя.

Используются `AuthService` для сериализации запроса и разбора ответа.

#### `Chat`, `ChatMember`, `ChatType` (`Chat.swift`)

- `ChatType` — перечисление типа чата с raw-строками бэкенда:
  `.direct = "DIRECT"`, `.group = "GROUP"`.
- `ChatMember { chatId, userId, joinedAt, user? }` — участник чата.
  `id` вычисляется из `userId` (для `Identifiable`).
- `Chat { id, type, name?, avatarUrl?, createdAt, members, lastMessage?, unreadCount }`
  — сам чат. Соответствует `Hashable` (равенство и хеш — только по `id`),
  поэтому пригоден для использования в `NavigationStack` и `Set`.

Вспомогательные методы:

- `displayName(currentUserId:)` — имя для показа: для группы возвращает `name`
  (или «Групповой чат»), для личного — имя собеседника.
- `otherUser(currentUserId:)` — собеседник в личном чате (первый участник,
  чей `userId` не совпадает с текущим пользователем).

#### `Message`, `MessageReplyPreview`, `MessageType` (`Message.swift`)

- `MessageType` — `.text = "TEXT"`, `.system = "SYSTEM"`.
- `MessageReplyPreview { id, senderId, content?, type, deletedAt? }` —
  укороченное превью сообщения-оригинала для ответа-цитаты; `isDeleted`
  вычисляется из `deletedAt`.
- `Message { id, chatId, senderId, type, content?, replyToId?, editedAt?,
  deletedAt?, createdAt, sender?, replyTo? }` — сообщение.

  Особенность: `id` объявлен как `var`. Это позволяет обновлять
  **оптимистичные** сообщения — клиент создаёт сообщение с временным `id`,
  показывает его сразу, а после подтверждения сервера подменяет `id` на
  настоящий.

  Вычисляемые свойства: `isDeleted`, `isEdited`, `displayContent`
  (для удалённого сообщения возвращает «Сообщение удалено»).

#### `CallLog`, `CallType`, `CallStatus` (`CallLog.swift`)

- `CallType` — `.voice = "VOICE"`, `.video = "VIDEO"`.
- `CallStatus` — `.accepted = "ACCEPTED"`, `.declined = "DECLINED"`,
  `.missed = "MISSED"`.
- `CallLog { id, initiatorId, targetId, type, status?, startedAt?, endedAt?,
  createdAt, initiator?, target? }` — запись истории звонка.

  Вычисляемые свойства: `duration: TimeInterval?` (разница между `startedAt` и
  `endedAt`) и `durationText` (формат `m:ss`, либо `—`).

### Связи с другими модулями

- **Сервисы → Модели.** `NetworkService.request` декодирует JSON в эти типы
  благодаря соответствию `Codable`. Например, `AuthService` возвращает
  `AuthResponse`, `ChatService` — `[Chat]` и `[Message]`, `ContactsService` —
  `[User]`, `CallService` — `CallLog`.
- **`SocketService` → Модели.** Real-time события (`message:new`,
  `message:edited` и т.п.) декодируются в `Message`/`Chat`.
- **ViewModels → Модели.** ViewModels держат массивы моделей как источник
  истины для экранов (`chats: [Chat]`, `messages: [Message]`, `contacts: [User]`).
- **Модели → Модели (вложенность).** `Chat` содержит `[ChatMember]`,
  `lastMessage: Message?`; `ChatMember` и `Message` содержат `User?`;
  `Message` содержит `MessageReplyPreview?`. Это позволяет бэкенду присылать
  «развёрнутые» объекты одним ответом.

### Как использовать

**Декодирование ответа сервера** (типы выводятся автоматически):

```swift
let chats: [Chat] = try await NetworkService.shared.request(endpoint: "/chats")
let me: User = try await NetworkService.shared.request(endpoint: "/users/\(id)")
```

**Отображение бизнес-логики без обращения к сети:**

```swift
if user.isOnline { /* зелёная точка */ }
let title = chat.displayName(currentUserId: session.userId)
let subtitle = user.lastSeenText
```

**Оптимистичная отправка сообщения:**

```swift
var draft = Message(id: UUID().uuidString, chatId: chatId, senderId: myId,
                    type: .text, content: text, createdAt: Date())
messages.append(draft)                 // показать сразу
let saved: Message = try await chatService.send(draft)
if let i = messages.firstIndex(where: { $0.id == draft.id }) {
    messages[i].id = saved.id          // подменить временный id на серверный
}
```

### Важные замечания

- **Даты.** Все поля `Date` декодируются кастомной стратегией из
  `NetworkService` (ISO 8601 с дробными долями секунды и без них). Отдельная
  настройка декодера для моделей не нужна.
- **Raw-значения enum должны совпадать с бэкендом.** Строки вида `"DIRECT"`,
  `"VOICE"`, `"TEXT"` — это контракт с сервером; менять их можно только
  синхронно с бэкендом.
- **Value types.** Модели передаются по значению; изменение локальной копии не
  затрагивает исходную. Для оптимистичных обновлений это ожидаемое поведение.
