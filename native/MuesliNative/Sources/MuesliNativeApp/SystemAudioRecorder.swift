import Foundation

final class SystemAudioRecorder {
    private let toolURL: URL?
    private var process: Process?
    private var outputURL: URL?

    init(toolURL: URL?) {
        self.toolURL = toolURL
    }

    var isRecording: Bool {
        process?.isRunning == true
    }

    func start() throws {
        guard process == nil else { return }
        guard let toolURL else {
            return
        }

        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-system-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")

        let process = Process()
        process.executableURL = toolURL
        process.arguments = [outputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        self.process = process
        self.outputURL = outputURL
    }

    func stop() -> URL? {
        defer {
            process = nil
        }
        guard let process else {
            return nil
        }
        if process.isRunning {
            process.interrupt()
            process.waitUntilExit()
        }
        return outputURL
    }
}
