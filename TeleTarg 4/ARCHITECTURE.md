# TeleTarg — Архитектура нативного iOS-клиента Telegram (Swift 6, iOS 17+)

## 1. Общая архитектура (Clean Modular Architecture + Reactive Local Overlay)

TeleTarg построен по слоистой архитектуре с жёстким разделением транспорта (TDLib), локального хранилища оверрайдов/анти-удаления (GRDB SQLite) и переключаемого UI-слоя (`AppLayoutMode`: Classic ↔ Discord):

```
┌────────────────────────────────────────────────────────────────────────────┐
│                            Presentation Layer                              │
│  AppRootContainer (instant AppLayoutMode switch: ClassicTabRoot /          │
│                     DiscordShellRoot — 0 restarts, shared ViewModels)      │
│  SwiftUI Chrome + UIKit 120Hz ChatCollectionView (ProMotion, cell reuse)   │
└──────────────────────────┬───────────────────────────────┬─────────────────┘
                           │ Observe reactive streams      │ User intents
┌──────────────────────────▼───────────────────────────────▼─────────────────┐
│                          Domain / Coordination Layer                       │
│  • ProfileMergeEngine (RemoteUserProfile + ProfileOverrideRecord ->        │
│    EffectiveUserProfile)                                                   │
│  • StealthInterceptor (wraps MessengerTransport, filters outgoing events)  │
│  • AntiDeleteStore / Coordinator (intercepts incoming delete/edit/TTL)     │
│  • HiddenChatsVault (Face ID / Touch ID + Real PIN / Decoy PIN)            │
└──────────────────────────┬───────────────────────────────┬─────────────────┘
                           │                               │
┌──────────────────────────▼──────────────┐  ┌─────────────▼─────────────────┐
│        Transport Layer (Protocol)       │  │   Local Persistence (GRDB)    │
│  MessengerTransport (Sendable protocol) │  │  AppDatabase (WAL, FTS5,      │
│   ├── TDLibTransport (Telegram API)     │  │  NSFileProtectionComplete)    │
│   └── CustomWebSocketTransport (opt.)   │  │  • ProfileOverrideRepository  │
│                                         │  │  • AntiDeleteRepository       │
│  KeychainStore (API keys, PIN hashes)   │  │  • StealthSettingsRepository  │
│  LocalMediaVault (protected cache dir)  │  │  • AppSettingsRepository      │
└─────────────────────────────────────────┘  │  • EncryptedBackupRepository  │
                                             └───────────────────────────────┘
```

---

## 2. Дерево файлов проекта

