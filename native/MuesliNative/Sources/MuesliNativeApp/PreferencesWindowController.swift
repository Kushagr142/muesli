import AppKit
import Foundation

@MainActor
final class PreferencesWindowController: NSObject {
    private let controller: MuesliController
    private var window: NSWindow?
    private var launchCheckbox: NSButton?
    private var openOnLaunchCheckbox: NSButton?
    private var indicatorCheckbox: NSButton?
    private var backendPopup: NSPopUpButton?

    init(controller: MuesliController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        let config = controller.config
        launchCheckbox?.state = config.launchAtLogin ? .on : .off
        openOnLaunchCheckbox?.state = config.openDashboardOnLaunch ? .on : .off
        indicatorCheckbox?.state = config.showFloatingIndicator ? .on : .off
        backendPopup?.selectItem(withTitle: controller.selectedBackend.label)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 220, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Muesli Settings"
        let content = window.contentView!

        let launch = checkbox(title: "Launch at login", action: #selector(toggleLaunchAtLogin))
        launch.frame.origin = NSPoint(x: 24, y: 220)
        content.addSubview(launch)
        self.launchCheckbox = launch

        let openOnLaunch = checkbox(title: "Open history window on launch", action: #selector(toggleOpenOnLaunch))
        openOnLaunch.frame.origin = NSPoint(x: 24, y: 188)
        content.addSubview(openOnLaunch)
        self.openOnLaunchCheckbox = openOnLaunch

        let indicator = checkbox(title: "Show floating indicator", action: #selector(toggleIndicator))
        indicator.frame.origin = NSPoint(x: 24, y: 156)
        content.addSubview(indicator)
        self.indicatorCheckbox = indicator

        let backendLabel = NSTextField(labelWithString: "Transcription backend")
        backendLabel.frame = NSRect(x: 24, y: 116, width: 180, height: 20)
        content.addSubview(backendLabel)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: 84, width: 250, height: 28), pullsDown: false)
        popup.addItems(withTitles: BackendOption.all.map(\.label))
        popup.target = self
        popup.action = #selector(selectBackend)
        content.addSubview(popup)
        self.backendPopup = popup

        let clearButton = NSButton(title: "Clear dictation history", target: self, action: #selector(clearHistory))
        clearButton.frame = NSRect(x: 24, y: 34, width: 180, height: 28)
        content.addSubview(clearButton)

        self.window = window
    }

    private func checkbox(title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        return button
    }

    @objc private func toggleLaunchAtLogin() {
        controller.updateConfig { $0.launchAtLogin = self.launchCheckbox?.state == .on }
    }

    @objc private func toggleOpenOnLaunch() {
        controller.updateConfig { $0.openDashboardOnLaunch = self.openOnLaunchCheckbox?.state == .on }
    }

    @objc private func toggleIndicator() {
        controller.updateConfig { $0.showFloatingIndicator = self.indicatorCheckbox?.state == .on }
        controller.refreshIndicatorVisibility()
    }

    @objc private func selectBackend() {
        guard let title = backendPopup?.titleOfSelectedItem,
              let option = BackendOption.all.first(where: { $0.label == title }) else { return }
        controller.selectBackend(option)
    }

    @objc private func clearHistory() {
        controller.clearDictationHistory()
    }
}
