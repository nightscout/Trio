import Foundation
import Harmonize
import Testing

@Suite struct RulesSelfExplain {
    @Test func everyRuleFileExplainsItselfWithARule() {
        let rulesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let violations = Self.swiftFiles(in: rulesDirectory)
            .filter { !Self.infrastructure.contains($0.lastPathComponent) }
            .filter { file in
                let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                return !contents.contains("Rule(")
            }

        #expect(
            violations.isEmpty,
            "\(Self.rule.message)\n\nViolating files:\n\(violations.map(\.lastPathComponent).joined(separator: "\n"))"
        )
    }

    private static let infrastructure = ["TrioHarmonize.swift"]

    private static func swiftFiles(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return enumerator?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    }

    private static let rule = Rule(
        description: "Every lint rule passes a Rule to its assertion.",
        rationale: "A failing rule must explain why it exists and how to fix it, otherwise the next person works around it instead of fixing the code.",
        fixHint: "Replace the raw string with a Rule(description, rationale, fixHint, badExample, goodExample).",
        badExample: "files.assertFalse(message: \"Don't sleep\") { ... }",
        goodExample: "files.assertFalse(rule: rule) { ... }"
    )
}
