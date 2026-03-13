import CoreML
import Foundation
import WhisperKit

struct SpeechSegment: Sendable {
    let start: Double
    let end: Double
    let text: String
}

struct SpeechTranscriptionResult: Sendable {
    let text: String
    let segments: [SpeechSegment]
}

struct TranscriptionExecution: Sendable {
    let runtime: TranscriptionRuntimeOption
    let result: SpeechTranscriptionResult
}

enum TranscriptionRuntimeError: LocalizedError {
    case unsupportedNativeBackend(String)
    case nativeUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedNativeBackend(let backend):
            return "The native runtime does not support the \(backend) backend yet."
        case .nativeUnavailable:
            return "The native transcription runtime is not available."
        }
    }
}

actor WhisperKitSpeechBackend {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    func preload(option: BackendOption) async throws {
        _ = try await ensureLoaded(option: option)
    }

    func transcribeFile(at url: URL, option: BackendOption) async throws -> SpeechTranscriptionResult {
        let kit = try await ensureLoaded(option: option)
        let results = try await kit.transcribe(
            audioPath: url.path,
            decodeOptions: DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: nil,
                temperature: 0.0,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: true
            )
        )

        let firstResult = results.first
        let text = firstResult?.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let segments = firstResult?.segments.compactMap { segment -> SpeechSegment? in
            let text = segment.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SpeechSegment(start: Double(segment.start), end: Double(segment.end), text: text)
        } ?? []

        return SpeechTranscriptionResult(text: text, segments: segments)
    }

    private func ensureLoaded(option: BackendOption) async throws -> WhisperKit {
        guard let nativeModel = option.nativeModel else {
            throw TranscriptionRuntimeError.unsupportedNativeBackend(option.label)
        }
        if let whisperKit, loadedModel == nativeModel {
            return whisperKit
        }

        if let whisperKit {
            await whisperKit.unloadModels()
        }

        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuAndGPU
        )
        let config = WhisperKitConfig(
            model: nativeModel,
            modelRepo: "argmaxinc/whisperkit-coreml",
            computeOptions: computeOptions,
            prewarm: true,
            download: true
        )
        let whisperKit = try await WhisperKit(config)
        self.whisperKit = whisperKit
        self.loadedModel = nativeModel
        return whisperKit
    }
}

final class LegacyPythonSpeechBackend {
    private let workerClient: PythonWorkerClient

    init?(runtime: RuntimePaths) {
        let fileManager = FileManager.default
        guard
            !runtime.pythonExecutable.path.isEmpty,
            !runtime.workerScript.path.isEmpty,
            fileManager.isExecutableFile(atPath: runtime.pythonExecutable.path),
            fileManager.fileExists(atPath: runtime.workerScript.path)
        else {
            return nil
        }
        self.workerClient = PythonWorkerClient(runtime: runtime)
    }

    func preload(option: BackendOption) async throws {
        _ = try await workerClient.preloadBackendAsync(option: option)
    }

    func transcribeFile(at url: URL, option: BackendOption) async throws -> SpeechTranscriptionResult {
        let payload = try await workerClient.transcribeFileAsync(wavURL: url, option: option)
        let text = (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SpeechTranscriptionResult(text: text, segments: [])
    }

    func stop() {
        workerClient.stop()
    }
}

actor TranscriptionCoordinator {
    private let nativeBackend = WhisperKitSpeechBackend()
    private let legacyBackend: LegacyPythonSpeechBackend?

    init(runtime: RuntimePaths) {
        self.legacyBackend = LegacyPythonSpeechBackend(runtime: runtime)
    }

    func preload(config: AppConfig, option: BackendOption) async -> TranscriptionRuntimeOption {
        do {
            let runtime = try await preferredRuntime(config: config, option: option)
            return runtime
        } catch {
            return .legacyPython
        }
    }

    func transcribeDictation(at url: URL, config: AppConfig, option: BackendOption) async throws -> TranscriptionExecution {
        let runtime = try await preferredRuntime(config: config, option: option)
        if runtime == .native {
            return TranscriptionExecution(runtime: .native, result: try await nativeBackend.transcribeFile(at: url, option: option))
        }
        if runtime == .legacyPython {
            guard let legacyBackend else {
                throw TranscriptionRuntimeError.nativeUnavailable
            }
            return TranscriptionExecution(runtime: .legacyPython, result: try await legacyBackend.transcribeFile(at: url, option: option))
        }
        throw TranscriptionRuntimeError.nativeUnavailable
    }

    func transcribeMeeting(at url: URL, option: BackendOption) async throws -> SpeechTranscriptionResult {
        try await nativeBackend.transcribeFile(at: url, option: option)
    }

    func shutdown() {
        legacyBackend?.stop()
    }

    private func preferredRuntime(config: AppConfig, option: BackendOption) async throws -> TranscriptionRuntimeOption {
        let requested = TranscriptionRuntimeOption.all.first(where: { $0.id == config.transcriptionRuntime }) ?? .native
        if requested == .legacyPython {
            if let legacyBackend {
                try await legacyBackend.preload(option: option)
                return .legacyPython
            }
            try await nativeBackend.preload(option: option)
            return .native
        }

        do {
            try await nativeBackend.preload(option: option)
            return .native
        } catch {
            guard let legacyBackend else {
                throw error
            }
            try await legacyBackend.preload(option: option)
            return .legacyPython
        }
    }
}
