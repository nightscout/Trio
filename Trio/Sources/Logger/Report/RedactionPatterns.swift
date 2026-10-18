import Foundation

enum RedactionPatterns {
    struct Pattern {
        let regex: NSRegularExpression
        let kind: Redactor.Kind
        let group: Int
    }

    // Order matters: Omnipod lot/TID digits run before the Dexcom TID pattern
    static let all: [Pattern] = [
        make(#"https?://[^\s"'<>)]+"#, kind: .url),
        make(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, kind: .email),
        make(#"Bearer\s+([A-Za-z0-9._-]+)"#, kind: .secret, group: 1),
        make(#"(?i)\b(?:lot|tid)[:\s]+(\d+)\b"#, kind: .pumpSerial, group: 1),
        make(#"(?i)\b(?:transmitter(?:ID)?|TID)[:\s"=]+([A-Za-z0-9]{6})\b"#, kind: .cgmSerial, group: 1),
        make(labelled: ["lotNo", "lotSeq", "pumpSN"], kind: .pumpSerial),
        make(labelled: ["sensorID", "sensorSerial", "transmitterSerial", "bleNameString"], kind: .cgmSerial),
        make(labelled: ["deviceName", "serialNumber"], kind: .serial),
        make(#"\b[0-9a-fA-F]{40}\b"#, kind: .secret)
    ].compactMap { $0 }

    static let ignoredValues: Set<String> = ["nil", "none", "unknown"]

    private static func make(_ pattern: String, kind: Redactor.Kind, group: Int = 0) -> Pattern? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Pattern(regex: regex, kind: kind, group: group)
    }

    // Kit debug descriptions print serials as `label: value` or `label: Optional("value")`
    private static func make(labelled labels: [String], kind: Redactor.Kind) -> Pattern? {
        make(
            #"(?i)\b(?:"# + labels.joined(separator: "|") + #")"?\s*[:=]\s*(?:Optional\()?"?([^\s"),<][^\s"),]{2,})"#,
            kind: kind,
            group: 1
        )
    }
}
