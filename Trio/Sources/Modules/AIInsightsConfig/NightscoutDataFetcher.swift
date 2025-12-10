import Foundation

/// Fetches comprehensive historical data from Nightscout for AI analysis
final class NightscoutDataFetcher {
    private let keychain: Keychain

    init(keychain: Keychain) {
        self.keychain = keychain
    }

    struct FetchedData {
        let glucoseReadings: [GlucoseReading]
        let treatments: [Treatment]
        let fetchDate: Date
        let daysOfData: Int

        struct GlucoseReading {
            let date: Date
            let value: Int
            let direction: String?
        }

        struct Treatment {
            let date: Date
            let type: TreatmentType
            let amount: Double
            let notes: String?

            enum TreatmentType {
                case carbs
                case bolus
                case tempBasal(duration: Int)
                case correction
                case announcement
            }
        }
    }

    /// Check if Nightscout is configured and available
    var isNightscoutConfigured: Bool {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              !urlString.isEmpty,
              keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) != nil
        else {
            return false
        }
        return true
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    /// Fetch all glucose readings for the specified number of days
    func fetchGlucose(days: Int) async throws -> [FetchedData.GlucoseReading] {
        guard let api = nightscoutAPI else {
            throw FetchError.notConfigured
        }

        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch glucose readings since the target date
        let readings = try await api.fetchLastGlucose(sinceDate: sinceDate)

        // Convert to our format
        let converted = readings.map { bg -> FetchedData.GlucoseReading in
            FetchedData.GlucoseReading(
                date: bg.dateString,
                value: bg.glucose ?? bg.sgv ?? 0,
                direction: bg.direction?.rawValue
            )
        }

        return converted.sorted { $0.date < $1.date }
    }

    /// Fetch all treatments (carbs, boluses) for the specified number of days
    func fetchTreatments(days: Int) async throws -> [FetchedData.Treatment] {
        guard let api = nightscoutAPI else {
            throw FetchError.notConfigured
        }

        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch carbs
        let carbs = try await api.fetchCarbs(sinceDate: sinceDate)
        let carbTreatments = carbs.map { entry -> FetchedData.Treatment in
            FetchedData.Treatment(
                date: entry.createdAt,
                type: .carbs,
                amount: Double(truncating: entry.carbs as NSNumber),
                notes: entry.note
            )
        }

        // Fetch boluses via treatments endpoint
        let boluses = try await fetchBoluses(since: sinceDate)

        var allTreatments = carbTreatments + boluses
        allTreatments.sort { $0.date < $1.date }

        return allTreatments
    }

    private func fetchBoluses(since: Date) async throws -> [FetchedData.Treatment] {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let baseURL = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return []
        }

        // Query the treatments endpoint for bolus events
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/api/v1/treatments.json"
        components.queryItems = [
            URLQueryItem(name: "find[insulin][$exists]", value: "true"),
            URLQueryItem(name: "find[created_at][$gt]", value: Formatter.iso8601withFractionalSeconds.string(from: since)),
            URLQueryItem(name: "count", value: "5000")
        ]

        guard let url = components.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.addValue(secret.sha1Hashed, forHTTPHeaderField: "api-secret")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let treatments = try JSONDecoder().decode([NSTreatment].self, from: data)

            return treatments.compactMap { treatment -> FetchedData.Treatment? in
                guard let dateStr = treatment.createdAt,
                      let date = Formatter.iso8601withFractionalSeconds.date(from: dateStr),
                      let insulin = treatment.insulin, insulin > 0
                else { return nil }

                let type: FetchedData.Treatment.TreatmentType = treatment.eventType == "Correction Bolus" ? .correction : .bolus
                return FetchedData.Treatment(
                    date: date,
                    type: type,
                    amount: insulin,
                    notes: treatment.notes
                )
            }
        } catch {
            // Return empty if fetch fails, don't block entire analysis
            return []
        }
    }

    /// Fetch comprehensive data for AI analysis
    func fetchComprehensiveData(days: Int) async throws -> FetchedData {
        async let glucoseTask = fetchGlucose(days: days)
        async let treatmentsTask = fetchTreatments(days: days)

        let (glucose, treatments) = try await (glucoseTask, treatmentsTask)

        return FetchedData(
            glucoseReadings: glucose,
            treatments: treatments,
            fetchDate: Date(),
            daysOfData: days
        )
    }

    enum FetchError: LocalizedError {
        case notConfigured
        case networkError(Error)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Nightscout is not configured. Please set up Nightscout in Settings."
            case let .networkError(error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Nightscout"
            }
        }
    }
}

// MARK: - Helper Codable Types

private struct NSTreatment: Codable {
    let createdAt: String?
    let eventType: String?
    let insulin: Double?
    let carbs: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case eventType
        case insulin
        case carbs
        case notes
    }
}

// MARK: - String Extension for SHA1

private extension String {
    var sha1Hashed: String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

import CommonCrypto
