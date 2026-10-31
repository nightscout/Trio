import Foundation

extension TherapySettingsEditor.Item {
    fileprivate var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    func asBasalProfileEntry() -> BasalProfileEntry {
        let start = timeFormatter.string(from: Date(timeIntervalSince1970: time))
        let minutes = Int(time / 60)
        return BasalProfileEntry(start: start, minutes: minutes, rate: value)
    }
}