```text
TeleTarg/
├── Package.swift
├── project.yml                              # XcodeGen spec для сборки iOS .ipa
├── .github/workflows/build-ios-ipa.yml      # CI/CD сборка unsigned .ipa (iOS 17+)
├── ARCHITECTURE.md
└── Sources/
    └── TeleTarg/
        ├── App/
        │   ├── TeleTargApp.swift            # Точка входа, DI-контейнер, сцена
        │   ├── AppEnvironment.swift         # Единый контейнер зависимостей
        │   └── AppRootView.swift            # Реактивный свитчер Classic <-> Discord
        ├── Core/
        │   ├── Models/
        │   │   ├── UserProfileModels.swift          # Модуль 1
        │   │   ├── ChatAndMessageModels.swift       # Модуль 1
        │   │   └── StealthAndSettingsModels.swift   # Модуль 1
        │   ├── Database/
        │   │   └── AppDatabase.swift                # Модуль 1 (GRDB + миграции)
        │   ├── Repositories/
        │   │   ├── ProfileOverrideRepository.swift  # Модуль 1
        │   │   ├── AntiDeleteRepository.swift       # Модуль 1
        │   │   ├── StealthSettingsRepository.swift  # Модуль 1
        │   │   ├── AppSettingsRepository.swift      # Модуль 1
        │   │   └── EncryptedBackupRepository.swift  # Модуль 1
        │   └── Security/
        │       ├── KeychainService.swift            # Модуль 2 (PIN, Decoy PIN, API keys)
        │       └── BiometricVaultService.swift      # Модуль 2 (Face ID / Touch ID)
        ├── Transport/
        │   ├── MessengerTransport.swift             # Модуль 2 (абстрактный протокол)
        │   ├── TDLibTransport.swift                 # Модуль 2 (реализация на TDLibKit)
        │   ├── StealthInterceptor.swift             # Модуль 2 (перехват исходящих)
        │   └── AntiDeleteCoordinator.swift          # Модуль 2 (перехват входящих)
        ├── Features/
        │   ├── Auth/
        │   │   └── TelegramAuthFlowView.swift       # Модуль 3 (телефон, код, 2FA, QR)
        │   ├── ChatList/
        │   │   ├── ChatListViewModel.swift          # Модуль 3 (общий для Classic & Discord)
        │   │   ├── ClassicChatListView.swift        # Модуль 3
        │   │   └── HiddenChatsGateView.swift        # Модуль 3 (Face ID / Real & Decoy PIN)
        │   ├── ChatRoom/
        │   │   ├── ChatRoomViewModel.swift          # Модуль 4
        │   │   ├── ProMotionChatTableView.swift     # Модуль 4 (UIKit 120Hz коллекция)
        │   │   ├── ClassicMessageCell.swift         # Модуль 4 (баблы, частичное выделение)
        │   │   ├── DiscordMessageCell.swift         # Модуль 4 (плотный Discord-стиль)
        │   │   ├── EditHistorySheetView.swift       # Модуль 4 (история правок)
        │   │   ├── ViewOnceMediaViewer.swift        # Модуль 4 (сохранение/копирование TTL)
        │   │   └── RawMetadataInspectorView.swift   # Модуль 4 (User/Chat ID, raw JSON)
        │   ├── ProfileEditor/
        │   │   ├── LocalProfileEditorViewModel.swift # Модуль 5
        │   │   └── LocalProfileEditorView.swift     # Модуль 5 (лайв-превью + сброс полей)
        │   ├── DiscordShell/
        │   │   ├── DiscordShellView.swift           # Модуль 5 (rail-бар, свайп-дроер)
        │   │   ├── DiscordServerRailView.swift      # Модуль 5 (папки/группы -> серверы)
        │   │   ├── DiscordChannelDrawerView.swift   # Модуль 5 (#каналы, ветки, ЛС)
        │   │   └── DiscordUserStatusBar.swift       # Модуль 5 (низ + оверлей звонка)
        │   └── Settings/
        │       ├── SettingsRootView.swift           # Модуль 6
        │       ├── StealthSettingsView.swift        # Модуль 6 (тумблеры + исключения)
        │       ├── AppearanceSettingsView.swift     # Модуль 6 (Classic/Discord, шрифты)
        │       └── BackupSettingsView.swift         # Модуль 6 (экспорт/импорт шифр. бэкапа)
        └── DesignSystem/
            ├── ThemeTokens.swift                    # Модуль 5 (iOS Classic + Discord Onyx/Ash/Blurple)
            └── CustomFontModifier.swift             # Модуль 5
```

---

## 3. Схема таблиц локальной БД (GRDB / SQLite WAL)

| Таблица | Первичный ключ / Индексы | Назначение |
|---|---|---|
| `profile_overrides` | PK `user_id` (`INTEGER`) | Локальные оверрайды профиля (имя, фамилия, `@username`, локальный путь фото/видео-аватара, био, статус, цвета имени/шапки, JSON-массив бейджей, эмодзи-статус, личная заметка). `NULL` в колонке = используется оригинал с сервера. |
| `cached_messages` | PK `(chat_id, message_id)`; IDX `(chat_id, sent_at DESC)`, IDX `(chat_id, is_deleted_locally)` | Полный локальный слепок сообщений для Anti-Delete, офлайн-просмотра, обхода запрета пересылки и просмотра raw-метаданных (`raw_json`, `is_deleted_locally`, `deleted_at`, `edit_count`, `is_view_once`). |
| `message_edit_revisions` | PK `id` (`AUTOINCREMENT`), FK `(chat_id, message_id)` → `cached_messages` (`ON DELETE CASCADE`); IDX `(chat_id, message_id, revision_index)` | Полная история версий текста сообщения до каждого `updateMessageContent` с точными таймстампами. |
| `view_once_media_cache` | PK `(chat_id, message_id)`; IDX `cached_at DESC` | Метаданные и локальные пути перехваченных одноразовых (TTL) фото, видео и голосовых, скопированных в защищённую папку до самоуничтожения. |
| `stealth_settings` | PK `id` (`INTEGER = 1`, singleton) | Глобальные флаги `StealthInterceptor`: `isMasterGhostEnabled`, `blockReadReceipts`, `blockTypingAndActivities`, `hideOnlinePresence`, `autoOfflineAfterSend`, `incognitoStories`, `bypassForwardRestrictions`. |
| `stealth_chat_rules` | PK `chat_id` (`INTEGER`) | Исключения режима «Призрак» по конкретным чатам: `forceGhostOn` (чёрный список — призрак всегда включён) или `forceGhostOff` (белый список — обычная работа даже при активном призраке). |
| `app_settings` | PK `id` (`INTEGER = 1`, singleton) | Глобальные настройки UI: `layout_mode` (`classic` / `discord`), `discord_palette`, кастомные цвета, `font_family`, `font_size_scale`, `show_user_and_chat_ids`, `translation_target_language`, `security_biometrics_enabled`, `decoy_pin_enabled`. |
| `hidden_chats` | PK `chat_id` (`INTEGER`); IDX `is_decoy_visible` | Список скрытых чатов, доступных только после прохождения Face ID / основного PIN-кода. При вводе ложного PIN-кода показывается пустой список (или только помеченные `is_decoy_visible = 1`). |
| `discord_server_mappings` | PK `folder_or_chat_id` (`TEXT`); IDX `sort_order` | Персональный порядок и кастомные иконки «серверов» в левом rail-баре Discord Mode (маппинг папок Telegram и закреплённых групп/каналов). |

