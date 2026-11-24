import SwiftUI

@MainActor
public final class AppEnvironment {
    public let database: AppDatabase
    public let keychain: KeychainService
    public let biometricVault: BiometricVaultService
    public let profileRepository: ProfileOverrideRepository
    public let antiDeleteRepository: AntiDeleteRepository
    public let stealthRepository: StealthSettingsRepository
    public let appSettingsRepository: AppSettingsRepository
    public let backupRepository: EncryptedBackupRepository
    public let rawTransport: TDLibTransport
    public let transport: StealthInterceptor
    public let antiDeleteCoordinator: AntiDeleteCoordinator
    public let chatListViewModel: ChatListViewModel

    public init() throws {
        let db = try AppDatabase.makePersistent()
        let keychain = KeychainService()
        let vault = BiometricVaultService(keychain: keychain)
        let profileRepo = ProfileOverrideRepository(database: db)
        let antiDeleteRepo = AntiDeleteRepository(database: db)
        let stealthRepo = StealthSettingsRepository(database: db)
        let appSettingsRepo = AppSettingsRepository(database: db)
        let backupRepo = EncryptedBackupRepository(database: db)

        let tdlib = TDLibTransport()
        let stealthTransport = StealthInterceptor(underlying: tdlib, stealthRepository: stealthRepo)
        let coordinator = AntiDeleteCoordinator(transport: stealthTransport, antiDeleteRepository: antiDeleteRepo)
        let listVM = ChatListViewModel(
            transport: stealthTransport,
            profileRepository: profileRepo,
            stealthRepository: stealthRepo,
            appSettingsRepository: appSettingsRepo
        )

        self.database = db
        self.keychain = keychain
        self.biometricVault = vault
        self.profileRepository = profileRepo
        self.antiDeleteRepository = antiDeleteRepo
        self.stealthRepository = stealthRepo
        self.appSettingsRepository = appSettingsRepo
        self.backupRepository = backupRepo
        self.rawTransport = tdlib
        self.transport = stealthTransport
        self.antiDeleteCoordinator = coordinator
        self.chatListViewModel = listVM
    }
}

public struct ProfileEditorSheetContext: Identifiable {
    public let id: Int64
    public let remote: RemoteUserProfile
    public let existingOverride: ProfileOverrideRecord?
}

public struct AppRootView: View {
    let env: AppEnvironment

