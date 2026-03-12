import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MuesliController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let runtime = try RuntimePaths.resolve()
            if let appIcon = runtime.appIcon, let image = NSImage(contentsOf: appIcon) {
                NSApplication.shared.applicationIconImage = image
            }
            let controller = MuesliController(runtime: runtime)
            self.controller = controller
            controller.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Muesli failed to start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
