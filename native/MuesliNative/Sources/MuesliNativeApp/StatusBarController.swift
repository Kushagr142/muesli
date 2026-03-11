import AppKit
import Foundation

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let controller: MuesliController
    private let runtime: RuntimePaths
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLabel = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")

    init(controller: MuesliController, runtime: RuntimePaths) {
        self.controller = controller
        self.runtime = runtime
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        build()
    }

    func setStatus(_ text: String) {
        statusLabel.title = "Status: \(text)"
    }

    func refresh() {
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func build() {
        if let button = statusItem.button {
            if let iconURL = runtime.menuIcon, let image = NSImage(contentsOf: iconURL) {
                image.isTemplate = false
                button.image = image
            } else {
                button.title = "M"
            }
            button.toolTip = "Muesli"
        }
        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(actionItem(title: "Open Muesli", action: #selector(MuesliController.openHistoryWindow)))
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recent Dictations", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let recentRows = controller.recentDictations()
        if recentRows.isEmpty {
            let empty = NSMenuItem(title: "No dictations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for row in recentRows {
                let item = NSMenuItem(title: controller.truncate(row.rawText, limit: 54), action: #selector(MuesliController.copyRecentDictation(_:)), keyEquivalent: "")
                item.target = controller
                item.representedObject = row.rawText
                recentMenu.addItem(item)
            }
        }
        menu.setSubmenu(recentMenu, for: recentItem)
        menu.addItem(recentItem)

        let backendItem = NSMenuItem(title: "Transcription Backend", action: nil, keyEquivalent: "")
        let backendMenu = NSMenu()
        for option in BackendOption.all {
            let prefix = controller.selectedBackend == option ? "✓ " : ""
            let item = NSMenuItem(title: "\(prefix)\(option.label)", action: #selector(MuesliController.selectBackendFromMenu(_:)), keyEquivalent: "")
            item.target = controller
            item.representedObject = option.label
            backendMenu.addItem(item)
        }
        menu.setSubmenu(backendMenu, for: backendItem)
        menu.addItem(backendItem)

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(MuesliController.openPreferences)))
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit", action: #selector(MuesliController.quitApp)))
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = controller
        return item
    }
}
