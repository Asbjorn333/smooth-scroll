@preconcurrency import AppKit

final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowSwitcherBlockerView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

@MainActor
final class WindowSwitcherCardView: NSView {
    private static let previewAspectRatio = 0.66
    private static let minimumPreviewHeight: CGFloat = 124
    private static let maximumPreviewHeight: CGFloat = 184
    private static let titleAreaHeight: CGFloat = 22
    private static let topInset: CGFloat = 12
    private static let bottomInset: CGFloat = 14
    private static let titleSpacing: CGFloat = 10

    private let item: WindowSwitchItem
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let placeholderIconView = NSImageView()
    private let badgeBackgroundView = NSView()
    private let badgeIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    var onClick: (() -> Void)?

    init(item: WindowSwitchItem) {
        self.item = item
        super.init(frame: .zero)
        configure()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    static func cardHeight(for width: CGFloat) -> CGFloat {
        topInset + previewHeight(for: width) + titleSpacing + titleAreaHeight + bottomInset
    }

    func updateCardSize(width: CGFloat) {
        widthConstraint?.constant = width
        let previewHeight = Self.previewHeight(for: width)
        previewHeightConstraint?.constant = previewHeight
        heightConstraint?.constant = Self.cardHeight(for: width)
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (
            selected
                ? NSColor.black.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.03)
        ).cgColor
        layer?.borderColor = (
            selected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.05)
        ).cgColor
        layer?.borderWidth = selected ? 2 : 1
        alphaValue = selected ? 1.0 : 0.92
        titleLabel.textColor = selected ? .labelColor : .secondaryLabelColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 16
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown

        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
        placeholderIconView.imageScaling = .scaleProportionallyUpOrDown

        badgeBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        badgeBackgroundView.wantsLayer = true
        badgeBackgroundView.layer?.cornerRadius = 14
        badgeBackgroundView.layer?.masksToBounds = true
        badgeBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor

        badgeIconView.translatesAutoresizingMaskIntoConstraints = false
        badgeIconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(previewContainer)
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(placeholderIconView)
        previewContainer.addSubview(badgeBackgroundView)
        badgeBackgroundView.addSubview(badgeIconView)
        addSubview(titleLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 220)
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.cardHeight(for: 220))
        previewHeightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: Self.previewHeight(for: 220))

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            previewHeightConstraint
        ].compactMap { $0 } + [
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.topInset),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.topInset),
            previewContainer.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),

            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderIconView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 52),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 52),

            badgeBackgroundView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 8),
            badgeBackgroundView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -8),
            badgeBackgroundView.widthAnchor.constraint(equalToConstant: 28),
            badgeBackgroundView.heightAnchor.constraint(equalToConstant: 28),

            badgeIconView.centerXAnchor.constraint(equalTo: badgeBackgroundView.centerXAnchor),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeBackgroundView.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 18),
            badgeIconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: Self.titleSpacing),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset)
        ])
    }

    private static func previewHeight(for width: CGFloat) -> CGFloat {
        max(minimumPreviewHeight, min(maximumPreviewHeight, floor(width * previewAspectRatio)))
    }

    private func render() {
        titleLabel.stringValue = item.target.displayTitle
        previewImageView.image = item.previewImage
        previewImageView.isHidden = item.previewImage == nil

        placeholderIconView.image = item.appIcon
        placeholderIconView.isHidden = item.previewImage != nil

        badgeIconView.image = item.appIcon
        badgeBackgroundView.isHidden = item.appIcon == nil || item.previewImage == nil
    }
}
