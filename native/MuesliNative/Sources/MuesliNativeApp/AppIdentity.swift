import Foundation

enum AppIdentity {
    private static let defaultName = "Muesli"

    static var bundleName: String {
        stringValue(for: "CFBundleName") ?? defaultName
    }

    static var displayName: String {
        stringValue(for: "CFBundleDisplayName") ?? bundleName
    }

    static var supportDirectoryName: String {
        stringValue(for: "MuesliSupportDirectoryName") ?? displayName
    }

    static var supportDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    private static func stringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
