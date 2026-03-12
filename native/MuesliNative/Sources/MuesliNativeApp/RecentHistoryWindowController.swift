import AppKit
import Foundation

@MainActor
final class RecentHistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: DictationStore
    private let controller: MuesliController
    private let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    private let localTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }()
    private let localTimestampFallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
    private let utcTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let utcTimestampFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private var window: NSWindow?
    private var dictationTableView: NSTableView?
    private var meetingTableView: NSTableView?
    private var dictationRows: [DictationRecord] = []
    private var meetingRows: [MeetingRecord] = []

    private var summaryLabel: NSTextField?
    private var dictationStatsLabel: NSTextField?
    private var meetingStatsLabel: NSTextField?
    private var backendLabel: NSTextField?

    init(store: DictationStore, controller: MuesliController) {
        self.store = store
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        guard let window else { return }
        reload()
        if !window.isVisible {
            controller.noteWindowOpened()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    func reload() {
        dictationRows = (try? store.recentDictations(limit: 10)) ?? []
        meetingRows = (try? store.recentMeetings(limit: 10)) ?? []
        updateLabels()
        dictationTableView?.reloadData()
        meetingTableView?.reloadData()
    }

    func updateBackendLabel() {
        backendLabel?.stringValue = "Backend: \(controller.selectedBackend.label)"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == dictationTableView {
            return dictationRows.count
        }
        if tableView == meetingTableView {
            return meetingRows.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableColumn?.identifier.rawValue ?? "text"
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(identifier)")
        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.lineBreakMode = .byTruncatingTail
        }

        if tableView == dictationTableView {
            let item = dictationRows[row]
            textField.stringValue = dictationValue(item, column: identifier)
        } else if tableView == meetingTableView {
            let item = meetingRows[row]
            textField.stringValue = meetingValue(item, column: identifier)
        } else {
            textField.stringValue = ""
        }
        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        if tableView == dictationTableView {
            let index = tableView.selectedRow
            guard index >= 0, index < dictationRows.count else { return }
            controller.copyToClipboard(dictationRows[index].rawText)
        } else if tableView == meetingTableView {
            let index = tableView.selectedRow
            guard index >= 0, index < meetingRows.count else { return }
            controller.copyToClipboard(meetingRows[index].rawTranscript)
        }
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 140, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Muesli"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = window.contentView!

        let title = NSTextField(labelWithString: "Welcome back")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        title.alignment = .center
        title.frame = NSRect(x: 24, y: 696, width: 992, height: 32)
        content.addSubview(title)

        let summary = NSTextField(labelWithString: "")
        summary.alignment = .center
        summary.frame = NSRect(x: 24, y: 670, width: 992, height: 20)
        content.addSubview(summary)
        summaryLabel = summary

        let settingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openPreferences))
        settingsButton.frame = NSRect(x: 468, y: 632, width: 120, height: 28)
        content.addSubview(settingsButton)

        let dictationStats = NSTextField(labelWithString: "")
        dictationStats.alignment = .center
        dictationStats.frame = NSRect(x: 24, y: 594, width: 992, height: 20)
        content.addSubview(dictationStats)
        dictationStatsLabel = dictationStats

        let meetingStats = NSTextField(labelWithString: "")
        meetingStats.alignment = .center
        meetingStats.frame = NSRect(x: 24, y: 566, width: 992, height: 20)
        content.addSubview(meetingStats)
        meetingStatsLabel = meetingStats

        let backend = NSTextField(labelWithString: "")
        backend.frame = NSRect(x: 24, y: 540, width: 400, height: 18)
        backend.identifier = NSUserInterfaceItemIdentifier("backendLabel")
        content.addSubview(backend)
        backendLabel = backend

        let tabView = NSTabView(frame: NSRect(x: 24, y: 24, width: 992, height: 500))
        tabView.addTabViewItem(buildDictationsTab())
        tabView.addTabViewItem(buildMeetingsTab())
        content.addSubview(tabView)

        self.window = window
        updateLabels()
        updateBackendLabel()
    }

    private func buildDictationsTab() -> NSTabViewItem {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 980, height: 460))
        scrollView.hasVerticalScroller = true

        let table = NSTableView(frame: scrollView.bounds)
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 32
        table.usesAlternatingRowBackgroundColors = true

        addColumn("time", title: "Time", width: 160, to: table)
        addColumn("transcript", title: "Transcript", width: 610, to: table)
        addColumn("words", title: "Words", width: 90, to: table)
        addColumn("duration", title: "Duration", width: 100, to: table)

        scrollView.documentView = table
        dictationTableView = table

        let item = NSTabViewItem(identifier: "dictations")
        item.label = "Dictations"
        item.view = scrollView
        return item
    }

    private func buildMeetingsTab() -> NSTabViewItem {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 980, height: 460))
        scrollView.hasVerticalScroller = true

        let table = NSTableView(frame: scrollView.bounds)
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 32
        table.usesAlternatingRowBackgroundColors = true

        addColumn("time", title: "Start", width: 160, to: table)
        addColumn("meeting", title: "Meeting", width: 180, to: table)
        addColumn("transcript", title: "Transcript", width: 450, to: table)
        addColumn("words", title: "Words", width: 90, to: table)
        addColumn("duration", title: "Duration", width: 100, to: table)

        scrollView.documentView = table
        meetingTableView = table

        let item = NSTabViewItem(identifier: "meetings")
        item.label = "Meeting Transcripts"
        item.view = scrollView
        return item
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat, to table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        table.addTableColumn(column)
    }

    private func updateLabels() {
        let dictationStats = controller.dictationStats()
        let meetingStats = controller.meetingStats()
        summaryLabel?.stringValue =
            "Streak \(dictationStats.currentStreakDays) days    \(dictationStats.totalWords) dictation words    \(String(format: "%.1f", dictationStats.averageWPM)) WPM"
        dictationStatsLabel?.stringValue =
            "Dictation: \(dictationStats.totalSessions) sessions, \(dictationStats.totalWords) words, \(String(format: "%.1f", dictationStats.averageWordsPerSession)) words/session, longest streak \(dictationStats.longestStreakDays) days"
        meetingStatsLabel?.stringValue =
            "Meetings: \(meetingStats.totalMeetings) meetings, \(meetingStats.totalWords) words, \(String(format: "%.1f", meetingStats.averageWPM)) WPM"
    }

    private func dictationValue(_ item: DictationRecord, column: String) -> String {
        switch column {
        case "time":
            return displayTime(item.timestamp)
        case "transcript":
            return controller.truncate(item.rawText, limit: 96)
        case "words":
            return "\(item.wordCount)"
        case "duration":
            return "\(Int(item.durationSeconds.rounded()))s"
        default:
            return ""
        }
    }

    private func meetingValue(_ item: MeetingRecord, column: String) -> String {
        switch column {
        case "time":
            return displayTime(item.startTime)
        case "meeting":
            return controller.truncate(item.title, limit: 24)
        case "transcript":
            return controller.truncate(item.rawTranscript, limit: 72)
        case "words":
            return "\(item.wordCount)"
        case "duration":
            return "\(Int(item.durationSeconds.rounded()))s"
        default:
            return ""
        }
    }

    @objc private func openPreferences() {
        controller.openPreferences()
    }

    func windowWillClose(_ notification: Notification) {
        controller.noteWindowClosed()
    }

    private func displayTime(_ raw: String) -> String {
        if let date = utcTimestampFormatter.date(from: raw) ?? utcTimestampFallbackFormatter.date(from: raw) {
            return displayFormatter.string(from: date)
        }
        if let date = localTimestampFormatter.date(from: raw) ?? localTimestampFallbackFormatter.date(from: raw) {
            return displayFormatter.string(from: date)
        }
        return raw.replacingOccurrences(of: "T", with: " ").prefix(16).description
    }
}
