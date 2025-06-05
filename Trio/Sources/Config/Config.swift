import Foundation
import SwiftDate

enum Config {
    static let treatWarningsAsErrors = true
    static let withSignPosts = false

    static var loopInterval: TimeInterval {
        let customInterval = UserDefaults.standard.double(forKey: "Config_LoopInterval")
        return customInterval > 0 ? customInterval : 3.minutes.timeInterval
    }

    static let eхpirationInterval = 10.minutes.timeInterval
}
