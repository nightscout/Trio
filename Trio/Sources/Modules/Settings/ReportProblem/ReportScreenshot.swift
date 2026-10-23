import UIKit

struct ReportScreenshot: Identifiable {
    static let maxBytes = 10_000_000

    let id = UUID()
    let image: UIImage
    let attachment: ProblemReport.Attachment

    // Redraws the pixels so location and camera metadata never leave the phone
    init?(data: Data, index: Int, maxBytes: Int = maxBytes) {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]), let png = image.pngData(), png.count <= maxBytes {
            self.image = image
            attachment = .init(filename: "screenshot-\(index).png", contentType: "image/png", data: png)
            return
        }
        for quality in [0.8, 0.5, 0.3] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                self.image = image
                attachment = .init(filename: "screenshot-\(index).jpg", contentType: "image/jpeg", data: jpeg)
                return
            }
        }
        return nil
    }
}
