@preconcurrency import AppKit
@preconcurrency import CoreGraphics

@MainActor
final class WindowSwitcherOverlayController {
    private let panel: WindowSwitcherPanel
    private let blockerView = WindowSwitcherBlockerView()
    private let backdropView = NSView()
    private let chromeView = NSVisualEffectView()
    private let contentContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let rowStackView = NSStackView()
    private var cardViews: [WindowSwitcherCardView] = []
    private var currentWindowIDs: [CGWindowID] = []
    private var containerWidthConstraint: NSLayoutConstraint?
    private var containerHeightConstraint: NSLayoutConstraint?
    var onItemActivated: ((Int) -> Void)?

    init() {
        panel = WindowSwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    func show(session: WindowSwitchSession) {
        let targetScreen = WindowSwitcherScreenLocator.screenContainingPointer()
        fitPanelToScreen(targetScreen)
        rebuildCardsIfNeeded(items: session.items)
        updateCardLayout(for: session.items.count, on: targetScreen)
        updateSelectionState(for: session)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.animationBehavior = .utilityWindow

        blockerView.translatesAutoresizingMaskIntoConstraints = false

        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.clear.cgColor

        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.material = .underWindowBackground
        chromeView.blendingMode = .behindWindow
        chromeView.state = .active
        chromeView.wantsLayer = true
        chromeView.layer?.cornerRadius = 26
        chromeView.layer?.masksToBounds = true
        chromeView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
        chromeView.layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
        chromeView.layer?.borderWidth = 1

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.alignment = .center
        detailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        rowStackView.translatesAutoresizingMaskIntoConstraints = false
        rowStackView.orientation = .horizontal
        rowStackView.alignment = .top
        rowStackView.distribution = .fill
        rowStackView.spacing = 18

        blockerView.addSubview(backdropView)
        blockerView.addSubview(chromeView)
        chromeView.addSubview(contentContainer)
        contentContainer.addSubview(rowStackView)
        contentContainer.addSubview(titleLabel)
        contentContainer.addSubview(detailLabel)
        panel.contentView = blockerView

        containerWidthConstraint = contentContainer.widthAnchor.constraint(equalToConstant: 980)
        containerHeightConstraint = contentContainer.heightAnchor.constraint(equalToConstant: 320)

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: blockerView.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: blockerView.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: blockerView.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: blockerView.bottomAnchor),

            chromeView.centerXAnchor.constraint(equalTo: blockerView.centerXAnchor),
            chromeView.centerYAnchor.constraint(equalTo: blockerView.centerYAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: chromeView.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),

            rowStackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor, constant: 30),
            rowStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -30),
            rowStackView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 28),
            rowStackView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: rowStackView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 20),
            detailLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -20),
            detailLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -18)
        ] + [containerWidthConstraint, containerHeightConstraint].compactMap { $0 })
    }

    private func rebuildCardsIfNeeded(items: [WindowSwitchItem]) {
        let windowIDs = items.map { $0.target.windowID }
        guard windowIDs != currentWindowIDs else {
            return
        }

        currentWindowIDs = windowIDs

        for cardView in cardViews {
            rowStackView.removeArrangedSubview(cardView)
            cardView.removeFromSuperview()
        }

        cardViews = items.map { item in
            let cardView = WindowSwitcherCardView(item: item)
            cardView.onClick = { [weak self] in
                guard let self else {
                    return
                }
                guard let index = self.cardViews.firstIndex(where: { $0 === cardView }) else {
                    return
                }
                self.onItemActivated?(index)
            }
            rowStackView.addArrangedSubview(cardView)
            return cardView
        }
    }

    private func updateCardLayout(for itemCount: Int, on screen: NSScreen?) {
        guard itemCount > 0 else {
            return
        }

        let visibleFrame = screen?.visibleFrame ?? panel.screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        let maxPanelWidth = max(640, (visibleFrame?.width ?? 1400) - 56)
        let horizontalPadding: CGFloat = 72
        let spacing = rowStackView.spacing * CGFloat(max(0, itemCount - 1))
        let availableCardWidth = (maxPanelWidth - horizontalPadding - spacing) / CGFloat(itemCount)
        let cardWidth = max(180, min(236, floor(availableCardWidth)))
        let panelWidth = min(
            maxPanelWidth,
            horizontalPadding + spacing + (cardWidth * CGFloat(itemCount))
        )
        let cardHeight = WindowSwitcherCardView.cardHeight(for: cardWidth)

        for cardView in cardViews {
            cardView.updateCardSize(width: cardWidth)
        }

        containerWidthConstraint?.constant = max(640, panelWidth)
        containerHeightConstraint?.constant = max(320, cardHeight + 108)
    }

    private func updateSelectionState(for session: WindowSwitchSession) {
        for (index, cardView) in cardViews.enumerated() {
            cardView.setSelected(index == session.selectedIndex)
        }

        let selectedItem = session.selectedItem
        titleLabel.stringValue = selectedItem.target.displayTitle
        detailLabel.stringValue = "\(selectedItem.target.appName)  •  Window \(session.selectedIndex + 1) of \(session.items.count)"
    }

    private func fitPanelToScreen(_ screen: NSScreen?) {
        guard let screen = screen ?? panel.screen ?? NSScreen.screens.first else {
            return
        }

        panel.setFrame(screen.frame, display: false)
    }
}
