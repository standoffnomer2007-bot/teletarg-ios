import SwiftUI
import UniformTypeIdentifiers

public struct TeleTargBackupDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.data] }
    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public struct SettingsRootView: View {
    @Binding var appSettings: AppSettingsRecord
    @Binding var stealthSettings: StealthSettingsRecord
    let appSettingsRepo: any AppSettingsRepositoryProtocol
    let stealthRepo: any StealthSettingsRepositoryProtocol
    let backupRepo: any EncryptedBackupRepositoryProtocol
    let onLogOut: () -> Void

    @State private var chatRules: [StealthChatRuleRecord] = []
    @State private var backupPassphrase: String = ""
    @State private var exportDocument: TeleTargBackupDocument? = nil
    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false
    @State private var backupStatus: String? = nil

    public init(
        appSettings: Binding<AppSettingsRecord>,
        stealthSettings: Binding<StealthSettingsRecord>,
        appSettingsRepo: any AppSettingsRepositoryProtocol,
        stealthRepo: any StealthSettingsRepositoryProtocol,
        backupRepo: any EncryptedBackupRepositoryProtocol,
        onLogOut: @escaping () -> Void
    ) {
        self._appSettings = appSettings
        self._stealthSettings = stealthSettings
        self.appSettingsRepo = appSettingsRepo
        self.stealthRepo = stealthRepo
        self.backupRepo = backupRepo
        self.onLogOut = onLogOut
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Переключатель интерфейса (без перезапуска)") {
                    Picker("Режим UI", selection: Binding(
                        get: { appSettings.layoutMode },
                        set: { newMode in
                            appSettings.layoutMode = newMode
                            Task { try? await appSettingsRepo.setLayoutMode(newMode) }
                        }
                    )) {
                        ForEach(AppLayoutMode.allCases, id: \.self) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if appSettings.layoutMode == .discord {
                        Picker("Палитра Discord", selection: Binding(
                            get: { appSettings.discordPalette },
                            set: { pal in
                                appSettings.discordPalette = pal
                                Task { _ = try? await appSettingsRepo.updateSettings { $0.discordPalette = pal } }
                            }
                        )) {
                            Text("Onyx").tag(DiscordThemePalette.onyx)
                            Text("Ash").tag(DiscordThemePalette.ash)
                            Text("Blurple").tag(DiscordThemePalette.blurple)
                            Text("Custom").tag(DiscordThemePalette.custom)
                        }
                    }
                }

                Section("Режим «Призрак» и «Нечитайка»") {
                    stealthToggle("Мастер-переключатель Призрака", keyPath: \.isMasterGhostEnabled)
                    stealthToggle("Нечитайка (блокировка viewMessages)", keyPath: \.blockReadReceipts)
                    stealthToggle("Скрыть «печатает...» и активность", keyPath: \.blockTypingAndActivities)
                    stealthToggle("Скрытый онлайн", keyPath: \.hideOnlinePresence)
                    stealthToggle("Авто-офлайн после отправки", keyPath: \.autoOfflineAfterSend)
                    stealthToggle("Инкогнито для сторис", keyPath: \.incognitoStories)
                    stealthToggle("Обход запрета пересылки и копирования", keyPath: \.bypassForwardRestrictions)
                }

                if !chatRules.isEmpty {
                    Section("Исключения Призрака по чатам (\(chatRules.count))") {
                        ForEach(chatRules) { rule in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(rule.note ?? "Чат \(rule.chatId)").font(.subheadline.weight(.medium))
                                    Text(rule.mode == .forceGhostOn ? "Чёрный список (Призрак всегда ВКЛ)" : "Белый список (Призрак всегда ВЫКЛ)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        try? await stealthRepo.removeChatRule(for: rule.chatId)
                                        chatRules.removeAll { $0.chatId == rule.chatId }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Типографика и Power-User") {
                    Picker("Шрифт", selection: Binding(
                        get: { appSettings.fontFamily },
                        set: { fam in
                            appSettings.fontFamily = fam
                            Task { _ = try? await appSettingsRepo.updateSettings { $0.fontFamily = fam } }
                        }
                    )) {
                        Text("SF Pro").tag(AppFontFamily.systemSF)
                        Text("SF Rounded").tag(AppFontFamily.roundedSF)
                        Text("SF Mono").tag(AppFontFamily.monoSF)
                        Text("New York Serif").tag(AppFontFamily.serifNewYork)
                    }

                    VStack(alignment: .leading) {
                        Text("Масштаб шрифта: \(Int(appSettings.fontSizeScale * 100))%")
                            .font(.subheadline)
                        Slider(value: Binding(
                            get: { appSettings.fontSizeScale },
                            set: { scale in
                                appSettings.fontSizeScale = scale
                                Task { _ = try? await appSettingsRepo.updateSettings { $0.fontSizeScale = scale } }
                            }
                        ), in: 0.85...1.35, step: 0.05)
                    }

                    Toggle("Показывать User ID и Chat ID", isOn: Binding(
                        get: { appSettings.showUserAndChatIDs },
                        set: { val in
                            appSettings.showUserAndChatIDs = val
                            Task { _ = try? await appSettingsRepo.updateSettings { $0.showUserAndChatIDs = val } }
                        }
                    ))
                }

                Section("Зашифрованный бэкап (AES-256-GCM)") {
                    SecureField("Пароль для шифрования / расшифровки", text: $backupPassphrase)

                    Button("Экспортировать бэкап (.teletargbackup)") {
                        Task {
                            do {
                                let data = try await backupRepo.exportEncryptedBackup(passphrase: backupPassphrase)
                                exportDocument = TeleTargBackupDocument(data: data)
                                isExporting = true
                                backupStatus = nil
                            } catch {
                                backupStatus = error.localizedDescription
                            }
                        }
                    }
                    .disabled(backupPassphrase.isEmpty)

                    Button("Импортировать бэкап") {
                        isImporting = true
                    }
                    .disabled(backupPassphrase.isEmpty)

                    if let backupStatus {
                        Text(backupStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Выйти из аккаунта Telegram", role: .destructive, action: onLogOut)
                }
            }
            .navigationTitle("Настройки TeleTarg")
            .task {
                chatRules = (try? await stealthRepo.fetchAllChatRules()) ?? []
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .data,
                defaultFilename: "TeleTarg_Backup.teletargbackup"
            ) { result in
                if case .success = result {
                    backupStatus = "Зашифрованный бэкап успешно сохранён."
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result {
                    Task {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        do {
                            let data = try Data(contentsOf: url)
                            try await backupRepo.importEncryptedBackup(data, passphrase: backupPassphrase, replaceExisting: true)
                            backupStatus = "Бэкап успешно восстановлен."
                        } catch {
                            backupStatus = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func stealthToggle(
        _ title: String,
        keyPath: WritableKeyPath<StealthSettingsRecord, Bool> & Sendable
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { stealthSettings[keyPath: keyPath] },
            set: { newValue in
                stealthSettings[keyPath: keyPath] = newValue
                Task {
                    _ = try? await stealthRepo.updateGlobalSettings { $0[keyPath: keyPath] = newValue }
                }
            }
        ))
    }
}
