import Foundation

extension Calendar {
    /// Converts an hour (0-23) to a Date object representing that hour on the current day.
    /// This is used to properly position marks on the chart's time axis.
    ///
    /// - Parameter hour: Integer representing the hour of day (0-23)
    /// - Returns: Date object set to the specified hour on the current day
    ///
    /// Example:
    /// ```
    /// calendar.dateForChartHour(14) // Returns today's date at 2:00 PM
    /// calendar.dateForChartHour(0)  // Returns today's date at 12:00 AM
    /// ```
    func dateForChartHour(_ hour: Int) -> Date {
        let today = startOfDay(for: Date())
        return date(byAdding: .hour, value: hour, to: today) ?? today
    }
}
