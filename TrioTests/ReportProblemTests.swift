import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Trio

@Suite("Report a Problem Tests") struct ReportProblemTests {
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

    private static func report(
        contact: ProblemReport.Contact? = nil,
        attachments: [ProblemReport.Attachment] = []
    ) -> ProblemReport {
        ProblemReport(
            title: "Synthetic title",
            description: "Synthetic description",
            contact: contact,
            context: context,
            attachments: attachments
        )
    }

    private struct Part {
        let headers: String
        let body: Data
    }

    private static func parts(of body: Data, boundary: String) -> [Part] {
        let delimiter = Data("--\(boundary)".utf8)
        var parts: [Part] = []
        var searchStart = body.startIndex
        var ranges: [Range<Data.Index>] = []
        while let range = body.range(of: delimiter, in: searchStart ..< body.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        for (current, next) in zip(ranges, ranges.dropFirst()) {
            // Each part is "\r\n<headers>\r\n\r\n<body>\r\n" between delimiters
            let chunk = body[current.upperBound ..< next.lowerBound]
            guard let split = chunk.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let headers = String(decoding: chunk[chunk.startIndex ..< split.lowerBound], as: UTF8.self)
            let content = chunk[split.upperBound ..< chunk.index(chunk.endIndex, offsetBy: -2)]
            parts.append(Part(headers: headers.trimmingCharacters(in: .whitespacesAndNewlines), body: Data(content)))
        }
        return parts
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Multipart body has the report and one part per attachment") func multipartStructure() throws {
        let screenshot = ProblemReport.Attachment(filename: "screenshot-1.png", contentType: "image/png", data: Data([1, 2, 3]))
        let logs = ProblemReport.Attachment(filename: "Trio Log.zip", contentType: "application/zip", data: Data([4, 5]))
        let body = try HTTPReportSubmitter.body(
            for: Self.report(attachments: [screenshot, logs]),
            boundary: "TEST-BOUNDARY",
            client: nil
        )

        #expect(body.starts(with: Data("--TEST-BOUNDARY\r\n".utf8)))
        #expect(String(decoding: body.suffix(19), as: UTF8.self) == "--TEST-BOUNDARY--\r\n")

        let parts = Self.parts(of: body, boundary: "TEST-BOUNDARY")
        #expect(parts.count == 3)
        #expect(parts[0].headers.contains("name=\"report\""))
        #expect(parts[0].headers.contains("Content-Type: application/json"))
        #expect(parts[1].headers.contains("name=\"attachment\"; filename=\"screenshot-1.png\""))
        #expect(parts[1].headers.contains("Content-Type: image/png"))
        #expect(parts[1].body == Data([1, 2, 3]))
        #expect(parts[2].headers.contains("filename=\"Trio Log.zip\""))
        #expect(parts[2].body == Data([4, 5]))

        let json = try Self.json(parts[0].body)
        #expect(json["title"] as? String == "Synthetic title")
        #expect(json["description"] as? String == "Synthetic description")
        #expect(json["contact"] == nil)
        let context = try #require(json["context"] as? [String: Any])
        #expect(context["appVersion"] as? String == "1.0.0")
        #expect(context["buildNumber"] as? String == "1")
        #expect(context["devVersion"] as? String == "1.0.0.1")
        #expect(context["branch"] as? String == "dev")
        #expect(context["commit"] as? String == "abc1234")
        #expect(context["deviceModel"] as? String == "iPhone99,9")
        #expect(context["osVersion"] as? String == "27.0.0")
        #expect(context["pumpModel"] as? String == "Example Pump")
        #expect(context["cgmModel"] == nil)
    }

    @Test("Client part is sent first only when configured") func clientPart() throws {
        let body = try HTTPReportSubmitter.body(for: Self.report(), boundary: "B", client: "synthetic-client")
        let parts = Self.parts(of: body, boundary: "B")
        #expect(parts.count == 2)
        #expect(parts[0].headers.contains("name=\"client\""))
        #expect(parts[0].body == Data("synthetic-client".utf8))

        let without = Self.parts(of: try HTTPReportSubmitter.body(for: Self.report(), boundary: "B", client: ""), boundary: "B")
        #expect(without.count == 1)
    }

    @Test("Contact is left out when anonymous or blank") func contactOmission() throws {
        var draft = ReportDraft(description: "Something happened")
        draft.contact = ProblemReport.Contact(name: "Test User", email: "user@example.com")
        #expect(draft.report(context: Self.context, attachments: []).contact == nil)

        draft.isAnonymous = false
        draft.contact = ProblemReport.Contact(name: "  ", email: "\n")
        #expect(draft.report(context: Self.context, attachments: []).contact == nil)

        draft.contact = ProblemReport.Contact(name: " Test User ", github: "test-user")
        let report = draft.report(context: Self.context, attachments: [])
        #expect(report.contact == ProblemReport.Contact(name: "Test User", github: "test-user"))

        let parts = Self.parts(of: try HTTPReportSubmitter.body(for: report, boundary: "B", client: nil), boundary: "B")
        let contact = try #require(try Self.json(parts[0].body)["contact"] as? [String: String])
        #expect(contact == ["name": "Test User", "github": "test-user"])
    }

    @Test("Server status codes map to plain errors") func errorMapping() throws {
        #expect(throws: ReportSubmitError.tooLarge) { try HTTPReportSubmitter.reportID(status: 413, data: Data()) }
        #expect(throws: ReportSubmitError.unsupportedImage) { try HTTPReportSubmitter.reportID(status: 415, data: Data()) }
        #expect(throws: ReportSubmitError.rateLimited) { try HTTPReportSubmitter.reportID(status: 429, data: Data()) }
        #expect(throws: ReportSubmitError.server(status: 503)) { try HTTPReportSubmitter.reportID(status: 503, data: Data()) }
        #expect(throws: ReportSubmitError.server(status: 400)) { try HTTPReportSubmitter.reportID(status: 400, data: Data()) }
        #expect(throws: ReportSubmitError.invalidResponse) {
            try HTTPReportSubmitter.reportID(status: 200, data: Data("not json".utf8))
        }
        #expect(throws: ReportSubmitError.invalidResponse) {
            try HTTPReportSubmitter.reportID(status: 200, data: Data("{\"id\":\"\"}".utf8))
        }
        #expect(try HTTPReportSubmitter.reportID(status: 200, data: Data("{\"id\":\"TRIO-TEST-1\"}".utf8)) == "TRIO-TEST-1")

