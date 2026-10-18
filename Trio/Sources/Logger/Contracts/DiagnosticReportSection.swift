import Foundation

protocol DiagnosticReportSection {
    var title: String { get }
    var order: Int { get }
    func render(window: DateInterval, into directory: URL) async -> String
}
