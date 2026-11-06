import SwiftUI

/// Renders one or more SwiftUI views into a multi-page A4 PDF file, one page per view.
enum StatPDFExporter {
    /// A4 page size in points at 72 DPI (210mm x 297mm).
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    enum ExportError: LocalizedError {
        case noPages
        case renderingFailed
        case fileWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noPages:
                return String(localized: "The report has no pages to export.")
            case .renderingFailed:
                return String(localized: "Could not render the PDF content.")
            case let .fileWriteFailed(error):
                return String(localized: "Failed to write PDF file: \(error.localizedDescription)")
            }
        }
    }

    /// Renders `pages` at `pageSize`, one per PDF page in order, and writes the result to a
    /// temporary file.
    ///
    /// A fresh `ImageRenderer` is built for each page because `ImageRenderer.content` can only be
    /// reassigned to the same concrete `Content` type it was created with, and pages are
    /// type-erased `AnyView`s of differing underlying content — but all pages still share the
    /// same underlying `CGContext`/output so they land in a single PDF file.
    /// - Returns: The URL of the written PDF file.
    @MainActor static func export(_ pages: [AnyView], fileName: String) throws -> URL {
        guard !pages.isEmpty else {
            throw ExportError.noPages
        }

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ExportError.renderingFailed
        }

        for page in pages {
            let renderer = ImageRenderer(
                content: page
                    .frame(width: pageSize.width, height: pageSize.height)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(pageSize)

            renderer.render { _, renderContent in
                pdfContext.beginPDFPage(nil)
                renderContent(pdfContext)
                pdfContext.endPDFPage()
            }
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
