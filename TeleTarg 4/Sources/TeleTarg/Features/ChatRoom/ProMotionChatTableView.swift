import SwiftUI
import UIKit

public struct MessageRowActionCallbacks {
    public let onCopy: (CachedMessageRecord) -> Void
    public let onReply: (CachedMessageRecord) -> Void
    public let onQuoteSelection: (String, CachedMessageRecord) -> Void
    public let onTranslate: (CachedMessageRecord) -> Void
    public let onShowEditHistory: (CachedMessageRecord) -> Void
    public let onOpenViewOnce: (CachedMessageRecord) -> Void
    public let onShowRawMetadata: (CachedMessageRecord) -> Void
    public let onOpenAuthorEditor: (Int64) -> Void
}

/// UIKit-лента сообщений с нативным реиспользованием ячеек и 120Hz ProMotion-скроллом.
/// Поддерживает мгновенное переключение раскладки между `classic` (баблы) и `discord` (плотный стиль с группировкой).
public struct ProMotionChatTableView: UIViewRepresentable {
    let messages: [CachedMessageRecord]
    let layoutMode: AppLayoutMode
    let settings: AppSettingsRecord
    let translatedTexts: [Int64: String]
    let resolveAuthor: (Int64) -> EffectiveUserProfile
    let callbacks: MessageRowActionCallbacks

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
        tableView.allowsSelection = false
        tableView.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        tableView.register(ClassicMessageCell.self, forCellReuseIdentifier: ClassicMessageCell.reuseID)
        tableView.register(DiscordMessageCell.self, forCellReuseIdentifier: DiscordMessageCell.reuseID)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        return tableView
    }

    public func updateUIView(_ uiView: UITableView, context: Context) {
        let previousCount = context.coordinator.parent.messages.count
        context.coordinator.parent = self
        uiView.reloadData()

        if messages.count > previousCount, !messages.isEmpty {
            let lastIndex = IndexPath(row: messages.count - 1, section: 0)
            uiView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
    }

    public final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: ProMotionChatTableView

        init(parent: ProMotionChatTableView) {
            self.parent = parent
        }

        public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            parent.messages.count
        }

        public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let message = parent.messages[indexPath.row]
            let author = parent.resolveAuthor(message.senderUserId)
            let translation = parent.translatedTexts[message.messageId]

            switch parent.layoutMode {
            case .classic:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: ClassicMessageCell.reuseID,
                    for: indexPath
                ) as! ClassicMessageCell
                cell.configure(
                    message: message,
                    author: author,
                    translation: translation,
                    settings: parent.settings,
                    onTapEdited: { [weak self] in self?.parent.callbacks.onShowEditHistory(message) },
                    onTapViewOnce: { [weak self] in self?.parent.callbacks.onOpenViewOnce(message) }
                )
                return cell

            case .discord:
                let isGroupedWithPrevious: Bool
                if indexPath.row > 0 {
                    let prev = parent.messages[indexPath.row - 1]
                    let withinFiveMinutes = message.sentAt.timeIntervalSince(prev.sentAt) < 300
                    isGroupedWithPrevious = prev.senderUserId == message.senderUserId && withinFiveMinutes
                } else {
                    isGroupedWithPrevious = false
                }

                let cell = tableView.dequeueReusableCell(
                    withIdentifier: DiscordMessageCell.reuseID,
                    for: indexPath
                ) as! DiscordMessageCell
                cell.configure(
                    message: message,
                    author: author,
                    translation: translation,
                    groupedWithPrevious: isGroupedWithPrevious,
                    settings: parent.settings,
                    onTapEdited: { [weak self] in self?.parent.callbacks.onShowEditHistory(message) },
                    onTapViewOnce: { [weak self] in self?.parent.callbacks.onOpenViewOnce(message) },
                    onTapAuthor: { [weak self] in self?.parent.callbacks.onOpenAuthorEditor(message.senderUserId) }
                )
                return cell
            }
        }

        public func tableView(
            _ tableView: UITableView,
            contextMenuConfigurationForRowAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            let message = parent.messages[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return UIMenu() }
                var actions: [UIAction] = [
                    UIAction(title: "Ответить", image: UIImage(systemName: "arrowshape.turn.up.left")) { _ in
                        self.parent.callbacks.onReply(message)
                    },
                    UIAction(title: "Скопировать текст", image: UIImage(systemName: "doc.on.doc")) { _ in
                        self.parent.callbacks.onCopy(message)
                    },
                    UIAction(title: "Цитировать фрагмент", image: UIImage(systemName: "text.quote")) { _ in
                        let excerpt = String((message.text.isEmpty ? (message.caption ?? "") : message.text).prefix(80))
                        self.parent.callbacks.onQuoteSelection(excerpt, message)
                    },
                    UIAction(title: "Перевести", image: UIImage(systemName: "character.book.closed")) { _ in
                        self.parent.callbacks.onTranslate(message)
                    }
                ]

                if message.editCount > 0 {
                    actions.append(
                        UIAction(title: "История редактирований (\(message.editCount))", image: UIImage(systemName: "clock.arrow.circlepath")) { _ in
                            self.parent.callbacks.onShowEditHistory(message)
                        }
                    )
                }

                if message.isViewOnce {
                    actions.append(
                        UIAction(title: "Открыть сохранённый TTL-файл", image: UIImage(systemName: "flame.fill")) { _ in
                            self.parent.callbacks.onOpenViewOnce(message)
                        }
                    )
                }

                actions.append(
                    UIAction(title: "Локальный редактор профиля автора", image: UIImage(systemName: "person.crop.circle.badge.exclamationmark")) { _ in
                        self.parent.callbacks.onOpenAuthorEditor(message.senderUserId)
                    }
                )

                actions.append(
                    UIAction(title: "Метаданные и Raw JSON", image: UIImage(systemName: "curlybraces")) { _ in
                        self.parent.callbacks.onShowRawMetadata(message)
                    }
                )

                return UIMenu(title: "Msg #\(message.messageId)", children: actions)
            }
        }
    }
}

