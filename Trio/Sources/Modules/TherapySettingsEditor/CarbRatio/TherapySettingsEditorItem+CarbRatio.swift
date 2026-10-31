import Foundation

extension TherapySettingsEditor.Item {
    fileprivate var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    func asCarbRatioEntry() -> CarbRatioEntry {
        let start = timeFormatter.string(from: Date(timeIntervalSince1970: time))
        let offset = Int(time / 60)
        return CarbRatioEntry(start: start, offset: offset, ratio: value)
    }
}
