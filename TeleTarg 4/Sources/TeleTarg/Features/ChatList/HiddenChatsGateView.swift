import SwiftUI

public struct HiddenChatsGateView: View {
    @Bindable var viewModel: ChatListViewModel
    let vaultService: any BiometricVaultServiceProtocol
    let keychain: any KeychainServiceProtocol
    let onSelectChat: (ChatDialogSummary) -> Void

    @State private var enteredPin: String = ""
    @State private var setupRealPin: String = ""
    @State private var setupDecoyPin: String = ""
    @State private var errorMessage: String?

    public init(
        viewModel: ChatListViewModel,
        vaultService: any BiometricVaultServiceProtocol,
        keychain: any KeychainServiceProtocol,
        onSelectChat: @escaping (ChatDialogSummary) -> Void
    ) {
        self.viewModel = viewModel
        self.vaultService = vaultService
        self.keychain = keychain
        self.onSelectChat = onSelectChat
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !keychain.hasConfiguredPin() {
                    pinSetupView
                } else if viewModel.vaultAccessState == .locked {
                    unlockView
                } else {
                    unlockedListView
                }
            }
            .navigationTitle("Скрытые чаты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        viewModel.vaultAccessState = .locked
                        viewModel.isHiddenVaultOpen = false
                    }
                }
            }
        }
    }

    private var pinSetupView: some View {
        Form {
            Section("Основной PIN-код (открывает скрытые чаты)") {
                SecureField("Минимум 4 цифры", text: $setupRealPin)
                    .keyboardType(.numberPad)
            }
            Section("Ложный PIN-код (открывает пустой список)") {
                SecureField("Опционально, другой код", text: $setupDecoyPin)
                    .keyboardType(.numberPad)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }
            Button("Сохранить PIN в Keychain") {
                guard setupRealPin.count >= 4 else {
                    errorMessage = "Основной PIN должен содержать минимум 4 цифры."
                    return
                }
                if !setupDecoyPin.isEmpty && setupDecoyPin == setupRealPin {
                    errorMessage = "Ложный PIN должен отличаться от основного."
                    return
                }
                do {
                    try keychain.saveRealPin(setupRealPin)
                    if !setupDecoyPin.isEmpty {
                        try keychain.saveDecoyPin(setupDecoyPin)
                    }
                    viewModel.vaultAccessState = .unlockedReal
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var unlockView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.blue)

            Text("Введите PIN-код или используйте \(vaultService.biometryDisplayName())")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("PIN-код", text: $enteredPin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Разблокировать") {
                let state = vaultService.unlockWithPin(enteredPin)
                if state == .locked {
                    errorMessage = "Неверный PIN-код."
                } else {
                    errorMessage = nil
                    viewModel.vaultAccessState = state
                }
                enteredPin = ""
            }
            .buttonStyle(.borderedProminent)

            if vaultService.canUseBiometrics() {
                Button {
                    Task {
                        let ok = await vaultService.authenticateWithBiometrics(reason: "Доступ к скрытым чатам TeleTarg")
                        if ok {
                            viewModel.vaultAccessState = .unlockedReal
                        }
                    }
                } label: {
                    Label("Войти через \(vaultService.biometryDisplayName())", systemImage: "faceid")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var unlockedListView: some View {
        Group {
            if viewModel.hiddenChatsList.isEmpty {
                ContentUnavailableView(
                    "Скрытых чатов нет",
                    systemImage: "tray",
                    description: Text("Удерживайте любой чат в основном списке, чтобы перенести его сюда.")
                )
            } else {
                List(viewModel.hiddenChatsList) { chat in
                    let profile = viewModel.effectiveProfile(for: chat)
                    Button {
                        viewModel.isHiddenVaultOpen = false
                        onSelectChat(chat)
                    } label: {
                        HStack {
                            Text(profile.fullName).fontWeight(.semibold)
                            Spacer()
                            Text("ID \(chat.chatId)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Вернуть") {
                            viewModel.setChatHidden(chat.chatId, hidden: false)
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }
}
