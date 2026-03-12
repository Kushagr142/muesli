import AppKit
import AVFoundation
import Foundation

@MainActor
final class MuesliController: NSObject {
    private let runtime: RuntimePaths
    private let configStore = ConfigStore()
    private let dictationStore = DictationStore()
    private let workerClient: PythonWorkerClient
    private let hotkeyMonitor = HotkeyMonitor()
    private let recorder = MicrophoneRecorder()
    private let indicator: FloatingIndicatorController

    private var statusBarController: StatusBarController?
    private var historyWindowController: RecentHistoryWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    private(set) var config: AppConfig
    private(set) var selectedBackend: BackendOption
    private var dictationStartedAt: Date?
    private var openWindowCount = 0
    private var lastExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?

    init(runtime: RuntimePaths) {
        let loadedConfig = configStore.load()
        self.runtime = runtime
        self.config = loadedConfig
        self.selectedBackend = BackendOption.all.first(where: {
            $0.backend == loadedConfig.sttBackend && $0.model == loadedConfig.sttModel
        }) ?? .whisper
        self.workerClient = PythonWorkerClient(runtime: runtime)
        self.indicator = FloatingIndicatorController(configStore: configStore)
        super.init()
    }

    func start() {
        do {
            try dictationStore.migrateIfNeeded()
            try workerClient.start()
        } catch {
            fputs("[muesli-native] startup error: \(error)\n", stderr)
        }

        hotkeyMonitor.onPrepare = { [weak self] in self?.handlePrepare() }
        hotkeyMonitor.onStart = { [weak self] in self?.handleStart() }
        hotkeyMonitor.onStop = { [weak self] in self?.handleStop() }
        hotkeyMonitor.onCancel = { [weak self] in self?.handleCancel() }
        hotkeyMonitor.start()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app != NSRunningApplication.current
            else { return }
            self?.lastExternalApp = app
        }

        statusBarController = StatusBarController(controller: self, runtime: runtime)
        preferencesWindowController = PreferencesWindowController(controller: self)
        historyWindowController = RecentHistoryWindowController(store: dictationStore, controller: self)
        refreshUI()

        workerClient.preloadBackend(option: selectedBackend) { _ in }

        if config.openDashboardOnLaunch {
            openHistoryWindow()
        }
    }

    func shutdown() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        hotkeyMonitor.stop()
        recorder.cancel()
        workerClient.stop()
        indicator.close()
    }

    func recentDictations() -> [DictationRecord] {
        (try? dictationStore.recentDictations(limit: 10)) ?? []
    }

    func recentMeetings() -> [MeetingRecord] {
        (try? dictationStore.recentMeetings(limit: 10)) ?? []
    }

    func dictationStats() -> DictationStats {
        (try? dictationStore.dictationStats()) ?? DictationStats(
            totalWords: 0,
            totalSessions: 0,
            averageWordsPerSession: 0,
            averageWPM: 0,
            currentStreakDays: 0,
            longestStreakDays: 0
        )
    }

    func meetingStats() -> MeetingStats {
        (try? dictationStore.meetingStats()) ?? MeetingStats(totalWords: 0, totalMeetings: 0, averageWPM: 0)
    }

    func truncate(_ text: String, limit: Int) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func refreshIndicatorVisibility() {
        if config.showFloatingIndicator {
            indicator.ensureVisible(config: config)
        } else {
            indicator.close()
        }
    }

    func refreshUI() {
        statusBarController?.setStatus("Idle")
        statusBarController?.refresh()
        historyWindowController?.updateBackendLabel()
        historyWindowController?.reload()
        preferencesWindowController?.refresh()
        refreshIndicatorVisibility()
    }

    func updateConfig(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        configStore.save(config)
        selectedBackend = BackendOption.all.first(where: {
            $0.backend == config.sttBackend && $0.model == config.sttModel
        }) ?? .whisper
        statusBarController?.refresh()
        historyWindowController?.updateBackendLabel()
        if config.showFloatingIndicator {
            indicator.ensureVisible(config: config)
        } else {
            indicator.close()
        }
    }

    func selectBackend(_ option: BackendOption) {
        updateConfig {
            $0.sttBackend = option.backend
            $0.sttModel = option.model
        }
        workerClient.preloadBackend(option: option) { [weak self] _ in
            self?.statusBarController?.refresh()
        }
    }

    @objc func openHistoryWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.historyWindowController?.show()
        }
    }

    @objc func openPreferences() {
        DispatchQueue.main.async { [weak self] in
            self?.preferencesWindowController?.show()
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func copyRecentDictation(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            copyToClipboard(text)
        }
    }

    @objc func copyRecentMeeting(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            copyToClipboard(text)
        }
    }

    @objc func selectBackendFromMenu(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String,
              let option = BackendOption.all.first(where: { $0.label == label }) else { return }
        selectBackend(option)
    }

    func clearDictationHistory() {
        try? dictationStore.clearDictations()
        statusBarController?.refresh()
        historyWindowController?.reload()
    }

    func clearMeetingHistory() {
        try? dictationStore.clearMeetings()
        statusBarController?.refresh()
        historyWindowController?.reload()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func noteWindowOpened() {
        openWindowCount += 1
        if NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func noteWindowClosed() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func setState(_ state: DictationState) {
        let status: String
        switch state {
        case .idle: status = "Idle"
        case .preparing: status = "Preparing"
        case .recording: status = "Recording"
        case .transcribing: status = "Transcribing"
        }
        statusBarController?.setStatus(status)
        indicator.setState(state, config: config)
    }

    private func handlePrepare() {
        fputs("[muesli-native] prepare\n", stderr)
        do {
            try recorder.prepare()
            setState(.preparing)
        } catch {
            fputs("[muesli-native] recorder prepare failed: \(error)\n", stderr)
            setState(.idle)
        }
    }

    private func handleStart() {
        fputs("[muesli-native] recording start\n", stderr)
        do {
            try recorder.start()
            dictationStartedAt = Date()
            setState(.recording)
        } catch {
            fputs("[muesli-native] recorder start failed: \(error)\n", stderr)
            setState(.idle)
        }
    }

    private func handleCancel() {
        fputs("[muesli-native] cancel\n", stderr)
        recorder.cancel()
        dictationStartedAt = nil
        setState(.idle)
    }

    private func handleStop() {
        fputs("[muesli-native] stop\n", stderr)
        let startedAt = dictationStartedAt ?? Date()
        dictationStartedAt = nil
        guard let wavURL = recorder.stop() else {
            fputs("[muesli-native] stop without wav\n", stderr)
            setState(.idle)
            return
        }
        let duration = max(Date().timeIntervalSince(startedAt), 0)
        if duration < 0.3 {
            fputs("[muesli-native] discarded short recording\n", stderr)
            try? FileManager.default.removeItem(at: wavURL)
            setState(.idle)
            return
        }

        setState(.transcribing)
        workerClient.transcribeFile(wavURL: wavURL, option: selectedBackend) { [weak self] result in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: wavURL)
                self.setState(.idle)
            }

            switch result {
            case .success(let payload):
                let text = (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                try? self.dictationStore.insertDictation(
                    text: text,
                    durationSeconds: duration,
                    startedAt: startedAt,
                    endedAt: Date()
                )
                self.statusBarController?.refresh()
                self.historyWindowController?.reload()
                PasteController.paste(text: text, runtime: self.runtime)
            case .failure(let error):
                fputs("[muesli-native] transcription failed: \(error)\n", stderr)
            }
        }
    }
}
