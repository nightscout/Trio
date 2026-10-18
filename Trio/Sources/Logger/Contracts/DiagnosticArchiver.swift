import Foundation

enum DiagnosticArchiver {
    static func zip(_ directory: URL, name: String) throws -> URL {
        let fileManager = FileManager.default
        let destination = fileManager.temporaryDirectory.appendingPathComponent("\(name).zip")
        var coordinationError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: destination.path])
        }
        return destination
    }
}
