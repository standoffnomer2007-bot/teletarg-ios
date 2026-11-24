import PhotosUI
import SwiftUI

public struct LocalProfileEditorView: View {
    let remoteProfile: RemoteUserProfile
    let repository: any ProfileOverrideRepositoryProtocol
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ProfileOverrideRecord
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var firstNameText: String = ""
    @State private var lastNameText: String = ""
    @State private var usernameText: String = ""
    @State private var bioText: String = ""
    @State private var statusMode: ActivityStatusMode = .remote
    @State private var customStatusText: String = ""
    @State private var nameColorHex: String = ""
    @State private var headerColorHex: String = ""
    @State private var selectedBadges: Set<ProfileBadge> = []
    @State private var badgesOverridden: Bool = false
    @State private var emojiStatusText: String = ""
    @State private var privateNoteText: String = ""
    @State private var statusMessage: String?

    public init(
        remoteProfile: RemoteUserProfile,
        existingOverride: ProfileOverrideRecord?,
        repository: any ProfileOverrideRepositoryProtocol
    ) {
        self.remoteProfile = remoteProfile
        self.repository = repository
        let initial = existingOverride ?? ProfileOverrideRecord(userId: remoteProfile.userId)
        self._draft = State(initialValue: initial)
        self._firstNameText = State(initialValue: initial.firstName ?? remoteProfile.firstName)
        self._lastNameText = State(initialValue: initial.lastName ?? remoteProfile.lastName)
        self._usernameText = State(initialValue: initial.username ?? (remoteProfile.username ?? ""))
        self._bioText = State(initialValue: initial.bio ?? (remoteProfile.bio ?? ""))
        self._statusMode = State(initialValue: initial.activityStatusMode ?? .remote)
        self._customStatusText = State(initialValue: initial.activityStatusText ?? "")
        self._nameColorHex = State(initialValue: initial.nameColorHex ?? (remoteProfile.nameColorHex ?? "#2AABEE"))
        self._headerColorHex = State(initialValue: initial.headerColorHex ?? (remoteProfile.headerColorHex ?? "#1C2430"))
        self._selectedBadges = State(initialValue: Set(initial.decodedBadges ?? remoteProfile.badges))
        self._badgesOverridden = State(initialValue: initial.decodedBadges != nil)
        self._emojiStatusText = State(initialValue: initial.emojiStatus ?? (remoteProfile.emojiStatus ?? ""))
        self._privateNoteText = State(initialValue: initial.privateNote ?? "")
    }

    private var livePreviewProfile: EffectiveUserProfile {
        EffectiveUserProfile.merge(remote: remoteProfile, override: draft)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Превью в реальном времени (только локально)") {
                    livePreviewCard
                }

