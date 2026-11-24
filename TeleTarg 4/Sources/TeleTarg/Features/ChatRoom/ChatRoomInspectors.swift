import Photos
import SwiftUI
import UIKit

// MARK: - Edit History Sheet

public struct EditHistorySheetView: View {
    let message: CachedMessageRecord
    let revisions: [MessageEditRevisionRecord]
    @Environment(\.dismiss) private var dismiss

    public init(message: CachedMessageRecord, revisions: [MessageEditRevisionRecord]) {
        self.message = message
        self.revisions = revisions
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Текущая версия") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.text.isEmpty ? (message.caption ?? "") : message.text)
                            .textSelection(.enabled)
                        if let editedAt = message.editedAt {
                            Text("Обновлено: \(editedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Предыдущие версии (\(revisions.count))") {
                    if revisions.isEmpty {
                        Text("Локальных версий до редактирования не зафиксировано.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(revisions.reversed()) { rev in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Версия #\(rev.revisionIndex)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                                Text(rev.previousText.isEmpty ? (rev.previousCaption ?? "") : rev.previousText)
                                    .textSelection(.enabled)
                                Text("Сохранено: \(rev.capturedAt.formatted(date: .abbreviated, time: .standard))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Скопировать эту версию") {
                                    UIPasteboard.general.string = rev.previousText
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("История правок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: - View-Once / TTL Media Viewer (Save, Copy, Share)

public struct ViewOnceMediaViewer: View {
    let record: ViewOnceMediaCacheRecord
    @Environment(\.dismiss) private var dismiss
    @State private var statusBanner: String?

    public init(record: ViewOnceMediaCacheRecord) {
        self.record = record
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let uiImage = UIImage(contentsOfFile: record.protectedLocalPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        record.originalFileName,
                        systemImage: "doc.fill",
                        description: Text("Файл (\(record.mimeType), \(record.fileSizeBytes) байт) сохранён в локальном защищённом кеше до истечения TTL (\(record.originalTTLSeconds) сек).")
                    )
                }

                if let statusBanner {
                    Text(statusBanner)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 12) {
                    Button {
                        saveToGallery()
                    } label: {
                        Label("В галерею", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        copyToPasteboard()
                    } label: {
                        Label("Скопировать", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: URL(fileURLWithPath: record.protectedLocalPath)) {
                        Label("Переслать", systemImage: "arrowshape.turn.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("TTL-медиа (сохранено)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func saveToGallery() {
        let fileURL = URL(fileURLWithPath: record.protectedLocalPath)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in statusBanner = "Нет доступа к Фото — выдайте разрешение в Настройках iOS." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                if record.mediaType == .photo, let img = UIImage(contentsOfFile: record.protectedLocalPath) {
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                } else if record.mediaType == .video || record.mediaType == .videoNote {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in
                    statusBanner = success ? "Сохранено в галерею без ограничений." : "Используйте «Переслать» для сохранения этого типа файла."
                }
            }
        }
    }

    private func copyToPasteboard() {
        if let img = UIImage(contentsOfFile: record.protectedLocalPath) {
            UIPasteboard.general.image = img
            statusBanner = "Изображение скопировано в буфер обмена."
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: record.protectedLocalPath)) {
            UIPasteboard.general.setData(data, forPasteboardType: record.mimeType)
            statusBanner = "Файл скопирован в буфер обмена."
        }
    }
}

// MARK: - Raw Metadata Inspector

public struct RawMetadataInspectorView: View {
    let message: CachedMessageRecord
    @Environment(\.dismiss) private var dismiss

    public init(message: CachedMessageRecord) {
        self.message = message
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Идентификаторы") {
                    LabeledContent("Chat ID", value: "\(message.chatId)")
                    LabeledContent("Message ID", value: "\(message.messageId)")
                    LabeledContent("Sender User ID", value: "\(message.senderUserId)")
                    LabeledContent("Отправлено", value: message.sentAt.formatted(date: .numeric, time: .standard))
                    LabeledContent("Локально удалено", value: message.isDeletedLocally ? "Да" : "Нет")
                    LabeledContent("Запрет пересылки на сервере", value: message.isProtectedContent ? "Да (обойдено локально)" : "Нет")
                }

                Section("Raw JSON") {
                    ScrollView(.horizontal) {
                        Text(message.rawJSON)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Скопировать Raw JSON") {
                        UIPasteboard.general.string = message.rawJSON
                    }
                }
            }
            .navigationTitle("Метаданные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
