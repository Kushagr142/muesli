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

struct MeetingSummaryBackendOption: Equatable {
    let backend: String
    let label: String

    static let openAI = MeetingSummaryBackendOption(
        backend: "openai",
        label: "OpenAI"
    )

    static let openRouter = MeetingSummaryBackendOption(
        backend: "openrouter",
        label: "OpenRouter"
    )

    static let all: [MeetingSummaryBackendOption] = [.openAI, .openRouter]
}

struct AppConfig: Codable {
    var hotkey: String = "left_command_hold"
    var sttBackend: String = BackendOption.whisper.backend
    var sttModel: String = BackendOption.whisper.model
    var meetingSummaryBackend: String = MeetingSummaryBackendOption.openAI.backend
    var whisperModel: String = BackendOption.whisper.model
    var idleTimeout: Double = 120
    var autoRecordMeetings: Bool = false
    var launchAtLogin: Bool = false
    var openDashboardOnLaunch: Bool = true
    var showFloatingIndicator: Bool = true
    var dashboardWindowFrame: WindowFrame? = nil
    var indicatorOrigin: CGPointCodable? = nil

    enum CodingKeys: String, CodingKey {
        case hotkey
        case sttBackend = "stt_backend"
        case sttModel = "stt_model"
        case meetingSummaryBackend = "meeting_summary_backend"
        case whisperModel = "whisper_model"
        case idleTimeout = "idle_timeout"
        case autoRecordMeetings = "auto_record_meetings"
        case launchAtLogin = "launch_at_login"
        case openDashboardOnLaunch = "open_dashboard_on_launch"
        case showFloatingIndicator = "show_floating_indicator"
        case dashboardWindowFrame = "dashboard_window_frame"
        case indicatorOrigin = "indicator_origin"
    }
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

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            let x = try arrayContainer.decode(Double.self)
            let y = try arrayContainer.decode(Double.self)
            self.init(x: x, y: y)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    enum CodingKeys: String, CodingKey {
        case x
        case y
    }
}

struct DictationRecord: Identifiable {
    let id: Int64
    let timestamp: String
    let durationSeconds: Double
    let rawText: String
    let appContext: String
    let wordCount: Int
}

struct MeetingRecord: Identifiable {
    let id: Int64
    let title: String
    let startTime: String
    let durationSeconds: Double
    let rawTranscript: String
    let formattedNotes: String
    let wordCount: Int
}

struct DictationStats {
    let totalWords: Int
    let totalSessions: Int
    let averageWordsPerSession: Double
    let averageWPM: Double
    let currentStreakDays: Int
    let longestStreakDays: Int
}

struct MeetingStats {
    let totalWords: Int
    let totalMeetings: Int
    let averageWPM: Double
}

enum DictationState: String {
    case idle
    case preparing
    case recording
    case transcribing
}
