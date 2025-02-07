
import Foundation

struct DateFilter {
    var twoHours = Date().addingTimeInterval(-2.hours.timeInterval) as NSDate
    var today = Calendar.current.startOfDay(for: Date()) as NSDate
    var day = Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
    var week = Date().addingTimeInterval(-7.days.timeInterval) as NSDate
    var month = Date().addingTimeInterval(-30.days.timeInterval) as NSDate
    var total = Date().addingTimeInterval(-90.days.timeInterval) as NSDate
}
