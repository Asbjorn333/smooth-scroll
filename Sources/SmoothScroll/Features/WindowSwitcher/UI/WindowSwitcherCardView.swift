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

    func updateCardSize(width: CGFloat) {
        widthConstraint?.constant = width
        previewHeightConstraint?.constant = max(74, min(108, width * 0.64))
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (
            selected
                ? NSColor.white.withAlphaComponent(0.16)
                : NSColor.white.withAlphaComponent(0.05)
        ).cgColor
        layer?.borderColor = (
            selected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.95)
                : NSColor.white.withAlphaComponent(0.08)
        ).cgColor
        layer?.borderWidth = selected ? 2 : 1
        alphaValue = selected ? 1.0 : 0.78
        titleLabel.textColor = selected ? .labelColor : .secondaryLabelColor
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 13
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown

        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
        placeholderIconView.imageScaling = .scaleProportionallyUpOrDown

        badgeBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        badgeBackgroundView.wantsLayer = true
        badgeBackgroundView.layer?.cornerRadius = 12
        badgeBackgroundView.layer?.masksToBounds = true
        badgeBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor

        badgeIconView.translatesAutoresizingMaskIntoConstraints = false
        badgeIconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(previewContainer)
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(placeholderIconView)
        previewContainer.addSubview(badgeBackgroundView)
        badgeBackgroundView.addSubview(badgeIconView)
        addSubview(titleLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 156)
        heightConstraint = heightAnchor.constraint(equalToConstant: 146)
        previewHeightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: 96)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            previewHeightConstraint
        ].compactMap { $0 } + [
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewContainer.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            placeholderIconView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 40),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 40),

            badgeBackgroundView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 8),
            badgeBackgroundView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -8),
            badgeBackgroundView.widthAnchor.constraint(equalToConstant: 24),
            badgeBackgroundView.heightAnchor.constraint(equalToConstant: 24),

            badgeIconView.centerXAnchor.constraint(equalTo: badgeBackgroundView.centerXAnchor),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeBackgroundView.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 16),
            badgeIconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
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
