import SwiftUI

/// Renders a SwiftUI view into a single-page A4 PDF file.
enum StatPDFExporter {
    /// A4 page size in points at 72 DPI (210mm x 297mm).
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    enum ExportError: LocalizedError {
        case renderingFailed
        case fileWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .renderingFailed:
                return String(localized: "Could not render the PDF content.")
            case let .fileWriteFailed(error):
                return String(localized: "Failed to write PDF file: \(error.localizedDescription)")
            }
        }
    }

    /// Renders `content` at `pageSize` and writes it as a single-page PDF to a temporary file.
    /// - Returns: The URL of the written PDF file.
    @MainActor static func export(_ content: some View, fileName: String) throws -> URL {
        let renderer = ImageRenderer(
            content: content
                .frame(width: pageSize.width, height: pageSize.height)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(pageSize)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ExportError.renderingFailed
        }

        renderer.render { _, renderContent in
            pdfContext.beginPDFPage(nil)
            renderContent(pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).appendingPathExtension("pdf")
        do {
            try (pdfData as Data).write(to: fileURL, options: .atomic)
        } catch {
            throw ExportError.fileWriteFailed(error)
        }

        return fileURL
    }
}
