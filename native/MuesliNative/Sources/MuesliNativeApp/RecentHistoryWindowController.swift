import AppKit
import Foundation

@MainActor
final class RecentHistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: DictationStore
    private let controller: MuesliController
    private var window: NSWindow?
    private var tableView: NSTableView?
    private var rows: [DictationRecord] = []

    init(store: DictationStore, controller: MuesliController) {
        self.store = store
        self.controller = controller
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        rows = (try? store.recentDictations(limit: 10)) ?? []
        tableView?.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let item = rows[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "time":
            value = item.timestamp.replacingOccurrences(of: "T", with: " ").prefix(16).description
        default:
            value = controller.truncate(item.rawText, limit: 72)
        }

        let identifier = NSUserInterfaceItemIdentifier("cell-\(tableColumn?.identifier.rawValue ?? "text")")
        let textField: NSTextField
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            textField = existing
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingTail
        }
        textField.stringValue = value
        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = tableView?.selectedRow ?? -1
        guard index >= 0, index < rows.count else { return }
        PasteController.paste(text: rows[index].rawText)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 180, width: 760, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Muesli"
        window.delegate = self

        let content = window.contentView!
        let title = NSTextField(labelWithString: "Recent Dictations")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.frame = NSRect(x: 24, y: 376, width: 300, height: 28)
        content.addSubview(title)

        let backend = NSTextField(labelWithString: "Backend")
        backend.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        backend.frame = NSRect(x: 24, y: 352, width: 400, height: 18)
        backend.identifier = NSUserInterfaceItemIdentifier("backendLabel")
        content.addSubview(backend)

        let settingsButton = NSButton(title: "Settings", target: self, action: #selector(openPreferences))
        settingsButton.frame = NSRect(x: 640, y: 368, width: 96, height: 28)
        content.addSubview(settingsButton)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 24, width: 712, height: 312))
        scrollView.hasVerticalScroller = true

        let table = NSTableView(frame: scrollView.bounds)
        table.delegate = self
        table.dataSource = self
        table.headerView = nil
        table.rowHeight = 32

        let timeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        timeColumn.width = 160
        let textColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        textColumn.width = 540
        table.addTableColumn(timeColumn)
        table.addTableColumn(textColumn)
        scrollView.documentView = table
        content.addSubview(scrollView)

        self.tableView = table
        self.window = window
        updateBackendLabel()
    }

    func updateBackendLabel() {
        guard let label = window?.contentView?.subviews.first(where: { $0.identifier?.rawValue == "backendLabel" }) as? NSTextField else {
            return
        }
        label.stringValue = "Backend: \(controller.selectedBackend.label)"
    }

    @objc private func openPreferences() {
        controller.openPreferences()
    }
}
