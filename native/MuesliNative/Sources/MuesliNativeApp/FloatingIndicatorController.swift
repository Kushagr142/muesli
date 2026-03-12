import AppKit
import Foundation

@MainActor
private final class HoverIndicatorView: NSView {
    weak var owner: FloatingIndicatorController?
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        owner?.setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        owner?.setHovered(false)
    }
}

@MainActor
final class FloatingIndicatorController {
    private var panel: NSPanel?
    private var contentView: HoverIndicatorView?
    private var iconLabel: NSTextField?
    private var textLabel: NSTextField?
    private var state: DictationState = .idle
    private var isHovered = false
    private let configStore: ConfigStore

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func setState(_ state: DictationState, config: AppConfig) {
        self.state = state
        if state != .idle {
            isHovered = false
        }
        guard config.showFloatingIndicator else {
            close()
            return
        }
        if panel == nil {
            createPanel(config: config)
        }
        guard let panel, let contentView, let iconLabel, let textLabel else { return }
        let style = styleForState(state)
        panel.setFrame(frameForState(state, config: config), display: true)
        contentView.frame = NSRect(origin: .zero, size: panel.frame.size)
        contentView.layer?.cornerRadius = panel.frame.height / 2
        contentView.layer?.backgroundColor = style.background.cgColor
        contentView.layer?.borderWidth = 1.0
        contentView.layer?.borderColor = style.border.cgColor
        iconLabel.stringValue = style.icon
        iconLabel.textColor = style.iconColor
        textLabel.stringValue = style.title
        textLabel.textColor = style.textColor
        textLabel.isHidden = style.title.isEmpty

        layoutLabels(iconLabel: iconLabel, textLabel: textLabel, in: panel.frame.size, hasTitle: !style.title.isEmpty)
        panel.alphaValue = style.alpha
        panel.orderFrontRegardless()
    }

    func ensureVisible(config: AppConfig) {
        setState(state, config: config)
    }

    func setHovered(_ hovered: Bool) {
        guard state == .idle, isHovered != hovered else { return }
        isHovered = hovered
        let config = configStore.load()
        setState(.idle, config: config)
    }

    func close() {
        panel?.close()
        panel = nil
        contentView = nil
        iconLabel = nil
        textLabel = nil
    }

    private func createPanel(config: AppConfig) {
        let panel = NSPanel(
            contentRect: frameForState(.idle, config: config),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let contentView = HoverIndicatorView(frame: NSRect(origin: .zero, size: panel.frame.size))
        contentView.owner = self
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = panel.frame.height / 2
        contentView.layer?.masksToBounds = false

        let iconLabel = NSTextField(labelWithString: "")
        iconLabel.alignment = .center
        iconLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        contentView.addSubview(iconLabel)

        let textLabel = NSTextField(labelWithString: "")
        textLabel.alignment = .left
        textLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        contentView.addSubview(textLabel)

        panel.contentView = contentView

        self.panel = panel
        self.contentView = contentView
        self.iconLabel = iconLabel
        self.textLabel = textLabel
        setState(.idle, config: config)
    }

    private func frameForState(_ state: DictationState, config: AppConfig) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 64, height: 28)
        }
        let size: NSSize
        switch state {
        case .idle:
            size = isHovered ? NSSize(width: 246, height: 46) : NSSize(width: 58, height: 30)
        case .preparing: size = NSSize(width: 148, height: 46)
        case .recording: size = NSSize(width: 164, height: 46)
        case .transcribing: size = NSSize(width: 182, height: 46)
        }

        let origin: CGPoint
        if let manual = config.indicatorOrigin {
            origin = CGPoint(x: manual.x, y: manual.y)
        } else {
            origin = CGPoint(
                x: screen.maxX - size.width - 8,
                y: screen.minY + (screen.height * 0.56) - (size.height / 2)
            )
        }

        let x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        let y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func styleForState(_ state: DictationState) -> (background: NSColor, border: NSColor, icon: String, title: String, iconColor: NSColor, textColor: NSColor, alpha: CGFloat) {
        switch state {
        case .idle:
            return (
                .colorWith(hex: 0x000000, alpha: isHovered ? 0.96 : 0.66),
                .colorWith(hex: 0xFFFFFF, alpha: 0.18),
                "🎤",
                isHovered ? "Hold Left Cmd to dictate" : "",
                .colorWith(hex: 0xFFFFFF, alpha: 0.92),
                .colorWith(hex: 0xFFFFFF, alpha: 0.92),
                isHovered ? 1.0 : 0.82
            )
        case .preparing:
            return (
                .colorWith(hex: 0x3B4757, alpha: 0.94),
                .colorWith(hex: 0xFFFFFF, alpha: 0.24),
                "🎤",
                "Preparing",
                .white,
                .white,
                1.0
            )
        case .recording:
            return (
                .colorWith(hex: 0xD32F2F, alpha: 0.96),
                .colorWith(hex: 0xFFFFFF, alpha: 0.24),
                "🎤",
                "Listening",
                .white,
                .white,
                1.0
            )
        case .transcribing:
            return (
                .colorWith(hex: 0xD99A11, alpha: 0.96),
                .colorWith(hex: 0xFFFFFF, alpha: 0.24),
                "✍️",
                "Transcribing",
                .colorWith(hex: 0x1A140D, alpha: 0.95),
                .black,
                1.0
            )
        }
    }

    private func layoutLabels(iconLabel: NSTextField, textLabel: NSTextField, in size: NSSize, hasTitle: Bool) {
        if !hasTitle {
            let iconSize = iconLabel.attributedStringValue.size()
            let iconWidth = max(26, ceil(iconSize.width) + 4)
            let iconHeight = max(18, ceil(iconSize.height))
            iconLabel.frame = NSRect(
                x: (size.width - iconWidth) / 2,
                y: (size.height - iconHeight) / 2,
                width: iconWidth,
                height: iconHeight
            )
            textLabel.frame = .zero
            return
        }

        let iconSize = iconLabel.attributedStringValue.size()
        let textSize = textLabel.attributedStringValue.size()
        let gap: CGFloat = 10

        let iconWidth = max(24, ceil(iconSize.width) + 2)
        let iconHeight = max(18, ceil(iconSize.height))
        let textWidth = ceil(textSize.width) + 2
        let textHeight = max(16, ceil(textSize.height))

        let totalWidth = iconWidth + gap + textWidth
        let originX = max((size.width - totalWidth) / 2, 12)

        iconLabel.frame = NSRect(
            x: originX,
            y: (size.height - iconHeight) / 2,
            width: iconWidth,
            height: iconHeight
        )
        textLabel.frame = NSRect(
            x: originX + iconWidth + gap,
            y: (size.height - textHeight) / 2,
            width: textWidth,
            height: textHeight
        )
    }
}

private extension NSColor {
    static func colorWith(hex: Int, alpha: CGFloat) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
