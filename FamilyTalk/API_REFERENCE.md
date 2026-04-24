# Руководство по API — FamilyTalk Backend

## Базовый URL
```
https://api.example.com
```

Все запросы используют `Content-Type: application/json`.

---

## 🔐 Авторизация

### Упрощённая авторизация (без OTP)

**Для разработки**: авторизация только по номеру телефона и имени.

```http
POST /auth/simplified-login
Content-Type: application/json

{
  "phone": "+79991234567",
  "displayName": "Иван Иванов"
}
```

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "uuid-here",
    "phone": "+79991234567",
    "username": null,
    "displayName": "Иван Иванов",
    "avatarUrl": null,
    "bio": null,
    "lastSeen": "2026-04-23T12:00:00Z",
    "createdAt": "2026-04-23T10:00:00Z"
  }
}
```

### Обновление токена

```http
POST /auth/refresh
Content-Type: application/json

{
  "refresh_token": "your-refresh-token"
}
```

**Response 200:**
```json
{
  "access_token": "new-access-token",
  "refresh_token": "new-refresh-token"
}
```

---

## 👥 Контакты

Все запросы требуют авторизации: `Authorization: Bearer <access_token>`

### Получить список всех контактов

```http
GET /users
Authorization: Bearer <access_token>
```

**Response 200:**
```json
[
  {
    "id": "uuid-1",
    "phone": "+79991234567",
    "username": "ivan_ivanov",
    "displayName": "Иван Иванов",
    "avatarUrl": "https://s3.example.com/avatars/uuid-1.jpg",
    "bio": "Семейный админ",
    "lastSeen": "2026-04-23T12:00:00Z",
    "createdAt": "2026-04-20T10:00:00Z"
  },
  {
    "id": "uuid-2",
    "phone": "+79991234568",
    "username": null,
    "displayName": "Мария Петрова",
    "avatarUrl": null,
    "bio": null,
    "lastSeen": "2026-04-23T11:50:00Z",
    "createdAt": "2026-04-21T14:30:00Z"
  }
]
```

### Поиск контактов по никнейму

```http
GET /users/search?q=ivan
Authorization: Bearer <access_token>
```

**Response 200:**
```json
[
  {
    "id": "uuid-1",
    "phone": "+79991234567",
    "username": "ivan_ivanov",
    "displayName": "Иван Иванов",
    "avatarUrl": "https://s3.example.com/avatars/uuid-1.jpg",
    "bio": "Семейный админ",
    "lastSeen": "2026-04-23T12:00:00Z",
    "createdAt": "2026-04-20T10:00:00Z"
  }
]
```

### Получить информацию о пользователе

```http
GET /users/:id
Authorization: Bearer <access_token>
```

**Response 200:**
```json
{
  "id": "uuid-1",
  "phone": "+79991234567",
  "username": "ivan_ivanov",
  "displayName": "Иван Иванов",
  "avatarUrl": "https://s3.example.com/avatars/uuid-1.jpg",
  "bio": "Семейный админ",
  "lastSeen": "2026-04-23T12:00:00Z",
  "createdAt": "2026-04-20T10:00:00Z"
}
```

---

## 📞 Звонки

### Инициировать звонок

```http
POST /calls/initiate
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "targetUserId": "uuid-2",
  "type": "VOICE"  // или "VIDEO"
}
```

**Response 200:**
```json
{
  "callId": "call-uuid",
  "sdp": "v=0\r\no=- 1234567890 1234567890 IN IP4 0.0.0.0\r\n..."
}
```

**Примечание:** SDP (Session Description Protocol) используется для WebRTC сигналинга.

### Завершить звонок

```http
POST /calls/:callId/end
Authorization: Bearer <access_token>
```

**Response 200:**
```json
{}
```

### История звонков

```http
GET /calls/history
Authorization: Bearer <access_token>
```

**Response 200:**
```json
[
  {
    "id": "call-uuid-1",
    "initiatorId": "uuid-1",
    "targetId": "uuid-2",
    "type": "VOICE",
    "status": "ACCEPTED",
    "startedAt": "2026-04-23T12:00:00Z",
    "endedAt": "2026-04-23T12:05:30Z",
    "createdAt": "2026-04-23T11:59:50Z"
  },
  {
    "id": "call-uuid-2",
    "initiatorId": "uuid-2",
    "targetId": "uuid-1",
    "type": "VIDEO",
    "status": "MISSED",
    "startedAt": null,
    "endedAt": null,
    "createdAt": "2026-04-23T10:30:00Z"
  }
]
```

**Статусы звонков:**
- `ACCEPTED` — принят
- `DECLINED` — отклонён
- `MISSED` — пропущен

---

## 🔧 Коды ошибок

| Код | Описание |
|-----|----------|
| 400 | Неверный запрос (проверьте параметры) |
| 401 | Не авторизован (неверный или истёкший токен) |
| 403 | Доступ запрещён |
| 404 | Ресурс не найден |
| 429 | Слишком много запросов (rate limit) |
| 500 | Внутренняя ошибка сервера |

**Пример ошибки:**
```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired token",
  "statusCode": 401
}
```

---

## 📝 Примечания

1. **Все даты** в формате ISO 8601: `2026-04-23T12:00:00Z`
2. **Токены** имеют ограниченный срок действия:
   - `access_token`: 15 минут
   - `refresh_token`: 30 дней
3. **Rate limiting**:
   - Максимум 100 запросов в минуту на один IP
   - Для SMS: максимум 3 запроса в час на номер
4. **WebRTC сигналинг** реализован через Socket.io (см. ТЗ, раздел 6.4)

---

## 🚀 Следующие этапы

После реализации базовой функциональности будут добавлены:
- Чаты и сообщения (REST + Socket.io)
- Загрузка медиафайлов (S3)
- Push-уведомления (APNs)
- Полная реализация WebRTC для звонков
