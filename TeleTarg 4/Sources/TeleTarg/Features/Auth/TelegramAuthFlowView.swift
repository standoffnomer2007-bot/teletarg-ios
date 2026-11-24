import CoreImage.CIFilterBuiltins
import SwiftUI

public struct TelegramAuthFlowView: View {
    @Binding var authStage: AuthStage
    let transport: any MessengerTransport
    let keychain: any KeychainServiceProtocol

    @State private var apiIdText: String = ""
    @State private var apiHashText: String = ""
    @State private var phoneNumber: String = ""
    @State private var smsCode: String = ""
    @State private var twoFactorPassword: String = ""
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?

    public init(
        authStage: Binding<AuthStage>,
        transport: any MessengerTransport,
        keychain: any KeychainServiceProtocol
    ) {
        self._authStage = authStage
        self.transport = transport
        self.keychain = keychain
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        Text("TeleTarg")
                            .font(.largeTitle.bold())
                        Text("Нативный клиент Telegram (TDLib)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    stageContent

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Вход в Telegram")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let savedId = try? keychain.getString(for: .telegramApiId) {
                    apiIdText = savedId
                }
                if let savedHash = try? keychain.getString(for: .telegramApiHash) {
                    apiHashText = savedHash
                }
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch authStage {
        case .idle, .waitTdlibParameters, .closed:
            VStack(alignment: .leading, spacing: 14) {
                Text("Ключи Telegram API (my.telegram.org)")
                    .font(.headline)
                TextField("API ID (число)", text: $apiIdText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Hash", text: $apiHashText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button(action: startClient) {
                    actionLabel("Подключиться к TDLib")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || Int32(apiIdText.trimmingCharacters(in: .whitespaces)) == nil || apiHashText.isEmpty)
            }

        case .waitPhoneNumber:
            VStack(alignment: .leading, spacing: 14) {
                Text("Номер телефона")
                    .font(.headline)
                TextField("+7 999 000 00 00", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
                Button(action: submitPhone) {
                    actionLabel("Получить код")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || phoneNumber.trimmingCharacters(in: .whitespaces).count < 6)

                Button("Войти по QR-коду") {
                    requestQR()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }

        case .waitCode(let phone):
            VStack(alignment: .leading, spacing: 14) {
                Text("Код подтверждения отправлен на \(phone)")
                    .font(.headline)
                TextField("Код из Telegram / SMS", text: $smsCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button(action: submitCode) {
                    actionLabel("Подтвердить код")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || smsCode.trimmingCharacters(in: .whitespaces).count < 4)
            }

        case .waitPassword(let hint):
            VStack(alignment: .leading, spacing: 14) {
                Text("Облачный пароль (2FA)")
                    .font(.headline)
                if !hint.isEmpty {
                    Text("Подсказка: \(hint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SecureField("Пароль", text: $twoFactorPassword)
                    .textFieldStyle(.roundedBorder)
                Button(action: submitPassword) {
                    actionLabel("Войти")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || twoFactorPassword.isEmpty)
            }

        case .waitQrConfirmation(let link):
            VStack(spacing: 16) {
                Text("Отсканируйте QR в Telegram → Настройки → Устройства")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let image = generateQRCode(from: link) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text("Ожидаем подтверждения входа...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            ProgressView("Загружаем чаты...")
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack {
            Spacer()
            if isBusy {
                ProgressView().tint(.white)
            } else {
                Text(title).fontWeight(.semibold)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func startClient() {
        guard let apiId = Int32(apiIdText.trimmingCharacters(in: .whitespaces)) else { return }
        let hash = apiHashText.trimmingCharacters(in: .whitespacesAndNewlines)
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try keychain.setString(String(apiId), for: .telegramApiId)
                try keychain.setString(hash, for: .telegramApiHash)
                try await transport.start(apiId: apiId, apiHash: hash)
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func submitPhone() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await transport.submitPhoneNumber(phoneNumber.trimmingCharacters(in: .whitespaces))
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func requestQR() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await transport.requestQrCodeAuthentication()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func submitCode() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await transport.submitAuthCode(smsCode.trimmingCharacters(in: .whitespaces))
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func submitPassword() {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await transport.submitTwoFactorPassword(twoFactorPassword)
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
