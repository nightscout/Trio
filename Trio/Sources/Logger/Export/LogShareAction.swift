import Foundation
import UIKit

enum LogShareAction {
    @MainActor private final class BackgroundTask {
        private var identifier: UIBackgroundTaskIdentifier = .invalid

        init(name: String) {
            identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                MainActor.assumeIsolated { self?.end() }
            }
        }

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }

    static func archive(named name: String, contents: @escaping (URL) async throws -> Void) async throws -> URL {
        let backgroundTask = await BackgroundTask(name: name)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // The zip's top-level folder takes the content directory's name
        let directory = root.appendingPathComponent(name, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try await contents(directory)
            let archive = try DiagnosticArchiver.zip(directory, name: name)
            try? fileManager.removeItem(at: root)
            await backgroundTask.end()
            return archive
        } catch {
            try? fileManager.removeItem(at: root)
            await backgroundTask.end()
            throw error
        }
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
