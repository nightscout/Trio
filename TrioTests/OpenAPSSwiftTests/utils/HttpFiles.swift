import Foundation
@testable import Trio

/// Helper struct to download files from localhost via HTTP. Must have a HTTP server
/// running on port 8123 that supports listing files and downloading files.
///
/// You can set two ReplayTests variables `HTTP_FILES_OFFSET` and `HTTP_FILES_LENGTH`
/// to implement paging
///
/// This struct is only useful during testing as it is missing a number of error checks
struct HttpFiles {
    static func listFiles() async throws -> [String] {
        let url = URL(string: "http://localhost:8123/list")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let allFiles = try JSONDecoder().decode([String].self, from: data)

        let files: [String]
        if let offset = ReplayTests.filesOffset, let length = ReplayTests.filesLength
        {
            // Both variables exist and are valid integers
            let endIndex = min(offset + length, allFiles.count)
            let startIndex = min(offset, allFiles.count)
            files = Array(allFiles[startIndex ..< endIndex])
        } else {
            files = allFiles
        }

        if files.count > 5000 {
            fatalError("too many files: \(files.count) \(ProcessInfo.processInfo.environment)")
        }

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