        #expect(ReportSubmitError.server(status: 500).canRetry)
        #expect(ReportSubmitError.network("offline").canRetry)
        #expect(!ReportSubmitError.server(status: 400).canRetry)
        #expect(!ReportSubmitError.tooLarge.canRetry)
        #expect(!ReportSubmitError.rateLimited.canRetry)
        #expect(!ReportSubmitError.invalidResponse.canRetry)
    }

    private static func jpegWithMetadata(size: CGSize, noise: Bool = false) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            guard noise else { return }
            var generator = SystemRandomNumberGenerator()
            for x in stride(from: 0, to: Int(size.width), by: 2) {
                for y in stride(from: 0, to: Int(size.height), by: 2) {
                    UIColor(
                        red: .random(in: 0 ... 1, using: &generator),
                        green: .random(in: 0 ... 1, using: &generator),
                        blue: .random(in: 0 ... 1, using: &generator),
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
        let cgImage = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.1, kCGImagePropertyGPSLongitude: 11.5],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SyntheticCam"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:01 12:00:00"]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    @Test("Screenshots are re-encoded without location or camera metadata") func screenshotMetadata() throws {
        let original = try Self.jpegWithMetadata(size: CGSize(width: 120, height: 80))
        #expect(try Self.properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let screenshot = try #require(ReportScreenshot(data: original, index: 2))
        #expect(screenshot.attachment.contentType == "image/jpeg")
        #expect(screenshot.attachment.filename == "screenshot-2.jpg")
        let properties = try Self.properties(of: screenshot.attachment.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)
    }

    @Test("PNG screenshots stay PNG") func pngScreenshot() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let png = try #require(image.pngData())
        let screenshot = try #require(ReportScreenshot(data: png, index: 1))
        #expect(screenshot.attachment.contentType == "image/png")
        #expect(screenshot.attachment.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Screenshots are shrunk to fit the size limit") func screenshotSizeLimit() throws {
        let noisy = try Self.jpegWithMetadata(size: CGSize(width: 600, height: 600), noise: true)
        let full = try #require(ReportScreenshot(data: noisy, index: 1))
        let limit = full.attachment.data.count - 1
        let smaller = try #require(ReportScreenshot(data: noisy, index: 1, maxBytes: limit))
        #expect(smaller.attachment.data.count <= limit)
        #expect(ReportScreenshot(data: noisy, index: 1, maxBytes: 100) == nil)
        #expect(ReportScreenshot.maxBytes == 10_000_000)
        #expect(ReportScreenshot(data: Data("not an image".utf8), index: 1) == nil)
    }

    @Test("Draft survives a round trip and clears") func draftPersistence() throws {
        let suite = "ReportProblemTests-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }

        #expect(ReportDraft.load(from: storage) == ReportDraft())

        var draft = ReportDraft(title: "Title", description: "Details", attachLogs: false, isAnonymous: false)
        draft.contact = ProblemReport.Contact(name: "Test User", email: "user@example.com", discord: "tester", github: "tester")
        draft.save(to: storage)
        #expect(ReportDraft.load(from: storage) == draft)

        ReportDraft.clear(in: storage)
        #expect(storage.data(forKey: ReportDraft.storageKey) == nil)
        #expect(ReportDraft.load(from: storage) == ReportDraft())
    }

    @Test("Description must have text to submit") func descriptionValidation() {
        #expect(!ReportDraft().canSubmit)
        #expect(!ReportDraft(description: " \n\t ").canSubmit)
        #expect(ReportDraft(description: " x ").canSubmit)
        #expect(!ReportDraft(description: String(repeating: "a", count: ReportDraft.maxDescriptionLength + 1)).canSubmit)

        let report = ReportDraft(title: "  ", description: "  Something happened \n")
            .report(context: Self.context, attachments: [])
        #expect(report.title == nil)
        #expect(report.description == "Something happened")

        let longTitle = ReportDraft(title: String(repeating: "t", count: 300), description: "x")
            .report(context: Self.context, attachments: [])
        #expect(longTitle.title?.count == ReportDraft.maxTitleLength)
    }

    @Test("Endpoint picks the real, mock or no submitter") func endpointSelection() throws {
        #expect(ReportEndpoint.submitter(endpoint: "", client: nil, allowsMock: true) is MockReportSubmitter)
        #expect(ReportEndpoint.submitter(endpoint: nil, client: nil, allowsMock: true) is MockReportSubmitter)
        #expect(ReportEndpoint.submitter(endpoint: "", client: nil, allowsMock: false) == nil)
        #expect(ReportEndpoint.submitter(endpoint: "http://example.com/report", client: nil, allowsMock: false) == nil)
        #expect(ReportEndpoint.submitter(endpoint: "$(TRIO_REPORT_ENDPOINT)", client: nil, allowsMock: false) == nil)

        let http = try #require(
            ReportEndpoint.submitter(
                endpoint: " https://example.com/report ",
                client: " ",
                allowsMock: false
            ) as? HTTPReportSubmitter
        )
        #expect(http.endpoint == URL(string: "https://example.com/report"))
        #expect(http.client == nil)

        let withClient = try #require(
            ReportEndpoint.submitter(
                endpoint: "https://example.com/report",
                client: "abc",
                allowsMock: true
            ) as? HTTPReportSubmitter
        )
        #expect(withClient.client == "abc")
    }

    @Test("Mock submitter returns a debug ID") func mockSubmitter() async throws {
        let id = try await MockReportSubmitter().submit(Self.report())
        #expect(id.hasPrefix("TRIO-DEBUG-"))
        #expect(id.count == "TRIO-DEBUG-".count + 6)
    }
}
