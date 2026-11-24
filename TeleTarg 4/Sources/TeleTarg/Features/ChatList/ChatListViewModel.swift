import Foundation
import Observation

@MainActor
@Observable
public final class ChatListViewModel {
    public var chats: [ChatDialogSummary] = []
    public var folders: [ChatFolderSummary] = []
    public var remoteProfiles: [Int64: RemoteUserProfile] = [:]
    public var profileOverrides: [Int64: ProfileOverrideRecord] = [:]
    public var hiddenChatIds: Set<Int64> = []
    public var stealthSettings: StealthSettingsRecord = .default
    public var selectedFolderId: Int32? = nil
    public var searchText: String = ""
    public var selectedChatId: Int64? = nil
    public var isHiddenVaultOpen: Bool = false
    public var vaultAccessState: VaultAccessState = .locked
    public var activeCall: ActiveCallInfo? = nil

    private let transport: any MessengerTransport
    private let profileRepository: any ProfileOverrideRepositoryProtocol
    private let stealthRepository: any StealthSettingsRepositoryProtocol
    private let appSettingsRepository: any AppSettingsRepositoryProtocol
    private var observationTasks: [Task<Void, Never>] = []

    public init(
        transport: any MessengerTransport,
        profileRepository: any ProfileOverrideRepositoryProtocol,
        stealthRepository: any StealthSettingsRepositoryProtocol,
        appSettingsRepository: any AppSettingsRepositoryProtocol
    ) {
        self.transport = transport
        self.profileRepository = profileRepository
        self.stealthRepository = stealthRepository
        self.appSettingsRepository = appSettingsRepository
    }

    public func start() {
        stop()

        observationTasks.append(Task {
            do {
                for try await overrides in profileRepository.observeAllOverrides() {
                    self.profileOverrides = overrides
                }
            } catch {}
        })

        observationTasks.append(Task {
            do {
                for try await hidden in appSettingsRepository.observeHiddenChatIds() {
                    self.hiddenChatIds = hidden
                }
            } catch {}
        })

        observationTasks.append(Task {
            do {
                for try await stealth in stealthRepository.observeGlobalSettings() {
                    self.stealthSettings = stealth
                }
            } catch {}
        })

        Task {
            await refreshChats()
        }
    }

    public func stop() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
    }

    public func refreshChats() async {
        if let fetched = try? await transport.fetchChats(limit: 120) {
            self.chats = fetched.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.lastMessageDate > $1.lastMessageDate
            }
            for chat in fetched {
                if let uid = chat.peerUserId, remoteProfiles[uid] == nil {
                    if let profile = try? await transport.fetchUserProfile(userId: uid) {
                        remoteProfiles[uid] = profile
                    }
                }
            }
        }
    }

    public func handleTransportEvent(_ event: TransportEvent) {
        switch event {
        case .chatsUpdated(let updated):
            self.chats = updated.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.lastMessageDate > $1.lastMessageDate
            }
        case .foldersUpdated(let updatedFolders):
            self.folders = updatedFolders
        case .userUpdated(let profile):
            self.remoteProfiles[profile.userId] = profile
        case .activeCallStateChanged(let call):
            self.activeCall = call
        default:
            break
        }
    }

    public func effectiveProfile(for chat: ChatDialogSummary) -> EffectiveUserProfile {
        let targetId = chat.peerUserId ?? chat.chatId
        let remote = remoteProfiles[targetId] ?? RemoteUserProfile(
            userId: targetId,
            firstName: chat.title,
            avatarLocalPath: chat.avatarLocalPath,
            isChannelOrGroup: chat.kind != .privateChat && chat.kind != .secretChat
        )
        return EffectiveUserProfile.merge(remote: remote, override: profileOverrides[targetId])
    }

    public var visibleChats: [ChatDialogSummary] {
        chats.filter { chat in
            if hiddenChatIds.contains(chat.chatId) {
                return false
            }
            if let folderId = selectedFolderId,
               let folder = folders.first(where: { $0.id == folderId }),
               !folder.includedChatIds.isEmpty,
               !folder.includedChatIds.contains(chat.chatId) {
                return false
            }
            if !searchText.isEmpty {
                let eff = effectiveProfile(for: chat)
                let query = searchText.lowercased()
                return eff.fullName.lowercased().contains(query) ||
                    chat.lastMessagePreview.lowercased().contains(query) ||
                    String(chat.chatId).contains(query)
            }
            return true
        }
    }

    public var hiddenChatsList: [ChatDialogSummary] {
        switch vaultAccessState {
        case .locked:
            return []
        case .unlockedDecoy:
            return []
        case .unlockedReal:
            return chats.filter { hiddenChatIds.contains($0.chatId) }
        }
    }

    public func toggleMasterGhostMode() {
        Task {
            _ = try? await stealthRepository.toggleMasterGhostMode()
        }
    }

    public func setChatHidden(_ chatId: Int64, hidden: Bool) {
        Task {
            try? await appSettingsRepository.setChatHidden(chatId: chatId, hidden: hidden, decoyVisible: false)
        }
    }

    public func markChatReadManually(_ chatId: Int64, messageIds: [Int64]) {
        Task {
            try? await transport.viewMessages(chatId: chatId, messageIds: messageIds, forceRead: true)
        }
    }
}
