import Foundation
import UIKit

/// At a high level, this module stores arrays of `AlgorithmComparison` objects in a
/// Google Cloud Storage (GCS) bucket. We use these arrays to confirm that the swift and js
/// implementations of oref produce the same results.
///
/// The basic flow is that the GCS bucket is private, so there is a server that we use to
/// get a signed URL to PUT this data in the bucket.
///
/// To analyze this data, we have some scripts that load this data into a sqlite3 database
/// where we run some basic statistics.
///
/// To keep the overhead of this library small we batch results and store them in a local
/// file system file, and we do all operations async by having the caller log new results
/// using a `Task`, and since this is an Actor it runs in a background thread.
///
/// Note: This Actor is temporary -- once the port is complete we will remove it
/// https://github.com/nightscout/Trio-dev/issues/293

actor JsSwiftOrefComparisonLogger {
    // MARK: - API Models for getting signed URLs

    struct SignedURLRequest: Codable {
        let project: String
        let deviceId: String
        let appVersion: String
        let function: OrefFunction
        let createdAt: Date
    }

    struct SignedURLResponse: Codable {
        let url: String
        let expiresAt: Double
    }

    // MARK: - Exceptions from the logger

    enum LoggerError: Error {
        case fileOperationFailed
        case encodingFailed
        case decodingFailed
        case timezoneError

        case invalidSignedUrlResponse
        case signedUrlGenerationFailed
        case signedUrlNetworkError(statusCode: Int)

        case uploadNetworkError(statusCode: Int)
    }

    // MARK: - Logger implementation

    private let minBatchSize = 16
    private let maxStoredEntries = 4096
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isUploading = false

    // server settings for getting a signed Google Cloud Storage URL
    // that we can PUT to
    private let baseUrlString = "https://trio-oref-logs.uc.r.appspot.com"
    private let project = "trio-oref-validation"

    private let storageUrl: URL

    init() throws {
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970

        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LoggerError.fileOperationFailed
        }

        self.storageUrl = documentsPath.appendingPathComponent("swift_js_oref_compare.json")

        if !fileManager.fileExists(atPath: storageUrl.path) {
            try "[]".write(to: storageUrl, atomically: true, encoding: .utf8)
        }
    }

    private func readComparisons() throws -> [AlgorithmComparison] {
        let data = try Data(contentsOf: storageUrl)
        do {
            return try decoder.decode([AlgorithmComparison].self, from: data)
        } catch DecodingError.keyNotFound {
            // this can happen when we change the AlgorithmComparison
            // struct, we can just drop the values that are cached and try again
            try "[]".write(to: storageUrl, atomically: true, encoding: .utf8)
            let data = try Data(contentsOf: storageUrl)
            return try decoder.decode([AlgorithmComparison].self, from: data)
        } catch {
            throw error
        }
    }

    private func writeComparisons(_ comparisons: [AlgorithmComparison]) throws {
        let data = try encoder.encode(comparisons)
        try data.write(to: storageUrl, options: .atomicWrite)
    }

    func logComparison(comparison: AlgorithmComparison) async throws {
        var comparisons = try readComparisons()
        comparisons.append(comparison)
        if comparisons.count > maxStoredEntries {
            comparisons.removeFirst(comparisons.count - maxStoredEntries)
        }

        try writeComparisons(comparisons)

        // upload when we have enough entries and avoid uploading duplicates
        if comparisons.count >= minBatchSize, !isUploading {
            isUploading = true
            do {
                try await uploadCurrentBatch()
                isUploading = false
            } catch {
                isUploading = false
                throw error
            }
        }
    }

    // We use the vendor ID to identify devices because it is something
    // that people can reset if they want to, thus is Apple's recommended
    // privacy-friendly way to group results by a device.
    private func getSignedURL(for function: OrefFunction, createdAt: Date) async throws -> URL {
        let request = await SignedURLRequest(
            project: project,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            function: function,
            createdAt: createdAt
        )

        guard let baseURL = URL(string: baseUrlString) else {
            throw LoggerError.signedUrlGenerationFailed
        }

        let signedURLEndpoint = baseURL.appendingPathComponent("v1/signed-url")
        var urlRequest = URLRequest(url: signedURLEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw LoggerError.signedUrlNetworkError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let signedURLResponse = try decoder.decode(SignedURLResponse.self, from: data)
        guard let uploadURL = URL(string: signedURLResponse.url) else {
            throw LoggerError.invalidSignedUrlResponse
        }

        return uploadURL
    }

    private func uploadCurrentBatch() async throws {
        let comparisons = try readComparisons()
        guard comparisons.count >= minBatchSize else { return }

        guard let utcTimeZone = TimeZone(identifier: "UTC") else {
            throw LoggerError.timezoneError
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone

        // First, group by UTC date
        let dateGroupedComparisons = Dictionary(grouping: comparisons) { comparison in
            calendar.startOfDay(for: comparison.createdAt)
        }

        // Then for each date, group by function
        for (date, dateComparisons) in dateGroupedComparisons {
            let functionGroupedComparisons = Dictionary(grouping: dateComparisons) { $0.function }

            for (function, functionComparisons) in functionGroupedComparisons {
                let comparisonsToUpload = Array(functionComparisons.prefix(min(functionComparisons.count, maxStoredEntries)))
                let uploadedIds = Set(comparisonsToUpload.map(\.id))

                // Get signed URL for this date and function combination
                let url = try await getSignedURL(for: function, createdAt: date)
                try await uploadBatch(comparisonsToUpload, to: url)

                // Important: Even though we're using Actors, they give up
                // the lock when you call await which could change our set
                // of comparisons and create an atomicity violation. Thus
                // we need to re-read the comparisons from disk and only remove
                // the ones we actually uploaded.
                var updatedComparisons = try readComparisons()
                updatedComparisons.removeAll(where: { uploadedIds.contains($0.id) })
                try writeComparisons(updatedComparisons)
            }
        }
    }

    private func uploadBatch(_ comparisons: [AlgorithmComparison], to url: URL) async throws {
        let data = try encoder.encode(comparisons)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw LoggerError.uploadNetworkError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
