import Foundation

struct ContactTrickState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var lastLoopDate: Date?
    var iob: Decimal?
    var iobText: String?
    var cob: Decimal?
    var cobText: String?
    var eventualBG: String?
    var maxIOB: Decimal = 10.0
    var maxCOB: Decimal = 120.0
}
