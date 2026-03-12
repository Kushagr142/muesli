import AppKit
import Foundation

enum PasteController {
    static func paste(text: String, runtime: RuntimePaths) {
        guard !text.isEmpty else { return }
        let process = Process()
        process.executableURL = runtime.pythonExecutable
        process.arguments = [runtime.pasteScript.path]

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            if let data = text.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } catch {
            fputs("[muesli-native] paste helper failed: \(error)\n", stderr)
        }
    }
}
