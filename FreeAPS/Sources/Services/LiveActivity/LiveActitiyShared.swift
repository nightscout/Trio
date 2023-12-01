import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let bg: String
        let trendSystemImage: String?
        let change: String
        let date: Date
    }

    let startDate: Date
}