---

## 4. Потоки данных ключевых подсистем

### 4.1 `StealthInterceptor` (перехват исходящих событий)
```
UI / ViewModel -> StealthInterceptor (реализует MessengerTransport)
                       │
                       ├── 1. Читает EffectiveStealthPolicy(chatId) из StealthSettingsRepository
                       │      (учитывает глобальный тумблер + per-chat whitelist/blacklist)
                       │
                       ├── 2. viewMessages / readHistory:
                       │      • forceManual == false && policy.blockReadReceipts -> DROP (не шлём в TDLib)
                       │      • forceManual == true (кнопка «Отметить прочитанным») -> FORWARD в TDLib
                       │
                       ├── 3. sendChatAction (typing, recordingVoice, uploadingPhoto...):
                       │      • policy.blockTypingAndActivities -> DROP
                       │
                       ├── 4. setOnlineStatus(true):
                       │      • policy.hideOnlinePresence -> DROP
                       │      • после sendMessage при policy.autoOfflineAfterSend -> немедленный setOnlineStatus(false)
                       │
                       └── 5. openStory / viewStory:
                              • policy.incognitoStories -> загружаем медиа через file API без openStory/markStoryViewed
```

### 4.2 `AntiDeleteStore` / `AntiDeleteRepository` (перехват входящих событий)
```
TDLib Update Stream -> AntiDeleteCoordinator
                         ├── updateNewMessage -> AntiDeleteRepository.upsertMessage()
                         │     └── если selfDestructType != nil -> немедленное скачивание и копирование
                         │         файла в ApplicationSupport/ViewOnceVault/ + запись в view_once_media_cache
                         │
                         ├── updateMessageContent -> AntiDeleteRepository.recordEditRevision()
                         │     └── в одной SQLite-транзакции:
                         │         1) сохраняет старый text/raw_json в message_edit_revisions
                         │         2) обновляет cached_messages.text, edited_at, edit_count += 1
                         │
                         └── updateDeleteMessages -> AntiDeleteRepository.markMessagesDeletedLocally()
                               └── НЕ удаляет строки: выставляет is_deleted_locally = 1, deleted_at = Date()
                                   UI через ValueObservation мгновенно рисует плашку «Удалено в HH:mm»
```

### 4.3 `ProfileOverrideRepository` (локальный редактор профиля)
```
RemoteUserProfile (из TDLib)  ──┐
                                ├──> ProfileOverrideRepository.observeEffectiveProfile(userId, remote)
ProfileOverrideRecord (GRDB)  ──┘            │
                                             ▼
                                   EffectiveUserProfile (immutable Sendable)
                                   (каждое non-nil поле из override заменяет оригинал;
                                    сброс поля пишет NULL в конкретную колонку GRDB)
                                             │
                 ┌───────────────────────────┼───────────────────────────┐
                 ▼                           ▼                           ▼
         Список чатов / Rail           Шапка и лента чата         Экран профиля и редактор
```

### 4.4 `AppLayoutMode` (мгновенное переключение Classic ↔ Discord)
```
Settings / Quick Switcher -> AppSettingsRepository.setLayoutMode(.discord | .classic)
                                      │
                                      ▼ (GRDB ValueObservation -> @Observable AppRouterState)
                                 AppRootView
                                  ├── .classic -> ClassicTabShell (TabView + NavigationStack)
                                  └── .discord -> DiscordAdaptiveShell (ServerRail + ChannelDrawer + ChatRoom)
                                      │
                  Оба режима используют ОДНИ И ТЕ ЖЕ экземпляры:
                  ChatListViewModel, ChatRoomViewModel, StealthInterceptor, AppDatabase
                  -> переключение мгновенное (< 16ms), без перезапуска и потери позиции скролла.
```
