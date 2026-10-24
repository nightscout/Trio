import CryptoKit
import DeviceCheck
import Foundation

struct ProblemReport {
    struct Contact: Codable, Equatable {
        var name = ""
        var email = ""
        var discord = ""
        var github = ""

        // Nil when every field is blank
        var trimmed: Contact? {
            let contact = Contact(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                discord: discord.trimmingCharacters(in: .whitespacesAndNewlines),
                github: github.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return contact == Contact() ? nil : contact
        }
    }

    struct Context: Encodable, Equatable {
        var appVersion: String
        var buildNumber: String
        var devVersion: String
        var branch: String
        var commit: String
        var deviceModel: String
        var osVersion: String
        var pumpModel: String?
        var cgmModel: String?

        static func current(pump: String?, cgm: String?) -> Context {
            let bundle = Bundle.main
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return Context(
                appVersion: known(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
                buildNumber: known(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
                devVersion: known(bundle.appDevVersion),
                branch: known(BuildDetails.shared.trioBranch),
                commit: known(BuildDetails.shared.trioCommitSHA),
                deviceModel: known(deviceModel),
                osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                pumpModel: pump,
                cgmModel: cgm
            )
        }

        static let unknown = "unknown"

        // The server rejects empty context fields
        static func known(_ value: String?) -> String {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return unknown }
            return value
        }

        private static var deviceModel: String {
            var info = utsname()
            uname(&info)
            return withUnsafeBytes(of: &info.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
    }

    struct Attachment: Equatable {
        var filename: String
        var contentType: String
        var data: Data

        var sha256: String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    var title: String?
    var description: String
    var contact: Contact?
    var context: Context
    var attachments: [Attachment]
}

enum ReportSubmitError: Error, Equatable {
    case tooLarge
    case logsTooLarge
    case unsupportedImage
    case rateLimited
    case appNotAllowed
    case attestationFailed
    case server(status: Int)
    case invalidResponse
    case logsUnavailable
    case network(String)

    var canRetry: Bool {
        switch self {
        case let .server(status): return status >= 500
        case .attestationFailed,
             .logsUnavailable,
             .network: return true
        case .appNotAllowed,
             .invalidResponse,
             .logsTooLarge,
             .rateLimited,
             .tooLarge,
             .unsupportedImage: return false
        }
    }

    var message: String {
        switch self {
        case .tooLarge:
            return String(localized: "The report is too large. Try fewer or smaller screenshots.")
        case .logsTooLarge:
            return String(
                localized: "Your logs are too large to send. Turn off Attach My Logs and share them on Discord or Facebook instead."
            )
        case .unsupportedImage:
            return String(localized: "One of the screenshots couldn't be read. Try choosing it again or leave it out.")
        case .rateLimited:
            return String(localized: "You've sent several reports today. Please try again tomorrow.")
        case .appNotAllowed:
            return String(
                localized: "This build of Trio can't send reports. Please share your logs on Discord or Facebook instead."
            )
        case .attestationFailed:
            return String(
                localized: "Trio couldn't confirm with Apple that this copy of the app is genuine. Please try again later."
            )
        case let .server(status):
            return String(localized: "The Trio team's server couldn't take the report right now (error \(status)).")
        case .invalidResponse:
            return String(localized: "The Trio team's server sent an answer the app doesn't understand.")
        case .logsUnavailable:
            return String(localized: "Your logs couldn't be prepared. Try again, or turn off Attach My Logs.")
        case let .network(message):
            return message
        }
    }

    static func from(status: Int, data: Data? = nil) -> ReportSubmitError {
        let code = data.flatMap(HTTPReportSubmitter.errorCode)
        switch (code, status) {
        case (_, 429),
             ("rate_limited", _): return .rateLimited
        case (_, 403),
             ("app_not_allowed", _): return .appNotAllowed
        case (_, 413),
             ("too_large", _): return .tooLarge
        case (_, 415),
             ("unsupported_type", _): return .unsupportedImage
        default: return .server(status: status)
        }
    }

    static func from(_ error: Error) -> ReportSubmitError {
        switch error {
        case let error as ReportSubmitError:
            return error
        case let error as AppAttestClient.AttestError:
            switch error {
            case .forbidden,
                 .unknownAppID,
                 .unsupportedDevice: return .appNotAllowed
            case .assertionFailed,
                 .attestationFailed,
                 .keyGenerationFailed: return .attestationFailed
            case let .clientError(status),
                 let .serverError(status): return .from(status: status)
            case .invalidRequestURL,
                 .malformedResponse,
                 .transportError: return .invalidResponse
            }
        default:
            return .network(error.localizedDescription)
        }
    }
}

enum ReportLimits {
    static let maxImages = 8
    static let maxImageBytes = 5_000_000
    static let maxLogsBytes = 15_000_000
    static let maxTotalBytes = 40_000_000

    static func check(_ attachments: [ProblemReport.Attachment]) throws {
        let images = attachments.filter { ["image/png", "image/jpeg"].contains($0.contentType) }
        let logs = attachments.filter { $0.contentType == "application/zip" }
        guard images.count + logs.count == attachments.count else { throw ReportSubmitError.unsupportedImage }
        guard logs.count <= 1, logs.allSatisfy({ $0.data.count <= maxLogsBytes }) else {
            throw ReportSubmitError.logsTooLarge
        }
        guard images.count <= maxImages,
              images.allSatisfy({ $0.data.count <= maxImageBytes }),
              attachments.reduce(0, { $0 + $1.data.count }) <= maxTotalBytes
        else { throw ReportSubmitError.tooLarge }
    }
}

protocol ReportSubmitting {
    // Returns the report ID once the server has accepted every file
    func submit(_ report: ProblemReport, progress: @escaping (Double) -> Void) async throws -> String
    func delete(id: String) async throws
}

extension ReportSubmitting {
    // The draft stays until the report is complete, so a failed send can be retried
    func send(
        _ report: ProblemReport,
        storage: KeyValueStorage = UserDefaults.standard,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        let id = try await submit(report, progress: progress)
        SentReports.add(id, in: storage)
        ReportDraft.clear(in: storage)
        return id
    }

    func withdraw(id: String, storage: KeyValueStorage = UserDefaults.standard) async throws {
        try await delete(id: id)
        SentReports.remove(id, in: storage)
    }
}

struct HTTPReportSubmitter: ReportSubmitting {
    struct Upload: Decodable {
        let name: String
        let url: URL
        let headers: [String: String]
    }

    struct Created: Decodable {
        let id: String
        let uploads: [Upload]
    }

    let attest: AppAttestClient
    var session: URLSession = .shared
    var uploadAttempts = 3
    var retryDelay: UInt64 = 1_000_000_000

    func submit(_ report: ProblemReport, progress: @escaping (Double) -> Void) async throws -> String {
        do {
            try ReportLimits.check(report.attachments)
            let (data, _) = try await signed("POST", path: "v1/reports", body: Self.body(for: report))
            guard let created = try? JSONDecoder().decode(Created.self, from: data), !created.id.isEmpty else {
                throw ReportSubmitError.invalidResponse
            }
            try await upload(report.attachments, to: created.uploads, progress: progress)
            _ = try await signed("POST", path: "v1/reports/\(created.id)/complete", body: Data("{}".utf8))
            info(.ui, "Problem report sent with \(report.attachments.count) attachments")
            return created.id
        } catch {
            throw ReportSubmitError.from(error)
        }
    }

    func delete(id: String) async throws {
        do {
            _ = try await signed("DELETE", path: "v1/reports/\(id)", body: Data())
            info(.ui, "Problem report deleted")
        } catch ReportSubmitError.server(status: 404) {
            debug(.ui, "Problem report was already gone on the server")
        } catch {
            throw ReportSubmitError.from(error)
        }
    }

    // A rejected assertion is retried once with a fresh challenge; only an unknown key gets a new one,
    // because reports belong to the key that created them
    func signed(_ method: String, path: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        var retriedAssertion = false
        var reattested = false
        var retriedTimeout = false
        while true {
            try await attest.registerIfNeeded()
            let assertion = try await attest.assertion(for: body)

            var request = URLRequest(url: attest.baseURL.appendingPathComponent(path))
            request.httpMethod = method
            request.timeoutInterval = attest.timeout
            if !body.isEmpty {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            request.setValue(assertion.keyID, forHTTPHeaderField: "X-Trio-Key-Id")
            request.setValue(assertion.assertion, forHTTPHeaderField: "X-Trio-Assertion")
            request.setValue(assertion.challenge, forHTTPHeaderField: "X-Trio-Challenge")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError where error.code == .timedOut && !retriedTimeout {
                warning(.ui, "Support server timed out, retrying with a new challenge", error: error)
                retriedTimeout = true
                continue
            }
            guard let http = response as? HTTPURLResponse else { throw ReportSubmitError.invalidResponse }
            if http.statusCode == 401 {
                let unknownKey = Self.errorCode(in: data) == "invalid_key"
                if !unknownKey, !retriedAssertion {
                    warning(.ui, "Support server rejected the App Attest assertion, retrying with a new challenge")
                    retriedAssertion = true
                    continue
                }
                if !reattested {
                    warning(.ui, "Support server rejected the App Attest key, registering a new one")
                    attest.invalidateRegistration()
                    reattested = true
                    continue
                }
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw ReportSubmitError.from(status: http.statusCode, data: data)
            }
            return (data, http)
        }
    }

    static func errorCode(in data: Data) -> String? {
        struct Reply: Decodable { let code: String }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.code
    }

    private func upload(
        _ attachments: [ProblemReport.Attachment],
        to uploads: [Upload],
        progress: @escaping (Double) -> Void
    ) async throws {
        let total = max(attachments.reduce(0) { $0 + $1.data.count }, 1)
        var done = 0
        progress(0)
        for attachment in attachments {
            guard let upload = uploads.first(where: { $0.name == attachment.filename }) else {
                throw ReportSubmitError.invalidResponse
            }
            let sentBefore = done
            try await put(attachment.data, to: upload) { sent in
                progress(Double(sentBefore + Int(sent)) / Double(total))
            }
            done += attachment.data.count
            progress(Double(done) / Double(total))
        }
    }

    private func put(_ data: Data, to upload: Upload, progress: @escaping (Int64) -> Void) async throws {
        var request = URLRequest(url: upload.url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        for (field, value) in upload.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        var attempt = 1
        while true {
            do {
                let (_, response) = try await session.upload(for: request, from: data, delegate: UploadProgress(progress))
                guard let http = response as? HTTPURLResponse else { throw ReportSubmitError.invalidResponse }
                guard (200 ..< 300).contains(http.statusCode) else {
                    throw ReportSubmitError.server(status: http.statusCode)
                }
                return
            } catch {
                let failure = ReportSubmitError.from(error)
                guard failure.canRetry, attempt < uploadAttempts else { throw failure }
                warning(.ui, "Upload of a report attachment failed, attempt \(attempt) of \(uploadAttempts)", error: error)
                try await Task.sleep(nanoseconds: retryDelay * UInt64(attempt))
                attempt += 1
            }
        }
    }

    static func body(for report: ProblemReport) throws -> Data {
        struct Contact: Encodable {
            let name, email, discord, github: String?
        }
        struct Manifest: Encodable {
            let name: String
            let contentType: String
            let size: Int
            let sha256: String
        }
        struct Payload: Encodable {
            let title: String?
            let description: String
            let contact: Contact?
            let context: ProblemReport.Context
            let attachments: [Manifest]
        }
        func value(_ string: String) -> String? { string.isEmpty ? nil : string }
        let contact = report.contact.map {
            Contact(name: value($0.name), email: value($0.email), discord: value($0.discord), github: value($0.github))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Payload(
            title: report.title,
            description: report.description,
            contact: contact,
            context: report.context,
            attachments: report.attachments.map {
                Manifest(name: $0.filename, contentType: $0.contentType, size: $0.data.count, sha256: $0.sha256)
            }
        ))
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    let update: (Int64) -> Void

    init(_ update: @escaping (Int64) -> Void) {
        self.update = update
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend _: Int64
    ) {
        update(totalBytesSent)
    }
}

struct MockReportSubmitter: ReportSubmitting {
    func submit(_: ProblemReport, progress: @escaping (Double) -> Void) async throws -> String {
        for step in 1 ... 4 {
            try await Task.sleep(nanoseconds: 250_000_000)
            progress(Double(step) / 4)
        }
        return "TR-DBUG-" + String(UUID().uuidString.prefix(4))
    }

    func delete(id _: String) async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
    }
}

extension AppAttestClient {
    static func reports(baseURL: URL, namespace: String, keychain: Keychain, service: AppAttestService) -> AppAttestClient {
        AppAttestClient(
            baseURL: baseURL,
            challengePath: "v1/attest/challenge",
            registerPath: "v1/attest/register",
            namespace: namespace,
            keychain: keychain,
            category: .ui,
            challengeBody: Data("{}".utf8),
            timeout: 60,
            timeoutRetries: 1,
            service: service
        )
    }
}

enum ReportEndpoint {
    static let production = "https://support.triodocs.org"
    static let dev = "https://support-dev.triodocs.org"
    // DEBUG only: "-TrioReportDev YES" uses the dev server, "-TrioReportBaseURL <url>" any other server
    static let devKey = "TrioReportDev"
    static let baseURLKey = "TrioReportBaseURL"

    #if DEBUG
        static let isDebug = true
    #else
        static let isDebug = false
    #endif

    static func submitter(
        keychain: Keychain,
        service: AppAttestService = DCAppAttestService.shared,
        defaults: UserDefaults = .standard
    ) -> ReportSubmitting? {
        let baseURL = isDebug ? defaults.string(forKey: baseURLKey) : nil
        let useDev = isDebug && (defaults.bool(forKey: devKey) || baseURL != nil)
        return submitter(attestSupported: service.isSupported, allowsMock: isDebug, useDev: useDev, baseURL: baseURL) { url in
            HTTPReportSubmitter(attest: .reports(
                baseURL: url,
                namespace: useDev ? "ReportAttest.dev" : "ReportAttest",
                keychain: keychain,
                service: service
            ))
        }
    }

    static func submitter(
        attestSupported: Bool,
        allowsMock: Bool,
        useDev: Bool,
        baseURL: String? = nil,
        make: (URL) -> ReportSubmitting
    ) -> ReportSubmitting? {
        guard attestSupported, let url = URL(string: baseURL ?? (useDev ? dev : production)) else {
            return allowsMock ? MockReportSubmitter() : nil
        }
        return make(url)
    }
}
