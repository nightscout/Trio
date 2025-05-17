import Combine
import CommonCrypto
import Foundation
import JavaScriptCore
import Swinject

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret?.nonEmpty
    }

    private enum Config {
        static let entriesPath = "/api/v1/entries/sgv.json"
        static let uploadEntriesPath = "/api/v1/entries.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let statusPath = "/api/v1/devicestatus.json"
        static let profilePath = "/api/v1/profile.json"
        static let retryCount = 1
        static let timeout: TimeInterval = 60
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()

    @Injected() private var settingsManager: SettingsManager!
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "Trio"
            var notes = "Trio connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent(Config.treatmentsPath))

        if let secret = secret {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            request.httpBody = try! JSONCoding.encoder.encode(check)
        } else {
            request.httpMethod = "GET"
        }

        return service.run(request)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchLastGlucose(sinceDate: Date? = nil) async throws -> [BloodGlucose] {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.entriesPath
        components.queryItems = [URLQueryItem(name: "count", value: "\(1600)")]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[dateString][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let glucose = try JSONCoding.decoder.decode([BloodGlucose].self, from: data)
            return glucose.map {
                var reading = $0
                reading.glucose = $0.sgv
                return reading
            }
        } catch {
            warning(.nightscout, "Glucose fetching error: \(error)")
            return []
        }
    }

    func fetchCarbs(sinceDate: Date? = nil) async throws -> [CarbsEntry] {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NightscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let carbs = try JSONCoding.decoder.decode([CarbsEntry].self, from: data)
            return carbs
        } catch {
            warning(.nightscout, "Carbs fetching error: \(error)")
            throw error
        }
    }

    func deleteCarbs(withId id: String) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        components.queryItems = [
            URLQueryItem(name: "find[id][$eq]", value: id)
        ]

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return
    }

    func deleteManualGlucose(withId id: String) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[id][$eq]", value: id)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        debugPrint("Delete successful for ID \(id)")
    }

    func deleteInsulin(withId id: String) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[id][$eq]", value: id)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchTempTargets(sinceDate: Date? = nil) async throws -> [TempTarget] {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temporary+Target"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: TempTarget.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NightscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(name: "find[duration][$exists]", value: "true")
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let tempTargets = try JSONCoding.decoder.decode([TempTarget].self, from: data)
            return tempTargets
        } catch {
            warning(.nightscout, "TempTarget fetching error: \(error)")
            throw error
        }
    }

    func uploadTreatments(_ treatments: [NightscoutTreatment]) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        guard let requestURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let encodedBody = try JSONCoding.encoder.encode(treatments)
            request.httpBody = encodedBody
//            debugPrint("Payload treatments size: \(encodedBody.count) bytes")
//            debugPrint(String(data: encodedBody, encoding: .utf8) ?? "Invalid payload")
        } catch {
            debugPrint("Error encoding payload: \(error)")
            throw error
        }
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        // Check the response status code
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

//        debugPrint("Upload successful, response data: \(String(data: data, encoding: .utf8) ?? "No data")")
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadEntriesPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        do {
            let encodedBody = try JSONCoding.encoder.encode(glucose)
            request.httpBody = encodedBody
//            debugPrint("Payload glucose size: \(encodedBody.count) bytes")
//            debugPrint(String(data: encodedBody, encoding: .utf8) ?? "Invalid payload")
        } catch {
            debugPrint("Error encoding payload: \(error)")
            throw error
        }
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        // Check the response status code
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

//        debugPrint("Upload successful, response data: \(String(data: data, encoding: .utf8) ?? "No data")")
    }

    func uploadDeviceStatus(_ status: NightscoutStatus) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.statusPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let encodedBody = try JSONCoding.encoder.encode(status)
            request.httpBody = encodedBody
//            debugPrint("Payload status size: \(encodedBody.count) bytes")
//            debugPrint(String(data: encodedBody, encoding: .utf8) ?? "Invalid payload")
        } catch {
            debugPrint("Error encoding payload: \(error)")
            throw error
        }

        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func uploadProfile(_ profile: NightscoutProfileStore) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.profilePath

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let encodedBody = try JSONCoding.encoder.encode(profile)
            request.httpBody = encodedBody
//            debugPrint("Payload profile upload size: \(encodedBody.count) bytes")
//            debugPrint(String(data: encodedBody, encoding: .utf8) ?? "Invalid payload")
        } catch {
            debugPrint("Error encoding payload: \(error)")
            throw error
        }
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
    }

    /// The delete func is needed to force re-rendering of overrides with changed durations in Nightscout main chart
    /// since just updating durations in existing entries doesn't trigger re-rendering.
    func deleteNightscoutOverride(withCreatedAt createdAt: String) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[created_at][$eq]", value: createdAt)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Config.timeout
        request.httpMethod = "DELETE"

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) {
        } else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            debug(.nightscout, "Failed to delete override with created_at: \(createdAt). HTTP status code: \(statusCode)")
            throw URLError(.badServerResponse)
        }
    }

    func uploadOverrides(_ overrides: [NightscoutExercise]) async throws {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        do {
            let encodedBody = try JSONCoding.encoder.encode(overrides)
            request.httpBody = encodedBody
//            debugPrint("Payload glucose size: \(encodedBody.count) bytes")
//            debugPrint(String(data: encodedBody, encoding: .utf8) ?? "Invalid payload")
        } catch {
            debugPrint("Error encoding payload: \(error)")
            throw error
        }
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        // Check the response status code
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

//        debugPrint("Upload successful, response data: \(String(data: data, encoding: .utf8) ?? "No data")")
    }

    func importSettings() async throws -> ScheduledNightscoutProfile {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.profilePath
        components.queryItems = [URLQueryItem(name: "count", value: "1")]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let mimeType = httpResponse.mimeType, mimeType == "application/json" else {
                throw URLError(.unsupportedURL)
            }

            let jsonDecoder = JSONCoding.decoder
            let fetchedProfileStore = try jsonDecoder.decode([FetchedNightscoutProfileStore].self, from: data)
            guard let fetchedProfile = fetchedProfileStore.first?.store["default"] else {
                throw NSError(
                    domain: "ImportError",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Can't find the default Nightscout Profile."]
                )
            }

            return fetchedProfile
        } catch {
            warning(.nightscout, "Could not fetch Nightscout Profile! Error: \(error)")
            throw error
        }
    }
}

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
