import Foundation

struct ContactImageState: Codable {
    var glucose: String?
    var trend: String?
    /// Raw direction backing `trend`, kept separately so the "Glucose Bobble" style can rotate its
    /// trend arrow exactly like the HUD bobble does, instead of reparsing the arrow glyph.
    var direction: BloodGlucose.Direction?
    var delta: String?
    var lastLoopDate: Date?
    var iob: Decimal?
    var iobText: String?
    var cob: Decimal?
    var cobText: String?
    var eventualBG: String?
    var maxIOB: Decimal = 10.0
    var maxCOB: Decimal = 120.0
    var highGlucoseColorValue: Decimal = 180.0
    var lowGlucoseColorValue: Decimal = 70.0
    var glucoseColorScheme: GlucoseColorScheme = .staticColor
    var targetGlucose: Decimal = 100.0
}