    @State private var authStage: AuthStage = .idle
    @State private var currentUserId: Int64 = 0
    @State private var appSettings: AppSettingsRecord = .default
    @State private var stealthSettings: StealthSettingsRecord = .default
    @State private var selectedChatForClassic: ChatDialogSummary? = nil
    @State private var isSettingsSheetPresented: Bool = false
    @State private var profileEditorContext: ProfileEditorSheetContext? = nil

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        Group {
            if case .ready = authStage {
                mainShell
            } else {
                TelegramAuthFlowView(
                    authStage: $authStage,
                    transport: env.transport,
                    keychain: env.keychain
                )
            }
        }
        .task {
            await bootstrap()
        }
        .sheet(isPresented: $env.chatListViewModel.isHiddenVaultOpen) {
            HiddenChatsGateView(
                viewModel: env.chatListViewModel,
                vaultService: env.biometricVault,
                keychain: env.keychain
            ) { chat in
                selectedChatForClassic = chat
                env.chatListViewModel.selectedChatId = chat.chatId
            }
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            SettingsRootView(
                appSettings: $appSettings,
                stealthSettings: $stealthSettings,
                appSettingsRepo: env.appSettingsRepository,
                stealthRepo: env.stealthRepository,
                backupRepo: env.backupRepository,
                onLogOut: {
                    Task { try? await env.transport.logOut() }
                }
            )
        }
        .sheet(item: $profileEditorContext) { ctx in
            LocalProfileEditorView(
                remoteProfile: ctx.remote,
                existingOverride: ctx.existingOverride,
                repository: env.profileRepository
            )
        }
    }

    @ViewBuilder
    private var mainShell: some View {
        switch appSettings.layoutMode {
        case .classic:
            TabView {
                NavigationStack {
                    ClassicChatListView(
                        viewModel: env.chatListViewModel,
                        showIds: appSettings.showUserAndChatIDs,
                        onSelectChat: { chat in
                            selectedChatForClassic = chat
                            env.chatListViewModel.selectedChatId = chat.chatId
                        },
                        onOpenProfileEditor: { _, remote in
                            openProfileEditor(for: remote.userId, fallbackRemote: remote)
                        },
                        onOpenHiddenVault: {
                            env.chatListViewModel.isHiddenVaultOpen = true
                        },
                        onSwitchToDiscord: {
                            Task { try? await env.appSettingsRepository.setLayoutMode(.discord) }
                        }
                    )
                    .navigationDestination(item: $selectedChatForClassic) { chat in
                        makeChatRoomView(chat: chat)
                    }
                }
                .tabItem {
                    Label("Чаты", systemImage: "message.fill")
                }

                SettingsRootView(
                    appSettings: $appSettings,
                    stealthSettings: $stealthSettings,
                    appSettingsRepo: env.appSettingsRepository,
                    stealthRepo: env.stealthRepository,
                    backupRepo: env.backupRepository,
                    onLogOut: {
                        Task { try? await env.transport.logOut() }
                    }
                )
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
            }

        case .discord:
            DiscordShellView(
                chatListVM: env.chatListViewModel,
                settings: appSettings,
                currentUserProfile: resolveAuthor(userId: currentUserId),
                makeChatRoom: { chat in
                    makeChatRoomView(chat: chat)
                },
                onOpenSettings: {
                    isSettingsSheetPresented = true
                },
                onOpenHiddenVault: {
                    env.chatListViewModel.isHiddenVaultOpen = true
                },
                onSwitchToClassic: {
                    Task { try? await env.appSettingsRepository.setLayoutMode(.classic) }
                }
            )
        }
    }

    private func makeChatRoomView(chat: ChatDialogSummary) -> ChatRoomView {
        let vm = ChatRoomViewModel(
            chat: chat,
            transport: env.transport,
            antiDeleteRepository: env.antiDeleteRepository,
            stealthRepository: env.stealthRepository
        )
        return ChatRoomView(
            viewModel: vm,
            settings: appSettings,
            resolveAuthor: { userId in
                resolveAuthor(userId: userId)
            },
            onOpenProfileEditor: { userId in
                openProfileEditor(for: userId, fallbackRemote: nil)
            }
        )
    }

    private func resolveAuthor(userId: Int64) -> EffectiveUserProfile {
        let remote = env.chatListViewModel.remoteProfiles[userId] ?? RemoteUserProfile(
            userId: userId,
            firstName: userId == 0 ? "Вы" : "User \(userId)"
        )
        return EffectiveUserProfile.merge(
            remote: remote,
            override: env.chatListViewModel.profileOverrides[userId]
        )
    }

    private func openProfileEditor(for userId: Int64, fallbackRemote: RemoteUserProfile?) {
        Task {
            let remote = fallbackRemote
                ?? env.chatListViewModel.remoteProfiles[userId]
                ?? (try? await env.transport.fetchUserProfile(userId: userId))
                ?? RemoteUserProfile(userId: userId, firstName: "User \(userId)")
            let existing = try? await env.profileRepository.fetchOverride(for: userId)
            profileEditorContext = ProfileEditorSheetContext(
                id: userId,
                remote: remote,
                existingOverride: existing
            )
        }
    }

    private func bootstrap() async {
        Task {
            do {
                for try await settings in env.appSettingsRepository.observeSettings() {
                    self.appSettings = settings
                }
            } catch {}
        }

        Task {
            do {
                for try await stealth in env.stealthRepository.observeGlobalSettings() {
                    self.stealthSettings = stealth
                }
            } catch {}
        }

        await env.antiDeleteCoordinator.startObserving { event in
            await MainActor.run {
                if case .authStageChanged(let stage) = event {
                    self.authStage = stage
                    if case .ready(let uid) = stage {
                        self.currentUserId = uid
                        env.chatListViewModel.start()
                    }
                } else {
                    env.chatListViewModel.handleTransportEvent(event)
                }
            }
        }

        if let savedIdStr = try? env.keychain.getString(for: .telegramApiId),
           let apiId = Int32(savedIdStr),
           let apiHash = try? env.keychain.getString(for: .telegramApiHash),
           !apiHash.isEmpty {
            try? await env.transport.start(apiId: apiId, apiHash: apiHash)
        }
    }
}

@main
public struct TeleTargApp: App {
    private let environment: AppEnvironment?
    private let initError: String?

    public init() {
        do {
            self.environment = try AppEnvironment()
            self.initError = nil
        } catch {
            self.environment = nil
            self.initError = error.localizedDescription
        }
    }

    public var body: some Scene {
        WindowGroup {
            if let environment {
                AppRootView(env: environment)
            } else {
                ContentUnavailableView(
                    "Ошибка запуска локальной БД",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(initError ?? "Неизвестная ошибка инициализации GRDB.")
                )
            }
        }
    }
}
