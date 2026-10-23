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
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                devVersion: bundle.appDevVersion ?? "",
                branch: BuildDetails.shared.trioBranch,
                commit: BuildDetails.shared.trioCommitSHA,
                deviceModel: deviceModel,
                osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                pumpModel: pump,
                cgmModel: cgm
            )
        }

        private static var deviceModel: String {
            var info = utsname()
            uname(&info)
            let machine = withUnsafeBytes(of: &info.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return machine.isEmpty ? "unknown" : machine
        }
    }

    struct Attachment: Equatable {
        var filename: String
        var contentType: String
        var data: Data
    }

    var title: String?
    var description: String
    var contact: Contact?
    var context: Context
    var attachments: [Attachment]
}

enum ReportSubmitError: Error, Equatable {
    case tooLarge
    case unsupportedImage
    case rateLimited
    case server(status: Int)
    case invalidResponse
    case logsUnavailable
    case network(String)

    var canRetry: Bool {
        switch self {
        case let .server(status): return status >= 500
        case .logsUnavailable,
             .network: return true
        case .invalidResponse,
             .rateLimited,
             .tooLarge,
             .unsupportedImage: return false
        }
    }

    var message: String {
        switch self {
        case .tooLarge:
            return String(localized: "The report is too large. Try fewer or smaller screenshots.")
        case .unsupportedImage:
            return String(localized: "One of the screenshots couldn't be read. Try choosing it again or leave it out.")
        case .rateLimited:
            return String(localized: "Too many reports were sent from this network recently. Please try again later.")
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

    static func from(status: Int) -> ReportSubmitError {
        switch status {
        case 413: return .tooLarge
        case 415: return .unsupportedImage
        case 429: return .rateLimited
        default: return .server(status: status)
        }
    }
}

protocol ReportSubmitting {
    func submit(_ report: ProblemReport) async throws -> String
}

struct HTTPReportSubmitter: ReportSubmitting {
    let endpoint: URL
    var client: String?
    var session: URLSession = .shared

    func submit(_ report: ProblemReport) async throws -> String {
        let boundary = "TrioReport-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try Self.body(for: report, boundary: boundary, client: client)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch {
            throw ReportSubmitError.network(error.localizedDescription)
        }
        guard let response = response as? HTTPURLResponse else { throw ReportSubmitError.invalidResponse }
        return try Self.reportID(status: response.statusCode, data: data)
    }

    static func reportID(status: Int, data: Data) throws -> String {
        guard (200 ..< 300).contains(status) else { throw ReportSubmitError.from(status: status) }
        struct Reply: Decodable { let id: String }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), !reply.id.isEmpty else {
            throw ReportSubmitError.invalidResponse
        }
        return reply.id
    }

    static func body(for report: ProblemReport, boundary: String, client: String?) throws -> Data {
        struct Contact: Encodable {
            let name, email, discord, github: String?
        }
        struct Payload: Encodable {
            let title: String?
            let description: String
            let contact: Contact?
            let context: ProblemReport.Context
        }
        func value(_ string: String) -> String? { string.isEmpty ? nil : string }
        let contact = report.contact.map {
            Contact(name: value($0.name), email: value($0.email), discord: value($0.discord), github: value($0.github))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(Payload(
            title: report.title,
            description: report.description,
            contact: contact,
            context: report.context
        ))

        var body = Data()
        func part(_ name: String, filename: String? = nil, contentType: String? = nil, _ data: Data) {
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            if let filename {
                header += "; filename=\"\(filename.filter { $0 != "\"" && !$0.isNewline })\""
            }
            header += "\r\n"
            if let contentType {
                header += "Content-Type: \(contentType)\r\n"
            }
            body.append(Data("\(header)\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }

        if let client, !client.isEmpty {
            part("client", Data(client.utf8))
        }
        part("report", contentType: "application/json", json)
        for attachment in report.attachments {
            part("attachment", filename: attachment.filename, contentType: attachment.contentType, attachment.data)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

struct MockReportSubmitter: ReportSubmitting {
    func submit(_: ProblemReport) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "TRIO-DEBUG-" + String(UUID().uuidString.prefix(6))
    }
}

enum ReportEndpoint {
    #if DEBUG
        static let allowsMock = true
    #else
        static let allowsMock = false
    #endif

    static func submitter(bundle: Bundle = .main) -> ReportSubmitting? {
        submitter(
            endpoint: bundle.object(forInfoDictionaryKey: "TrioReportEndpoint") as? String,
            client: bundle.object(forInfoDictionaryKey: "TrioReportClient") as? String,
            allowsMock: allowsMock
        )
    }

    static func submitter(endpoint: String?, client: String?, allowsMock: Bool) -> ReportSubmitting? {
        let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host?.isEmpty == false {
            let client = client?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HTTPReportSubmitter(endpoint: url, client: client?.isEmpty == false ? client : nil)
        }
        return allowsMock ? MockReportSubmitter() : nil
    }
}
