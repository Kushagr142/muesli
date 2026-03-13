import Foundation

extension PythonWorkerClient {
    func preloadBackendAsync(option: BackendOption) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            preloadBackend(option: option) { result in
                continuation.resume(with: result)
            }
        }
    }

    func transcribeFileAsync(wavURL: URL, option: BackendOption) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            transcribeFile(wavURL: wavURL, option: option) { result in
                continuation.resume(with: result)
            }
        }
    }
}
