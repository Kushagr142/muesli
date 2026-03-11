import AppKit
import Foundation

@MainActor
final class FloatingIndicatorController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var state: DictationState = .idle
    private let configStore: ConfigStore

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func setState(_ state: DictationState, config: AppConfig) {
        self.state = state
        guard config.showFloatingIndicator else {
            close()
            return
        }
        if panel == nil {
            createPanel(config: config)
        }
        guard let panel, let label else { return }
        let style = styleForState(state)
        panel.setFrame(frameForState(state, config: config), display: true)
        panel.backgroundColor = style.background
        label.stringValue = style.text
        label.textColor = style.textColor
        panel.orderFrontRegardless()
    }

    func ensureVisible(config: AppConfig) {
        setState(state, config: config)
    }

    func close() {
        panel?.close()
        panel = nil
        label = nil
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = panel.frame.height / 2

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.frame = contentView.bounds
        label.autoresizingMask = [.width, .height]
        contentView.addSubview(label)
        panel.contentView = contentView

        self.panel = panel
        self.label = label
        setState(.idle, config: config)
    }

    private func frameForState(_ state: DictationState, config: AppConfig) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 64, height: 28)
        }
        let size: NSSize
        switch state {
        case .idle: size = NSSize(width: 52, height: 28)
        case .preparing: size = NSSize(width: 110, height: 32)
        case .recording: size = NSSize(width: 148, height: 36)
        case .transcribing: size = NSSize(width: 164, height: 36)
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

    private func styleForState(_ state: DictationState) -> (background: NSColor, text: String, textColor: NSColor) {
        switch state {
        case .idle:
            return (.colorWith(hex: 0x16171C, alpha: 0.84), "M", .white)
        case .preparing:
            return (.colorWith(hex: 0x3B4757, alpha: 0.94), "Preparing", .white)
        case .recording:
            return (.colorWith(hex: 0xD32F2F, alpha: 0.96), "Listening", .white)
        case .transcribing:
            return (.colorWith(hex: 0xD99A11, alpha: 0.96), "Transcribing", .black)
        }
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