// MARK: - Classic iOS Bubble Cell

public final class ClassicMessageCell: UITableViewCell {
    static let reuseID = "ClassicMessageCell"

    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let authorLabel = UILabel()
    private let bodyTextView = UITextView()
    private let translationLabel = UILabel()
    private let deletedBadgeLabel = UILabel()
    private let viewOnceButton = UIButton(type: .system)
    private let metaRow = UIStackView()
    private let editedButton = UIButton(type: .system)
    private let timeLabel = UILabel()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var onTapEdited: (() -> Void)?
    private var onTapViewOnce: (() -> Void)?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubbleView.layer.cornerRadius = 16
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(stackView)

        authorLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        bodyTextView.isEditable = false
        bodyTextView.isScrollEnabled = false
        bodyTextView.isSelectable = true
        bodyTextView.backgroundColor = .clear
        bodyTextView.textContainerInset = .zero
        bodyTextView.textContainer.lineFragmentPadding = 0

        translationLabel.numberOfLines = 0
        translationLabel.font = .italicSystemFont(ofSize: 13)
        translationLabel.textColor = .secondaryLabel

        deletedBadgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        deletedBadgeLabel.textColor = .systemRed

        viewOnceButton.setTitle("Открыть сохранённое TTL-медиа", for: .normal)
        viewOnceButton.contentHorizontalAlignment = .leading
        viewOnceButton.addTarget(self, action: #selector(handleViewOnceTap), for: .touchUpInside)

        editedButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        editedButton.addTarget(self, action: #selector(handleEditedTap), for: .touchUpInside)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabel

        metaRow.axis = .horizontal
        metaRow.spacing = 8
        metaRow.addArrangedSubview(UIView())
        metaRow.addArrangedSubview(editedButton)
        metaRow.addArrangedSubview(timeLabel)

        [authorLabel, deletedBadgeLabel, bodyTextView, viewOnceButton, translationLabel, metaRow].forEach {
            stackView.addArrangedSubview($0)
        }

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),
            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }

