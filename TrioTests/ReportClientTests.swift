import CryptoKit
import Foundation
import Testing

@testable import Trio

private final class StubURLProtocol: URLProtocol {
    struct Request {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
        let timeout: TimeInterval

        var path: String { url.path }
    }

    static var handler: ((Request) -> (Int, Data))?
    static var requests: [Request] = []
    private static let lock = NSLock()

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let recorded = Request(
            method: request.httpMethod ?? "GET",
            url: request.url ?? URL(fileURLWithPath: "/"),
            headers: request.allHTTPHeaderFields ?? [:],
            body: body,
            timeout: request.timeoutInterval
        )
        Self.lock.lock()
        Self.requests.append(recorded)
        let handler = Self.handler
        Self.lock.unlock()

        // A negative status fails with that URLError code
        let (status, data) = handler?(recorded) ?? (500, Data())
        guard status >= 0 else {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let response = HTTPURLResponse(url: recorded.url, statusCode: status, httpVersion: nil, headerFields: nil)
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FakeAttestService: AppAttestService {
    var isSupported = true
    var generatedKeys = 0
    var attested: [(keyID: String, hash: Data)] = []
    var asserted: [(keyID: String, hash: Data)] = []

    func generateKey() async throws -> String {
        generatedKeys += 1
        return "synthetic-key-\(generatedKeys)"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attested.append((keyId, clientDataHash))
        return Data("synthetic-attestation".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        asserted.append((keyId, clientDataHash))
        return Data("synthetic-assertion-\(asserted.count)".utf8)
    }
}

@Suite("Report Client Tests", .serialized) final class ReportClientTests {
    private static let base = URL(string: "https://support.example.test")!
    private static let appID = "ABCDE12345.org.example.trio"
    private static let uploadBase = "https://bucket.example.test/reports/TR-TEST-0001"

    private let keychain = BaseKeychain(serviceName: "ReportClientTests-\(UUID().uuidString)", synchronizable: false)
    private let suite = "ReportClientTests-\(UUID().uuidString)"
    private let storage: UserDefaults
    private let service = FakeAttestService()
    private let session: URLSession
    private var challenges = 0

    init() throws {
        storage = try #require(UserDefaults(suiteName: suite))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.requests = []
        StubURLProtocol.handler = nil
    }

    deinit {
        keychain.removeAllKeys()
        storage.removePersistentDomain(forName: suite)
        StubURLProtocol.handler = nil
    }

    private var attest: AppAttestClient {
        var client = AppAttestClient.reports(baseURL: Self.base, namespace: "ReportAttest", keychain: keychain, service: service)
        client.session = session
        client.appID = { Self.appID }
        return client
    }

    private var submitter: HTTPReportSubmitter {
        HTTPReportSubmitter(attest: attest, session: session, uploadAttempts: 3, retryDelay: 0)
    }

    private var requests: [StubURLProtocol.Request] { StubURLProtocol.requests }

    private static let context = ProblemReport.Context(
        appVersion: "1.0.0",
        buildNumber: "1",
        devVersion: "1.0.0.1",
        branch: "dev",
        commit: "abc1234",
        deviceModel: "iPhone99,9",
        osVersion: "27.0.0",
        pumpModel: "Example Pump",
        cgmModel: nil
    )

    private static let screenshot = ProblemReport.Attachment(
        filename: "screenshot-1.png",
        contentType: "image/png",
        data: Data("abc".utf8)
    )
    private static let logs = ProblemReport.Attachment(
        filename: "logs.zip",
        contentType: "application/zip",
        data: Data([1, 2, 3, 4])
    )

    private static func report(_ attachments: [ProblemReport.Attachment] = [screenshot, logs]) -> ProblemReport {
        ProblemReport(
            title: "Synthetic title",
            description: "Synthetic description",
            contact: nil,
            context: context,
            attachments: attachments
        )
    }

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func uploadHeaders(_ attachment: ProblemReport.Attachment) -> [String: String] {
        [
            "Content-Type": attachment.contentType,
            "Content-Length": "\(attachment.data.count)",
            "x-amz-checksum-sha256": Data(SHA256.hash(data: attachment.data)).base64EncodedString()
        ]
    }

    private static let created = json([
        "id": "TR-TEST-0001",
        "uploads": [screenshot, logs].map {
            ["name": $0.filename, "url": "\(uploadBase)/\($0.filename)?X-Amz-Signature=synthetic", "headers": uploadHeaders($0)]
        },
        "expiresAt": "2026-01-01T00:15:00Z"
    ])

    // A working server; `override` can answer a request first
    private func serve(_ override: @escaping (StubURLProtocol.Request) -> (Int, Data)? = { _ in nil }) {
        StubURLProtocol.handler = { [unowned self] request in
            if let answer = override(request) { return answer }
            switch (request.method, request.path) {
            case ("POST", "/v1/attest/challenge"):
                challenges += 1
                return (200, Self.json(["challenge": "synthetic-challenge-\(challenges)"]))
            case ("POST", "/v1/attest/register"):
                return (201, Self.json(["keyId": "synthetic"]))
            case ("POST", "/v1/reports"):
                return (201, Self.created)
            case ("PUT", _):
                return (200, Data())
            case ("POST", "/v1/reports/TR-TEST-0001/complete"):
                return (200, Self.json(["id": "TR-TEST-0001"]))
            case ("DELETE", "/v1/reports/TR-TEST-0001"):
                return (204, Data())
            default:
                return (404, Self.json(["error": "Not found.", "code": "not_found"]))
            }
        }
    }

    private func steps() -> [String] {
        requests.map { "\($0.method) \($0.path)" }
    }

    @Test("Manifest lists each file with its size and checksum") func manifest() throws {
        let body = try Self.object(HTTPReportSubmitter.body(for: Self.report()))
        #expect(body["title"] as? String == "Synthetic title")
        #expect(body["description"] as? String == "Synthetic description")
        #expect(body["contact"] == nil)
        let context = try #require(body["context"] as? [String: Any])
        #expect(context["deviceModel"] as? String == "iPhone99,9")
        #expect(context["pumpModel"] as? String == "Example Pump")
        #expect(context["cgmModel"] == nil)

        let attachments = try #require(body["attachments"] as? [[String: Any]])
        #expect(attachments.count == 2)
        #expect(attachments[0]["name"] as? String == "screenshot-1.png")
        #expect(attachments[0]["contentType"] as? String == "image/png")
        #expect(attachments[0]["size"] as? Int == 3)
        #expect(attachments[0]["sha256"] as? String == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(attachments[1]["name"] as? String == "logs.zip")
        #expect(attachments[1]["size"] as? Int == 4)
    }

    @Test("A report is created, uploaded and completed with signed requests") func fullSend() async throws {
        serve()
        var progress: [Double] = []
        let id = try await submitter.submit(Self.report()) { progress.append($0) }

        #expect(id == "TR-TEST-0001")
        #expect(steps() == [
            "POST /v1/attest/challenge",
            "POST /v1/attest/register",
            "POST /v1/attest/challenge",
            "POST /v1/reports",
            "PUT /reports/TR-TEST-0001/screenshot-1.png",
            "PUT /reports/TR-TEST-0001/logs.zip",
            "POST /v1/attest/challenge",
            "POST /v1/reports/TR-TEST-0001/complete"
        ])
        #expect(progress.first == 0)
        #expect(progress.last == 1)

        let register = try Self.object(requests[1].body)
        #expect(register["keyId"] as? String == "synthetic-key-1")
        #expect(register["appId"] as? String == Self.appID)
        #expect(register["challenge"] as? String == "synthetic-challenge-1")
        #expect(register["attestation"] as? String == Data("synthetic-attestation".utf8).base64EncodedString())
        #expect(service.attested.first?.hash == Data(SHA256.hash(data: Data("synthetic-challenge-1".utf8))))

        let create = requests[3]
        #expect(create.headers["X-Trio-Key-Id"] == "synthetic-key-1")
        #expect(create.headers["X-Trio-Challenge"] == "synthetic-challenge-2")
        #expect(create.headers["X-Trio-Assertion"] == Data("synthetic-assertion-1".utf8).base64EncodedString())
        #expect(create.body == (try HTTPReportSubmitter.body(for: Self.report())))
        #expect(service.asserted[0].hash == Data(SHA256.hash(data: create.body + Data("synthetic-challenge-2".utf8))))

        let complete = requests[7]
        #expect(complete.body == Data("{}".utf8))
        #expect(complete.headers["X-Trio-Challenge"] == "synthetic-challenge-3")
        #expect(service.asserted[1].hash == Data(SHA256.hash(data: Data("{}synthetic-challenge-3".utf8))))
    }

    @Test("Presigned uploads send exactly the returned headers") func presignedHeaders() async throws {
        serve()
        _ = try await submitter.submit(Self.report()) { _ in }

        let puts = requests.filter { $0.method == "PUT" }
        #expect(puts.count == 2)
        for (put, attachment) in zip(puts, [Self.screenshot, Self.logs]) {
            #expect(put.url.query == "X-Amz-Signature=synthetic")
            #expect(put.body == attachment.data)
            for (field, value) in Self.uploadHeaders(attachment) {
                #expect(put.headers[field] == value)
            }
            #expect(put.headers["X-Trio-Key-Id"] == nil)
            #expect(put.headers["X-Trio-Assertion"] == nil)
        }
    }

    @Test("A rejected key is re-attested once and the step retried") func reattestOnce() async throws {
        var creates = 0
        serve { request in
            guard request.path == "/v1/reports" else { return nil }
            creates += 1
            return creates == 1 ? (401, Self.json(["error": "Unknown key.", "code": "invalid_key"])) : nil
        }
        let id = try await submitter.submit(Self.report()) { _ in }

        #expect(id == "TR-TEST-0001")
        #expect(creates == 2)
        #expect(service.generatedKeys == 2)
        #expect(requests.filter { $0.path == "/v1/attest/register" }.count == 2)
        let signed = requests.filter { $0.path == "/v1/reports" }
        #expect(signed.map { $0.headers["X-Trio-Key-Id"] } == ["synthetic-key-1", "synthetic-key-2"])
    }

    @Test("A key rejected twice gives up") func reattestGivesUp() async throws {
        serve { request in
            request.path == "/v1/reports" ? (401, Self.json(["error": "Unknown key.", "code": "invalid_key"])) : nil
        }
        await #expect(throws: ReportSubmitError.server(status: 401)) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        #expect(requests.filter { $0.path == "/v1/reports" }.count == 2)
        #expect(service.generatedKeys == 2)
    }

    @Test("A rejected assertion is retried with a fresh challenge and the same key") func assertionRetry() async throws {
        var creates = 0
        serve { request in
            guard request.path == "/v1/reports" else { return nil }
            creates += 1
            return creates == 1 ? (401, Self.json(["error": "Bad assertion.", "code": "invalid_assertion"])) : nil
        }
        let id = try await submitter.submit(Self.report()) { _ in }

        #expect(id == "TR-TEST-0001")
        #expect(service.generatedKeys == 1)
        #expect(requests.filter { $0.path == "/v1/attest/register" }.count == 1)
        let signed = requests.filter { $0.path == "/v1/reports" }
        #expect(signed.map { $0.headers["X-Trio-Key-Id"] } == ["synthetic-key-1", "synthetic-key-1"])
        #expect(signed[0].headers["X-Trio-Challenge"] != signed[1].headers["X-Trio-Challenge"])
    }

    @Test("Repeated assertion failures fall back to a new key once") func assertionFallback() async throws {
        serve { request in
            request.path == "/v1/reports" ? (401, Self.json(["error": "Bad assertion.", "code": "invalid_assertion"])) : nil
        }
        await #expect(throws: ReportSubmitError.server(status: 401)) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        let signed = requests.filter { $0.path == "/v1/reports" }
        #expect(signed.map { $0.headers["X-Trio-Key-Id"] } == ["synthetic-key-1", "synthetic-key-1", "synthetic-key-2"])
        #expect(service.generatedKeys == 2)
    }

    @Test("A cold server gets a long wait and one retry per request after a timeout") func coldServer() async throws {
        var challengeTimeouts = 0
        var createTimeouts = 0
        serve { request in
            switch request.path {
            case "/v1/attest/challenge" where challengeTimeouts == 0:
                challengeTimeouts += 1
                return (URLError.timedOut.rawValue, Data())
            case "/v1/reports" where createTimeouts == 0:
                createTimeouts += 1
                return (URLError.timedOut.rawValue, Data())
            default:
                return nil
            }
        }
        let id = try await submitter.submit(Self.report()) { _ in }

        #expect(id == "TR-TEST-0001")
        #expect(Array(steps().prefix(7)) == [
            "POST /v1/attest/challenge",
            "POST /v1/attest/challenge",
            "POST /v1/attest/register",
            "POST /v1/attest/challenge",
            "POST /v1/reports",
            "POST /v1/attest/challenge",
            "POST /v1/reports"
        ])
        let signed = requests.filter { $0.path == "/v1/reports" }
        #expect(signed[0].headers["X-Trio-Challenge"] != signed[1].headers["X-Trio-Challenge"])
        #expect(requests.filter { $0.method == "POST" }.allSatisfy { $0.timeout == 60 })
    }

    @Test("A second timeout gives up") func repeatedTimeout() async throws {
        serve { request in
            request.path == "/v1/reports" ? (URLError.timedOut.rawValue, Data()) : nil
        }
        await #expect(throws: ReportSubmitError.network(URLError(.timedOut).localizedDescription)) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        #expect(requests.filter { $0.path == "/v1/reports" }.count == 2)
    }

    @Test("Server errors map to plain messages by code and status") func errorMapping() throws {
        func error(_ status: Int, _ code: String? = nil) -> ReportSubmitError {
            .from(status: status, data: code.map { Self.json(["error": "Synthetic.", "code": $0]) })
        }
        #expect(error(429, "rate_limited") == .rateLimited)
        #expect(error(429) == .rateLimited)
        #expect(error(403, "app_not_allowed") == .appNotAllowed)
        #expect(error(413, "too_large") == .tooLarge)
        #expect(error(400, "too_large") == .tooLarge)
        #expect(error(415, "unsupported_type") == .unsupportedImage)
        #expect(error(400, "invalid_request") == .server(status: 400))
        #expect(error(503) == .server(status: 503))
        #expect(ReportSubmitError.from(status: 429, data: Data("not json".utf8)) == .rateLimited)

        #expect(ReportSubmitError.rateLimited.message == "You've sent several reports today. Please try again tomorrow.")
        #expect(
            ReportSubmitError.appNotAllowed.message ==
                "This build of Trio can't send reports. Please share your logs on Discord or Facebook instead."
        )
        #expect(ReportSubmitError.from(AppAttestClient.AttestError.forbidden) == .appNotAllowed)
        #expect(ReportSubmitError.from(AppAttestClient.AttestError.unsupportedDevice) == .appNotAllowed)
        #expect(ReportSubmitError.from(AppAttestClient.AttestError.serverError(502)) == .server(status: 502))
        let offline = URLError(.notConnectedToInternet)
        #expect(ReportSubmitError.from(offline) == .network(offline.localizedDescription))

        #expect(ReportSubmitError.server(status: 500).canRetry)
        #expect(ReportSubmitError.attestationFailed.canRetry)
        #expect(!ReportSubmitError.server(status: 400).canRetry)
        #expect(!ReportSubmitError.rateLimited.canRetry)
        #expect(!ReportSubmitError.appNotAllowed.canRetry)
        #expect(!ReportSubmitError.logsTooLarge.canRetry)
    }

    @Test("A rate-limited report is not uploaded") func rateLimitedCreate() async throws {
        serve { request in
            request.path == "/v1/reports" ? (429, Self.json(["error": "Too many reports.", "code": "rate_limited"])) : nil
        }
        await #expect(throws: ReportSubmitError.rateLimited) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        #expect(!requests.contains { $0.method == "PUT" })
    }

    @Test("Failed uploads are retried per file") func uploadRetries() async throws {
        var screenshotPuts = 0
        serve { request in
            guard request.method == "PUT", request.path.hasSuffix("screenshot-1.png") else { return nil }
            screenshotPuts += 1
            return screenshotPuts < 3 ? (503, Data()) : nil
        }
        _ = try await submitter.submit(Self.report()) { _ in }

        #expect(screenshotPuts == 3)
        #expect(requests.filter { $0.path.hasSuffix("logs.zip") }.count == 1)
        #expect(requests.last?.path == "/v1/reports/TR-TEST-0001/complete")
    }

    @Test("Uploads stop after the last attempt or a client error") func uploadGivesUp() async throws {
        serve { request in
            request.method == "PUT" ? (503, Data()) : nil
        }
        await #expect(throws: ReportSubmitError.server(status: 503)) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        #expect(requests.filter { $0.method == "PUT" }.count == 3)
        #expect(!requests.contains { $0.path.hasSuffix("/complete") })

        StubURLProtocol.requests = []
        serve { request in
            request.method == "PUT" ? (403, Data()) : nil
        }
        await #expect(throws: ReportSubmitError.server(status: 403)) {
            try await self.submitter.submit(Self.report()) { _ in }
        }
        #expect(requests.filter { $0.method == "PUT" }.count == 1)
    }

    @Test("The draft is kept until the report is complete") func draftKeptUntilComplete() async throws {
        var draft = ReportDraft(title: "Synthetic", description: "Something happened")
        draft.save(to: storage)

        serve { request in
            request.path.hasSuffix("/complete") ? (500, Self.json(["error": "Failure.", "code": "server_error"])) : nil
        }
        await #expect(throws: ReportSubmitError.server(status: 500)) {
            try await self.submitter.send(Self.report(), storage: self.storage)
        }
        #expect(ReportDraft.load(from: storage) == draft)
        #expect(SentReports.load(from: storage).isEmpty)

        serve()
        let id = try await submitter.send(Self.report(), storage: storage)
        #expect(ReportDraft.load(from: storage) == ReportDraft())
        #expect(SentReports.load(from: storage).map(\.id) == [id])
    }

    @Test("Sent reports are listed newest first and expire after 90 days") func sentReportStore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        SentReports.add("TR-OLD0-0001", date: now.addingTimeInterval(-91 * 24 * 60 * 60), in: storage)
        SentReports.add("TR-TEST-0001", date: now.addingTimeInterval(-60), in: storage)
        SentReports.add("TR-TEST-0002", date: now, in: storage)
        #expect(SentReports.load(from: storage, now: now).map(\.id) == ["TR-TEST-0002", "TR-TEST-0001"])

        SentReports.add("TR-TEST-0001", date: now, in: storage)
        #expect(SentReports.load(from: storage, now: now).filter { $0.id == "TR-TEST-0001" }.count == 1)

        SentReports.remove("TR-TEST-0002", in: storage)
        #expect(SentReports.load(from: storage, now: now).map(\.id) == ["TR-TEST-0001"])
    }

    @Test("Deleting a report signs an empty body and forgets it locally") func deleteReport() async throws {
        SentReports.add("TR-TEST-0001", in: storage)
        serve()
        try await submitter.withdraw(id: "TR-TEST-0001", storage: storage)

        let delete = try #require(requests.last)
        #expect(delete.method == "DELETE")
        #expect(delete.path == "/v1/reports/TR-TEST-0001")
        #expect(delete.body.isEmpty)
        let challenge = try #require(delete.headers["X-Trio-Challenge"])
        #expect(service.asserted.last?.hash == Data(SHA256.hash(data: Data(challenge.utf8))))
        #expect(SentReports.load(from: storage).isEmpty)
    }

    @Test("A report already gone is forgotten, other failures keep it") func deleteOutcomes() async throws {
        SentReports.add("TR-GONE-0001", in: storage)
        serve()
        try await submitter.withdraw(id: "TR-GONE-0001", storage: storage)
        #expect(SentReports.load(from: storage).isEmpty)

        SentReports.add("TR-TEST-0001", in: storage)
        serve { request in request.method == "DELETE" ? (500, Data()) : nil }
        await #expect(throws: ReportSubmitError.server(status: 500)) {
            try await self.submitter.withdraw(id: "TR-TEST-0001", storage: self.storage)
        }
        #expect(SentReports.load(from: storage).map(\.id) == ["TR-TEST-0001"])
    }

    @Test("Limits are checked before anything is sent") func limits() async throws {
        func image(_ bytes: Int, _ index: Int = 1) -> ProblemReport.Attachment {
            .init(filename: "screenshot-\(index).jpg", contentType: "image/jpeg", data: Data(count: bytes))
        }
        func zip(_ bytes: Int) -> ProblemReport.Attachment {
            .init(filename: "logs.zip", contentType: "application/zip", data: Data(count: bytes))
        }

        #expect(throws: Never.self) { try ReportLimits.check((1 ... 8).map { image(5_000_000, $0) }) }
        #expect(throws: ReportSubmitError.tooLarge) { try ReportLimits.check((1 ... 9).map { image(10, $0) }) }
        #expect(throws: ReportSubmitError.tooLarge) { try ReportLimits.check([image(5_000_001)]) }
        #expect(throws: ReportSubmitError.logsTooLarge) { try ReportLimits.check([zip(15_000_001)]) }
        #expect(throws: ReportSubmitError.logsTooLarge) { try ReportLimits.check([zip(1), zip(1)]) }
        #expect(throws: ReportSubmitError.tooLarge) {
            try ReportLimits.check((1 ... 8).map { image(5_000_000, $0) } + [zip(1)])
        }
        #expect(throws: ReportSubmitError.unsupportedImage) {
            try ReportLimits.check([.init(filename: "notes.txt", contentType: "text/plain", data: Data([1]))])
        }

        serve()
        await #expect(throws: ReportSubmitError.logsTooLarge) {
            try await self.submitter.submit(Self.report([zip(15_000_001)])) { _ in }
        }
        #expect(requests.isEmpty)
    }

    @Test("Endpoint picks the real, mock or no submitter") func endpointSelection() throws {
        var made: [URL] = []
        let make = { (url: URL) -> ReportSubmitting in
            made.append(url)
            return MockReportSubmitter()
        }
        let mock = ReportEndpoint.submitter(attestSupported: false, allowsMock: true, useDev: false, make: make)
        #expect(mock is MockReportSubmitter)
        #expect(ReportEndpoint.submitter(attestSupported: false, allowsMock: false, useDev: false, make: make) == nil)
        #expect(made.isEmpty)

        _ = ReportEndpoint.submitter(attestSupported: true, allowsMock: false, useDev: false, make: make)
        _ = ReportEndpoint.submitter(attestSupported: true, allowsMock: true, useDev: true, make: make)
        _ = ReportEndpoint.submitter(
            attestSupported: true,
            allowsMock: true,
            useDev: true,
            baseURL: "https://support.example.test",
            make: make
        )
        #expect(made.map(\.absoluteString) == [
            "https://support.triodocs.org",
            "https://support-dev.triodocs.org",
            "https://support.example.test"
        ])
    }

    private func endpointSubmitter() throws -> HTTPReportSubmitter {
        let submitter = ReportEndpoint.submitter(keychain: keychain, service: service, defaults: storage)
        return try #require(submitter as? HTTPReportSubmitter)
    }

    @Test("Debug launch arguments pick the dev server and its own key") func debugEndpoint() throws {
        let plain = try endpointSubmitter()
        #expect(plain.attest.baseURL.absoluteString == ReportEndpoint.production)
        #expect(plain.attest.namespace == "ReportAttest")

        storage.set(true, forKey: ReportEndpoint.devKey)
        let dev = try endpointSubmitter()
        #expect(dev.attest.baseURL.absoluteString == ReportEndpoint.dev)
        #expect(dev.attest.namespace == "ReportAttest.dev")

        storage.removeObject(forKey: ReportEndpoint.devKey)
        storage.set("https://support.example.test", forKey: ReportEndpoint.baseURLKey)
        let custom = try endpointSubmitter()
        #expect(custom.attest.baseURL == Self.base)
        #expect(custom.attest.namespace == "ReportAttest.dev")
    }

    @Test("Mock submitter returns a debug ID") func mockSubmitter() async throws {
        let id = try await MockReportSubmitter().submit(Self.report()) { _ in }
        #expect(id.hasPrefix("TR-DBUG-"))
        #expect(id.count == "TR-DBUG-".count + 4)
    }

    @Test("App Attest client keeps telemetry's field names and registers once") func attestClientTelemetryShape() async throws {
        serve { request in
            switch request.path {
            case "/api/auth/ios/challenge": return (200, Self.json(["challenge": "synthetic-challenge"]))
            case "/api/attest/register": return (200, Data())
            default: return nil
            }
        }
        var client = AppAttestClient(
            baseURL: Self.base,
            challengePath: "api/auth/ios/challenge",
            registerPath: "api/attest/register",
            namespace: "SyntheticAttest",
            keychain: keychain,
            category: .telemetry,
            registerFields: (keyID: "key_id", appID: "app_id"),
            queryItems: [URLQueryItem(name: "reason", value: "test")],
            prepare: { $0.setValue("9.9.9", forHTTPHeaderField: "X-Trio-Version") },
            service: service
        )
        client.session = session
        client.appID = { Self.appID }

        try await client.registerIfNeeded()
        try await client.registerIfNeeded()

        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url.query == "reason=test" && $0.headers["X-Trio-Version"] == "9.9.9" })
        #expect(requests[0].body.isEmpty)
        let register = try Self.object(requests[1].body)
        #expect(Set(register.keys) == ["key_id", "app_id", "attestation", "challenge"])
        #expect(keychain.getValue(String.self, forKey: "SyntheticAttest.keyID") == "synthetic-key-1")
        #expect(keychain.getValue(Bool.self, forKey: "SyntheticAttest.registered") == true)

        client.invalidateRegistration()
        #expect(!client.isRegistered)
        #expect(keychain.getValue(String.self, forKey: "SyntheticAttest.keyID") == nil)
    }

    @Test("App Attest client reports unsupported devices and rejected apps") func attestClientFailures() async throws {
        service.isSupported = false
        await #expect(throws: AppAttestClient.AttestError.self) { try await self.attest.registerIfNeeded() }
        #expect(requests.isEmpty)

        service.isSupported = true
        serve { request in request.path == "/v1/attest/register" ? (403, Data()) : nil }
        do {
            try await attest.registerIfNeeded()
            Issue.record("Registration should fail")
        } catch AppAttestClient.AttestError.forbidden {} catch {
            Issue.record("Unexpected error \(error)")
        }
        #expect(!attest.isRegistered)
        #expect(requests.first?.body == Data("{}".utf8))
    }
}
