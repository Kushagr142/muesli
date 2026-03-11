import Foundation

struct BackendOption: Equatable {
    let backend: String
    let model: String
    let label: String

    static let whisper = BackendOption(
        backend: "whisper",
        model: "mlx-community/whisper-small.en-mlx",
        label: "Whisper Small"
    )

    static let qwen = BackendOption(
        backend: "qwen",
        model: "mlx-community/Qwen3-ASR-0.6B-4bit",
        label: "Qwen3 ASR 0.6B 4-bit"
    )

    static let all: [BackendOption] = [.whisper, .qwen]
}

struct AppConfig: Codable {
    var hotkey: String = "left_command_hold"
    var sttBackend: String = BackendOption.whisper.backend
    var sttModel: String = BackendOption.whisper.model
    var whisperModel: String = BackendOption.whisper.model
    var idleTimeout: Double = 120
    var autoRecordMeetings: Bool = false
    var launchAtLogin: Bool = false
    var openDashboardOnLaunch: Bool = true
    var showFloatingIndicator: Bool = true
    var dashboardWindowFrame: WindowFrame? = nil
    var indicatorOrigin: CGPointCodable? = nil
}

struct WindowFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct CGPointCodable: Codable {
    let x: Double
    let y: Double
}

struct DictationRecord: Identifiable {
    let id: Int64
    let timestamp: String
    let durationSeconds: Double
    let rawText: String
    let appContext: String
    let wordCount: Int
}

enum DictationState: String {
    case idle
    case preparing
    case recording
    case transcribing
}
