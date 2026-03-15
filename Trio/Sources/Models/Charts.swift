
import Foundation

struct ShapeModel: Identifiable {
    var type: String
    var percent: Decimal
    var id = UUID()
}

struct ChartData: Identifiable {
    var date: Date
    var iob: Double
    var zt: Double
    var cob: Double
    var uam: Double
    var id = UUID()
}
