import Foundation

protocol DayNightDisplayable {
    var displayName: String { get }
}

extension DayNightDisplayable where Self: RawRepresentable, Self.RawValue == String {
    var displayName: String {
        rawValue == "always"
            ? String(localized: "Day & Night")
            : rawValue.localizedCapitalized
    }
}

enum ActiveOption: String, CaseIterable, Codable, Identifiable, DayNightDisplayable {
    case always
    case day
    case night

    var id: String { rawValue }
}

struct TimeOfDay: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }
}
