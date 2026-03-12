import Foundation

struct RuntimePaths {
    let repoRoot: URL
    let pythonExecutable: URL
    let workerScript: URL
    let pasteScript: URL
    let menuIcon: URL?
    let appIcon: URL?
    let bundlePath: URL?

    static func resolve() throws -> RuntimePaths {
        let fileManager = FileManager.default

        if let bundleResource = Bundle.main.resourceURL {
            let runtimeURL = bundleResource.appendingPathComponent("runtime.json")
            if fileManager.fileExists(atPath: runtimeURL.path) {
                let data = try Data(contentsOf: runtimeURL)
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]
                let repoRoot = URL(fileURLWithPath: payload?["repo_root"] ?? "")
                let pythonExecutable = URL(fileURLWithPath: payload?["python_executable"] ?? "")
                let workerScript = bundleResource.appendingPathComponent("worker.py")
                return RuntimePaths(
                    repoRoot: repoRoot,
                    pythonExecutable: pythonExecutable,
                    workerScript: workerScript,
                    pasteScript: bundleResource.appendingPathComponent("paste_text.py"),
                    menuIcon: bundleResource.appendingPathComponent("menu_m_template.png"),
                    appIcon: bundleResource.appendingPathComponent("muesli.icns"),
                    bundlePath: Bundle.main.bundleURL
                )
            }
        }

        var searchURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            let candidate = searchURL.appendingPathComponent("bridge/worker.py")
            if fileManager.fileExists(atPath: candidate.path) {
                return RuntimePaths(
                    repoRoot: searchURL,
                    pythonExecutable: searchURL.appendingPathComponent(".venv/bin/python"),
                    workerScript: candidate,
                    pasteScript: searchURL.appendingPathComponent("bridge/paste_text.py"),
                    menuIcon: searchURL.appendingPathComponent("assets/menu_m_template.png"),
                    appIcon: searchURL.appendingPathComponent("assets/muesli.icns"),
                    bundlePath: nil
                )
            }
            searchURL.deleteLastPathComponent()
        }

        throw NSError(domain: "MuesliRuntime", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not locate repo root or bundled runtime metadata.",
        ])
    }
}
