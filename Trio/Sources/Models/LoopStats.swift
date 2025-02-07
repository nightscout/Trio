import Foundation

struct LoopStats: JSON, Equatable {
    var start: Date
    var end: Date?
    var duration: Double?
    var loopStatus: String
    var interval: Double?

    init(
        start: Date,
        loopStatus: String,
        interval: Double?
    ) {
        self.start = start
        self.loopStatus = loopStatus
        self.interval = interval
    }
}

extension LoopStats {
    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case duration
        case loopStatus
        case interval
    }
}
