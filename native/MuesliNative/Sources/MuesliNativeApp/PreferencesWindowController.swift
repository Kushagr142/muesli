import AppKit
import Foundation

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let controller: MuesliController
    private var window: NSWindow?
    private var launchCheckbox: NSButton?
    private var openOnLaunchCheckbox: NSButton?
    private var indicatorCheckbox: NSButton?
    private var runtimePopup: NSPopUpButton?
    private var backendPopup: NSPopUpButton?
    private var meetingBackendPopup: NSPopUpButton?

    init(controller: MuesliController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        refresh()
        guard let window else { return }
        if !window.isVisible {
            controller.noteWindowOpened()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    func refresh() {
        let config = controller.config
        launchCheckbox?.state = config.launchAtLogin ? .on : .off
        openOnLaunchCheckbox?.state = config.openDashboardOnLaunch ? .on : .off
        indicatorCheckbox?.state = config.showFloatingIndicator ? .on : .off
        runtimePopup?.selectItem(withTitle: controller.selectedRuntime.label)
        backendPopup?.selectItem(withTitle: controller.selectedBackend.label)
        meetingBackendPopup?.selectItem(withTitle: controller.selectedMeetingSummaryBackend.label)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 220, width: 420, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppIdentity.displayName) Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!

        let launch = checkbox(title: "Launch at login", action: #selector(toggleLaunchAtLogin))
        launch.frame.origin = NSPoint(x: 24, y: 324)
        content.addSubview(launch)
        self.launchCheckbox = launch

        let openOnLaunch = checkbox(title: "Open history window on launch", action: #selector(toggleOpenOnLaunch))
        openOnLaunch.frame.origin = NSPoint(x: 24, y: 292)
        content.addSubview(openOnLaunch)
        self.openOnLaunchCheckbox = openOnLaunch

        let indicator = checkbox(title: "Show floating indicator", action: #selector(toggleIndicator))
        indicator.frame.origin = NSPoint(x: 24, y: 260)
        content.addSubview(indicator)
        self.indicatorCheckbox = indicator

        let runtimeLabel = NSTextField(labelWithString: "Runtime")
        runtimeLabel.frame = NSRect(x: 24, y: 220, width: 180, height: 20)
        content.addSubview(runtimeLabel)

        let runtimePopup = NSPopUpButton(frame: NSRect(x: 24, y: 188, width: 250, height: 28), pullsDown: false)
        runtimePopup.addItems(withTitles: TranscriptionRuntimeOption.all.map(\.label))
        runtimePopup.target = self
        runtimePopup.action = #selector(selectRuntime)
        content.addSubview(runtimePopup)
        self.runtimePopup = runtimePopup

        let backendLabel = NSTextField(labelWithString: "Transcription backend")
        backendLabel.frame = NSRect(x: 24, y: 150, width: 180, height: 20)
        content.addSubview(backendLabel)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: 118, width: 250, height: 28), pullsDown: false)
        popup.addItems(withTitles: BackendOption.all.map(\.label))
        popup.target = self
        popup.action = #selector(selectBackend)
        content.addSubview(popup)
        self.backendPopup = popup

        let meetingBackendLabel = NSTextField(labelWithString: "Meeting summary backend")
        meetingBackendLabel.frame = NSRect(x: 24, y: 80, width: 180, height: 20)
        content.addSubview(meetingBackendLabel)

        let meetingPopup = NSPopUpButton(frame: NSRect(x: 24, y: 48, width: 250, height: 28), pullsDown: false)
        meetingPopup.addItems(withTitles: MeetingSummaryBackendOption.all.map(\.label))
        meetingPopup.target = self
        meetingPopup.action = #selector(selectMeetingBackend)
        content.addSubview(meetingPopup)
        self.meetingBackendPopup = meetingPopup

        let clearButton = NSButton(title: "Clear dictation history", target: self, action: #selector(clearHistory))
        clearButton.frame = NSRect(x: 24, y: 12, width: 180, height: 28)
        content.addSubview(clearButton)

        let clearMeetingsButton = NSButton(title: "Clear meeting history", target: self, action: #selector(clearMeetingHistory))
        clearMeetingsButton.frame = NSRect(x: 210, y: 12, width: 180, height: 28)
        content.addSubview(clearMeetingsButton)

        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        controller.noteWindowClosed()
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

    @objc private func selectRuntime() {
        guard let title = runtimePopup?.titleOfSelectedItem,
              let option = TranscriptionRuntimeOption.all.first(where: { $0.label == title }) else { return }
        controller.selectRuntime(option)
    }

    @objc private func selectMeetingBackend() {
        guard let title = meetingBackendPopup?.titleOfSelectedItem,
              let option = MeetingSummaryBackendOption.all.first(where: { $0.label == title }) else { return }
        controller.selectMeetingSummaryBackend(option)
    }

    @objc private func clearHistory() {
        controller.clearDictationHistory()
    }

    @objc private func clearMeetingHistory() {
        controller.clearMeetingHistory()
    }
}