                Section("Аватар из галереи (фото / видео)") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
                        Label("Выбрать локальный аватар", systemImage: "photo.on.rectangle.angled")
                    }
                    if draft.avatarLocalPath != nil {
                        Button("Сбросить аватар к оригиналу", role: .destructive) {
                            resetSingleField(.avatarLocalPath)
                        }
                    }
                }

                Section("Основные поля") {
                    fieldRow(label: "Имя", text: $firstNameText, field: .firstName) { draft.firstName = $0 }
                    fieldRow(label: "Фамилия", text: $lastNameText, field: .lastName) { draft.lastName = $0 }
                    fieldRow(label: "@username", text: $usernameText, field: .username) { draft.username = $0 }
                    fieldRow(label: "Био / описание", text: $bioText, field: .bio) { draft.bio = $0 }
                    fieldRow(label: "Эмодзи-статус", text: $emojiStatusText, field: .emojiStatus) { draft.emojiStatus = $0 }
                }

                Section("Статус активности") {
                    Picker("Режим статуса", selection: $statusMode) {
                        Text("Оригинал с сервера").tag(ActivityStatusMode.remote)
                        Text("В сети").tag(ActivityStatusMode.online)
                        Text("Не в сети").tag(ActivityStatusMode.offline)
                        Text("Был(а) недавно").tag(ActivityStatusMode.recently)
                        Text("Свой текст").tag(ActivityStatusMode.customText)
                    }
                    .onChange(of: statusMode) { _, newValue in
                        draft.activityStatusMode = (newValue == .remote) ? nil : newValue
                    }

                    if statusMode == .customText {
                        TextField("Кастомный статус", text: $customStatusText)
                            .onChange(of: customStatusText) { _, newValue in
                                draft.activityStatusText = newValue
                            }
                    }

                    if draft.activityStatusMode != nil {
                        Button("Сбросить статус") { resetSingleField(.activityStatus) }
                            .font(.caption)
                    }
                }

                Section("Цвета имени и шапки (HEX)") {
                    fieldRow(label: "Цвет имени (#RRGGBB)", text: $nameColorHex, field: .nameColorHex) { draft.nameColorHex = $0 }
                    fieldRow(label: "Цвет шапки (#RRGGBB)", text: $headerColorHex, field: .headerColorHex) { draft.headerColorHex = $0 }
                }

                Section("Кастомные бейджи") {
                    ForEach(ProfileBadge.allCases) { badge in
                        Toggle(isOn: Binding(
                            get: { selectedBadges.contains(badge) },
                            set: { enabled in
                                badgesOverridden = true
                                if enabled { selectedBadges.insert(badge) } else { selectedBadges.remove(badge) }
                                draft.setBadges(Array(selectedBadges))
                            }
                        )) {
                            Label(badge.displayTitle, systemImage: badge.systemSymbolName)
                        }
                    }
                    if badgesOverridden {
                        Button("Сбросить бейджи") { resetSingleField(.badges) }
                            .font(.caption)
                    }
                }

                Section("Личная заметка о контакте") {
                    TextField("Видна только вам...", text: $privateNoteText, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: privateNoteText) { _, newValue in
                            draft.privateNote = newValue.isEmpty ? nil : newValue
                        }
                    if draft.privateNote != nil {
                        Button("Очистить заметку") { resetSingleField(.privateNote) }
                            .font(.caption)
                    }
                }

                Section {
                    Button("Сбросить весь профиль к оригиналу", role: .destructive) {
                        Task {
                            try? await repository.resetProfile(for: remoteProfile.userId)
                            dismiss()
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage).font(.footnote).foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Локальный профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        Task {
                            try? await repository.saveOverride(draft)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("picked_\(UUID().uuidString).jpg")
                        try? data.write(to: tempURL)
                        if let savedPath = try? await repository.saveAvatarMedia(
                            for: remoteProfile.userId,
                            sourceURL: tempURL,
                            isVideo: false
                        ) {
                            draft.avatarLocalPath = savedPath
                            draft.avatarIsVideo = false
                            statusMessage = "Локальный аватар обновлён."
                        }
                    }
                }
            }
        }
    }

    private var livePreviewCard: some View {
        let preview = livePreviewProfile
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarCircleView(
                    localPath: preview.avatarLocalPath,
                    initials: String(preview.fullName.prefix(1)).uppercased(),
                    accentHex: preview.nameColorHex,
                    size: 56,
                    isOnline: preview.isOnline
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(preview.fullName)
                            .font(.headline)
                            .foregroundStyle(Color(hex: preview.nameColorHex) ?? .white)
                        ForEach(preview.badges) { badge in
                            Image(systemName: badge.systemSymbolName)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        if let emoji = preview.emojiStatus, !emoji.isEmpty {
                            Text(emoji)
                        }
                    }
                    if let username = preview.formattedUsername {
                        Text(username)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(preview.statusDescription)
                        .font(.caption2)
                        .foregroundStyle(preview.isOnline ? .green : .white.opacity(0.75))
                }
                Spacer()
            }

            if let bio = preview.bio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let note = preview.privateNote, !note.isEmpty {
                Text("Заметка: \(note)")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(14)
        .background(Color(hex: preview.headerColorHex) ?? Color.blue.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func fieldRow(
        label: String,
        text: Binding<String>,
        field: ProfileOverrideField,
        onCommit: @escaping (String) -> Void
    ) -> some View {
        HStack {
            TextField(label, text: text)
                .onChange(of: text.wrappedValue) { _, newValue in
                    onCommit(newValue)
                }
            if livePreviewProfile.overriddenFields.contains(field) {
                Button("Сброс") {
                    resetSingleField(field)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }

    private func resetSingleField(_ field: ProfileOverrideField) {
        draft.reset(field: field)
        switch field {
        case .firstName: firstNameText = remoteProfile.firstName
        case .lastName: lastNameText = remoteProfile.lastName
        case .username: usernameText = remoteProfile.username ?? ""
        case .bio: bioText = remoteProfile.bio ?? ""
        case .activityStatus:
            statusMode = .remote
            customStatusText = ""
        case .nameColorHex: nameColorHex = remoteProfile.nameColorHex ?? "#2AABEE"
        case .headerColorHex: headerColorHex = remoteProfile.headerColorHex ?? "#1C2430"
        case .badges:
            badgesOverridden = false
            selectedBadges = Set(remoteProfile.badges)
        case .emojiStatus: emojiStatusText = remoteProfile.emojiStatus ?? ""
        case .privateNote: privateNoteText = ""
        case .avatarLocalPath: break
        }
        Task {
            try? await repository.resetField(field, for: remoteProfile.userId)
        }
    }
}
