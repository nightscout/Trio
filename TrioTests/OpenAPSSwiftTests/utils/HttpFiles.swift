import Foundation
@testable import Trio

/// Helper struct to download files from localhost via HTTP. Must have a HTTP server
/// running on port 8123 that supports listing files and downloading files
///
/// This struct is only useful during testing as it is missing a number of error checks
struct HttpFiles {
    static func listFiles() async throws -> [String] {
        let url = URL(string: "http://localhost:8123/list")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let files = try JSONDecoder().decode([String].self, from: data)
        return files
    }

    static func downloadFile(at: String) async throws -> AlgorithmComparison {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let dataUrl = URL(string: "http://localhost:8123\(at)")!
        let (data, _) = try await URLSession.shared.data(from: dataUrl)
        return try decoder.decode(AlgorithmComparison.self, from: data)
    }
}