    public func configure(
        message: CachedMessageRecord,
        author: EffectiveUserProfile,
        translation: String?,
        settings: AppSettingsRecord,
        onTapEdited: @escaping () -> Void,
        onTapViewOnce: @escaping () -> Void
    ) {
        self.onTapEdited = onTapEdited
        self.onTapViewOnce = onTapViewOnce

        leadingConstraint.isActive = !message.isOutgoing
        trailingConstraint.isActive = message.isOutgoing

        bubbleView.backgroundColor = message.isOutgoing
            ? UIColor.systemBlue.withAlphaComponent(0.18)
            : UIColor.secondarySystemBackground

        authorLabel.isHidden = message.isOutgoing
        authorLabel.text = author.fullName
        authorLabel.textColor = UIColor(hex: author.nameColorHex) ?? .systemBlue

        let bodyFontSize = CGFloat(16.0 * settings.fontSizeScale)
        bodyTextView.font = settings.fontFamily.uiFont(size: bodyFontSize)
        bodyTextView.textColor = .label
        bodyTextView.text = message.text.isEmpty ? (message.caption ?? "[\(message.contentType.rawValue)]") : message.text

        if let badge = message.deletedBadgeText {
            deletedBadgeLabel.isHidden = false
            deletedBadgeLabel.text = "● \(badge)"
        } else {
            deletedBadgeLabel.isHidden = true
        }

        viewOnceButton.isHidden = !message.isViewOnce
        translationLabel.isHidden = translation == nil
        translationLabel.text = translation.map { "Перевод: \($0)" }

        if message.editCount > 0 {
            editedButton.isHidden = false
            editedButton.setTitle("изменено (\(message.editCount))", for: .normal)
        } else {
            editedButton.isHidden = true
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: message.sentAt)
    }

    @objc private func handleEditedTap() { onTapEdited?() }
    @objc private func handleViewOnceTap() { onTapViewOnce?() }
}

// MARK: - Discord Compact Message Cell

public final class DiscordMessageCell: UITableViewCell {
    static let reuseID = "DiscordMessageCell"

    private let avatarButton = UIButton(type: .custom)
    private let headerRow = UIStackView()
    private let authorButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let editedButton = UIButton(type: .system)
    private let deletedPill = UILabel()
    private let bodyTextView = UITextView()
    private let viewOnceButton = UIButton(type: .system)
    private let translationLabel = UILabel()
    private let reactionsLabel = UILabel()
    private let rightStack = UIStackView()

