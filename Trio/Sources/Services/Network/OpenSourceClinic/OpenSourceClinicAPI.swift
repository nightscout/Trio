import Foundation

class OpenSourceClinicAPI {
    private let session = URLSession.shared
    private let encoder = JSONCoding.encoder
    private let decoder = JSONDecoder()

    enum APIError: LocalizedError {
        case invalidURL
        case unauthorized
        case badStatusCode(Int)
        case encodingFailed(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .unauthorized: return "Invalid API token"
            case let .badStatusCode(code): return "Server error (\(code))"
            case let .encodingFailed(error): return "Encoding failed: \(error.localizedDescription)"
            case let .networkError(error): return error.localizedDescription
            }
        }
    }

    // MARK: - Sync (alles in één)

    func sync(baseURL: URL, token: String, payload: TrioSyncPayload) async throws {
        let data = try encoder.encode(payload)
        let request = try buildRequest(
            baseURL: baseURL,
            path: "/v1/trio/sync",
            token: token,
            body: data
        )
        try await execute(request)
    }

    // MARK: - Glucose

    func uploadGlucose(baseURL: URL, token: String, units: String, entries: [GlucoseEntry]) async throws {
        let body: [String: Any] = [
            "units": units,
            "entries": entries.map { [
                "date": $0.date,
                "value": $0.value,
                "direction": $0.direction ?? "None"
            ] as [String: Any] }
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let request = try buildRequest(
            baseURL: baseURL,
            path: "/v1/trio/glucose",
            token: token,
            body: data
        )
        try await execute(request)
    }

    // MARK: - Preferences

    func uploadPreferences(baseURL: URL, token: String, preferences: Preferences) async throws {
        let data = try encoder.encode(preferences)
        let request = try buildRequest(
            baseURL: baseURL,
            path: "/v1/trio/preferences",
            token: token,
            body: data
        )
        try await execute(request)
    }

    // MARK: - Therapy Profile

    func uploadTherapyProfile(baseURL: URL, token: String, profile: TherapyProfilePayload) async throws {
        let data = try encoder.encode(profile)
        let request = try buildRequest(
            baseURL: baseURL,
            path: "/v1/trio/therapy-profile",
            token: token,
            body: data
        )
        try await execute(request)
    }

    // MARK: - Private

    private func buildRequest(baseURL: URL, path: String, token: String, body: Data) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30
        return request
    }

    private func execute(_ request: URLRequest) async throws {
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            switch httpResponse.statusCode {
            case 200 ..< 300: return
            case 401: throw APIError.unauthorized
            default: throw APIError.badStatusCode(httpResponse.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Payload types

struct TrioSyncPayload: Encodable {
    let device: DeviceInfo
    let timestamp: String
    let glucose: GlucosePayload?
    let therapyProfile: TherapyProfilePayload?
    let preferences: Preferences?
    let treatments: TreatmentsPayload?
    let deviceStatus: DeviceStatusPayload?
    let autotune: AutotunePayload?

    enum CodingKeys: String, CodingKey {
        case device, timestamp, glucose, preferences, treatments, autotune
        case therapyProfile = "therapy_profile"
        case deviceStatus = "device_status"
    }
}

struct DeviceInfo: Encodable {
    let app: String
    let version: String
    let os: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case app, version, os
        case osVersion = "os_version"
    }
}

struct GlucosePayload: Encodable {
    let units: String
    let entries: [GlucoseEntry]
}

struct GlucoseEntry: Encodable {
    let date: TimeInterval
    let value: Decimal
    let direction: String?
}

struct TherapyProfilePayload: Encodable {
    let dia: Decimal
    let basal: [TimeRate]
    let isf: [TimeValue]
    let carbRatio: [TimeValue]
    let targets: [TimeTarget]
    let maxBolus: Decimal
    let maxBasal: Decimal

    enum CodingKeys: String, CodingKey {
        case dia, basal, isf, targets
        case carbRatio = "carb_ratio"
        case maxBolus = "max_bolus"
        case maxBasal = "max_basal"
    }
}

struct TimeRate: Encodable {
    let time: String
    let rate: Decimal
}

struct TimeValue: Encodable {
    let time: String
    let value: Decimal
}

struct TimeTarget: Encodable {
    let time: String
    let low: Decimal
    let high: Decimal
}

struct TreatmentsPayload: Encodable {
    let entries: [TreatmentEntry]
}

struct TreatmentEntry: Encodable {
    let type: String
    let date: TimeInterval
    let insulin: Decimal?
    let carbs: Decimal?
    let duration: Decimal?
    let rate: Decimal?
}

struct DeviceStatusPayload: Encodable {
    let iob: IOBPayload?
    let cob: Decimal?
    let tdd: Decimal?
}

struct IOBPayload: Encodable {
    let iob: Decimal
    let basaliob: Decimal
    let bolusiob: Decimal
    let activity: Decimal
}

struct AutotunePayload: Encodable {
    let enabled: Bool
    let onlyBasals: Bool
    let recommended: AutotuneRecommended?

    enum CodingKeys: String, CodingKey {
        case enabled
        case onlyBasals = "only_basals"
        case recommended
    }
}

struct AutotuneRecommended: Encodable {
    let carbRatio: Decimal?
    let isf: Decimal?
    let basal: [BasalRate]?

    enum CodingKeys: String, CodingKey {
        case carbRatio = "carb_ratio"
        case isf, basal
    }
}

struct BasalRate: Encodable {
    let start: String
    let minutes: Int
    let rate: Decimal
}
