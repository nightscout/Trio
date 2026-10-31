import Foundation

extension TherapySettingsEditor.Item {
    fileprivate var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    func asBGTargetEntry() -> BGTargetEntry {
        let start = timeFormatter.string(from: Date(timeIntervalSince1970: time))
        let offset = Int(time / 60)
        return BGTargetEntry(low: value, high: value, start: start, offset: offset)
    }
}