    private var onTapEdited: (() -> Void)?
    private var onTapViewOnce: (() -> Void)?
    private var onTapAuthor: (() -> Void)?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarButton.layer.cornerRadius = 19
        avatarButton.clipsToBounds = true
        avatarButton.backgroundColor = UIColor(red: 0.345, green: 0.396, blue: 0.949, alpha: 0.25)
        avatarButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        avatarButton.addTarget(self, action: #selector(handleAuthorTap), for: .touchUpInside)
        contentView.addSubview(avatarButton)

        authorButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        authorButton.addTarget(self, action: #selector(handleAuthorTap), for: .touchUpInside)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = UIColor(white: 0.58, alpha: 1)

        editedButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        editedButton.tintColor = UIColor(red: 0.54, green: 0.62, blue: 1.0, alpha: 1)
        editedButton.addTarget(self, action: #selector(handleEditedTap), for: .touchUpInside)

        deletedPill.font = .systemFont(ofSize: 11, weight: .semibold)
        deletedPill.textColor = .systemRed

        headerRow.axis = .horizontal
        headerRow.spacing = 6
        headerRow.alignment = .center
        headerRow.addArrangedSubview(authorButton)
        headerRow.addArrangedSubview(timeLabel)
        headerRow.addArrangedSubview(editedButton)
        headerRow.addArrangedSubview(UIView())

        bodyTextView.isEditable = false
        bodyTextView.isScrollEnabled = false
        bodyTextView.isSelectable = true
        bodyTextView.backgroundColor = .clear
        bodyTextView.textContainerInset = .zero
        bodyTextView.textContainer.lineFragmentPadding = 0

        viewOnceButton.setTitle("TTL-файл сохранён — открыть", for: .normal)
        viewOnceButton.contentHorizontalAlignment = .leading
        viewOnceButton.addTarget(self, action: #selector(handleViewOnceTap), for: .touchUpInside)

        translationLabel.numberOfLines = 0
        translationLabel.font = .italicSystemFont(ofSize: 13)
        translationLabel.textColor = UIColor(white: 0.72, alpha: 1)

        reactionsLabel.font = .systemFont(ofSize: 12, weight: .medium)
        reactionsLabel.textColor = UIColor(white: 0.85, alpha: 1)

        rightStack.axis = .vertical
        rightStack.spacing = 3
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        [headerRow, deletedPill, bodyTextView, viewOnceButton, translationLabel, reactionsLabel].forEach {
            rightStack.addArrangedSubview($0)
        }
        contentView.addSubview(rightStack)

        NSLayoutConstraint.activate([
            avatarButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            avatarButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            avatarButton.widthAnchor.constraint(equalToConstant: 38),
            avatarButton.heightAnchor.constraint(equalToConstant: 38),

            rightStack.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 12),
            rightStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            rightStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            rightStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }

    public func configure(
        message: CachedMessageRecord,
        author: EffectiveUserProfile,
        translation: String?,
        groupedWithPrevious: Bool,
        settings: AppSettingsRecord,
        onTapEdited: @escaping () -> Void,
        onTapViewOnce: @escaping () -> Void,
        onTapAuthor: @escaping () -> Void
    ) {
        self.onTapEdited = onTapEdited
        self.onTapViewOnce = onTapViewOnce
        self.onTapAuthor = onTapAuthor

        avatarButton.isHidden = groupedWithPrevious
        headerRow.isHidden = groupedWithPrevious

        if !groupedWithPrevious {
            if let path = author.avatarLocalPath, let img = UIImage(contentsOfFile: path) {
                avatarButton.setImage(img, for: .normal)
                avatarButton.setTitle(nil, for: .normal)
            } else {
                avatarButton.setImage(nil, for: .normal)
                avatarButton.setTitle(String(author.fullName.prefix(1)).uppercased(), for: .normal)
            }
            authorButton.setTitle(author.fullName, for: .normal)
            authorButton.setTitleColor(UIColor(hex: author.nameColorHex) ?? .white, for: .normal)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: message.sentAt)

        editedButton.isHidden = message.editCount == 0
        if message.editCount > 0 {
            editedButton.setTitle("(изм. \(message.editCount))", for: .normal)
        }

        if let badge = message.deletedBadgeText {
            deletedPill.isHidden = false
            deletedPill.text = "● \(badge)"
        } else {
            deletedPill.isHidden = true
        }

        let fontSize = CGFloat(15.0 * settings.fontSizeScale)
        bodyTextView.font = settings.fontFamily.uiFont(size: fontSize)
        bodyTextView.textColor = UIColor(white: 0.94, alpha: 1)
        bodyTextView.text = message.text.isEmpty ? (message.caption ?? "[\(message.contentType.rawValue)]") : message.text

        viewOnceButton.isHidden = !message.isViewOnce
        translationLabel.isHidden = translation == nil
        translationLabel.text = translation.map { "Перевод: \($0)" }

        let reactions = message.decodedReactions
        if reactions.isEmpty {
            reactionsLabel.isHidden = true
        } else {
            reactionsLabel.isHidden = false
            reactionsLabel.text = reactions.map { "\($0.emoji) \($0.count)" }.joined(separator: "   ")
        }
    }

    @objc private func handleEditedTap() { onTapEdited?() }
    @objc private func handleViewOnceTap() { onTapViewOnce?() }
    @objc private func handleAuthorTap() { onTapAuthor?() }
}
