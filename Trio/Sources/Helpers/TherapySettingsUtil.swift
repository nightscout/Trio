import Foundation

enum TherapySettingsUtil {
    /// Parses a time string of therapy setting entry into a `Date` object using either "HH:mm:ss" or "HH:mm" formats.
    /// This function ensures compatibility with time strings that may include or exclude seconds.
    ///
    /// - Parameter timeString: A string representing the time in "HH:mm:ss" or "HH:mm" format.
    /// - Returns: A `Date` object set to today’s date with the extracted time, or `nil` if parsing fails.
    static func parseTime(_ timeString: String) -> Date? {
        let formats = ["HH:mm:ss", "HH:mm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: timeString) {
                return date
            }
        }
        return nil
    }
}
