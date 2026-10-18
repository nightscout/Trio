import Foundation

struct BuildSection: DiagnosticReportSection {
    let title = "Build"
    let order = 0
    var buildDetails: BuildDetails = .shared
    var bundle: Bundle = .main

    func render(window _: DateInterval, into _: URL) async -> String {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        var lines = [
            "- Version: \(version) (\(build))",
            "- Dev version: \(bundle.appDevVersion ?? "unknown")",
            "- Branch: \(buildDetails.trioBranch)",
            "- Commit: \(buildDetails.trioCommitSHA)",
            "- Built: \(buildDetails.buildDateString ?? "unknown")",
            "- Expires: \(ReportFormatting.timestamp(buildDetails.calculateExpirationDate()))",
            "- TestFlight: \(buildDetails.isTestFlightBuild() ? "yes" : "no")"
        ]
        let submodules = buildDetails.submodules.sorted { $0.key < $1.key }
        if !submodules.isEmpty {
            lines.append("- Submodules:")
            lines += submodules.map { "  - \($0.key): \($0.value.branch) \($0.value.commitSHA)" }
        }
        return lines.joined(separator: "\n")
    }
}
