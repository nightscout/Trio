import Foundation

enum LogShareAction {
    static func archive(named _: String, contents _: @escaping (URL) async throws -> Void) async throws -> URL {
        throw CocoaError(.featureUnsupported)
    }
}
