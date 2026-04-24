# FamilyTalk — Семейный мессенджер

iOS-приложение для семейного общения с поддержкой текстовых сообщений, звонков и видеозвонков.

## 📁 Структура проекта

```
FamilyTalk/
├── Models/               # Модели данных
│   ├── User.swift
│   ├── AuthResponse.swift
│   └── CallLog.swift
├── Services/            # Бизнес-логика и API
│   ├── NetworkService.swift
│   ├── AuthService.swift
│   ├── KeychainService.swift
│   ├── ContactsService.swift
│   └── CallService.swift
├── ViewModels/          # MVVM ViewModels
│   ├── AuthViewModel.swift
│   ├── ContactsViewModel.swift
│   └── CallViewModel.swift
├── Views/               # SwiftUI интерфейсы
│   ├── AuthView.swift
│   ├── ContactsView.swift
│   ├── CallView.swift
│   └── Components/
│       └── AsyncImageView.swift
└── FamilyTalkApp.swift  # Точка входа
```

## 🚀 Текущая реализация (Этап 1)

### Реализованные экраны:

1. **AuthView** — упрощённая авторизация по номеру телефона и имени (без SMS)
2. **ContactsView** — список контактов с поиском и online-статусом
3. **CallView** — экран голосового/видео звонка

### API-эндпоинты (согласно ТЗ):

#### Авторизация
- `POST /auth/simplified-login` — упрощённая авторизация (без OTP)
  - Body: `{ phone: string, displayName: string }`
  - Response: `{ access_token, refresh_token, user }`

#### Контакты
- `GET /users` — получить список всех контактов
- `GET /users/search?q=query` — поиск по никнейму
- `GET /users/:id` — информация о пользователе

#### Звонки
- `POST /calls/initiate` — инициировать звонок
  - Body: `{ targetUserId: string, type: "VOICE" | "VIDEO" }`
  - Response: `{ callId: string, sdp: string }`
- `POST /calls/:id/end` — завершить звонок
- `GET /calls/history` — история звонков

## 🔧 Настройка

### 1. Измените URL сервера

В файле `Services/NetworkService.swift` замените:
```swift
private let baseURL = "https://api.example.com"
```
на ваш реальный адрес бэкенда.

### 2. Запустите проект

```bash
# Откройте проект в Xcode
open FamilyTalk.xcodeproj

# Выберите симулятор или устройство
# Нажмите Cmd+R для запуска
```

## 📱 Использование

1. **Авторизация**:
   - Введите номер телефона (формат: +7XXXXXXXXXX)
   - Введите ваше имя
   - Нажмите "Войти"

2. **Контакты**:
   - Просмотр списка контактов
   - Поиск по имени или никнейму
   - Индикация online-статуса
   - Tap по контакту → выбор типа звонка

3. **Звонок**:
   - Автоматическая инициализация звонка
   - Отображение статуса соединения
   - Таймер длительности звонка
   - Кнопка завершения звонка

## 🔐 Безопасность

- **Токены** хранятся в iOS Keychain
- **JWT** автоматически добавляется к запросам
- **Автообновление** access_token через refresh_token (TODO)

## 📋 TODO (следующие этапы)

- [ ] Реальная интеграция WebRTC для звонков
- [ ] Socket.io для real-time событий
- [ ] Экран чатов и сообщений
- [ ] Отправка изображений и голосовых сообщений
- [ ] Push-уведомления (APNs)
- [ ] CallKit для системных звонков
- [ ] История звонков
- [ ] Групповые чаты
- [ ] Настройки профиля

## 🛠 Технологии

- **Swift 5.9+**
- **SwiftUI** — UI фреймворк
- **Combine** — реактивное программирование
- **MVVM** — архитектурный паттерн
- **URLSession** — HTTP-клиент
- **Keychain** — безопасное хранилище

## 📄 Лицензия

Приватный семейный проект
