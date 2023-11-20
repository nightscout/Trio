import Charts
import SwiftUI

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct DotInfo {
    let rect: CGRect
    let value: Decimal
}

struct AnnouncementDot {
    let rect: CGRect
    let value: Decimal
    let note: String
}

typealias GlucoseYRange = (minValue: Int, minY: CGFloat, maxValue: Int, maxY: CGFloat)

struct MainChartView2: View {
    private enum Config {
        static let endID = "End"
        static let basalHeight: CGFloat = 80
        static let topYPadding: CGFloat = 20
        static let bottomYPadding: CGFloat = 80
        static let minAdditionalWidth: CGFloat = 150
        static let maxGlucose = 270
        static let minGlucose = 45
        static let yLinesCount = 5
        static let glucoseScale: CGFloat = 2 // default 2
        static let bolusSize: CGFloat = 8
        static let bolusScale: CGFloat = 2.5
        static let carbsSize: CGFloat = 10
        static let fpuSize: CGFloat = 5
        static let carbsScale: CGFloat = 0.3
        static let fpuScale: CGFloat = 1
        static let announcementSize: CGFloat = 8
        static let announcementScale: CGFloat = 2.5
        static let owlSeize: CGFloat = 25
        static let owlOffset: CGFloat = 80
    }

    // MARK: BINDINGS

    @Binding var glucose: [BloodGlucose]
    @Binding var isManual: [BloodGlucose]
    @Binding var suggestion: Suggestion?
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var boluses: [PumpHistoryEvent]
    @Binding var suspensions: [PumpHistoryEvent]
    @Binding var announcement: [Announcement]
    @Binding var hours: Int
    @Binding var maxBasal: Decimal
    @Binding var autotunedBasalProfile: [BasalProfileEntry]
    @Binding var basalProfile: [BasalProfileEntry]
    @Binding var tempTargets: [TempTarget]
    @Binding var carbs: [CarbsEntry]
    @Binding var timerDate: Date
    @Binding var units: GlucoseUnits
    @Binding var smooth: Bool
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var screenHours: Int16
    @Binding var displayXgridLines: Bool
    @Binding var displayYgridLines: Bool
    @Binding var thresholdLines: Bool

//    // MARK: STATEs
//
//    @State private var glucoseDots: [CGRect] = []
//    @State private var glucoseYRange: Range<CGFloat> = 0 ..< 0
    @State var didAppearTrigger = false
    @State private var glucoseDots: [CGRect] = []
    @State private var manualGlucoseDots: [CGRect] = []
    @State private var announcementDots: [AnnouncementDot] = []
    @State private var announcementPath = Path()
    @State private var manualGlucoseDotsCenter: [CGRect] = []
    @State private var unSmoothedGlucoseDots: [CGRect] = []
    @State private var predictionDots: [PredictionType: [CGRect]] = [:]
    @State private var bolusDots: [DotInfo] = []
    @State private var bolusPath = Path()
    @State private var tempBasalPath = Path()
    @State private var regularBasalPath = Path()
    @State private var tempTargetsPath = Path()
    @State private var suspensionsPath = Path()
    @State private var carbsDots: [DotInfo] = []
    @State private var carbsPath = Path()
    @State private var fpuDots: [DotInfo] = []
    @State private var fpuPath = Path()
    @State private var glucoseYRange: GlucoseYRange = (0, 0, 0, 0)
    @State private var offset: CGFloat = 0
    @State private var cachedMaxBasalRate: Decimal?

    private var date24Formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("HH")
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    Chart(glucose) {
                        PointMark(
                            x: .value("Time", $0.dateString),
                            y: .value("Value", $0.value)
                        )
                        .foregroundStyle(Color.green.gradient)
                        .cornerRadius(0)
                    }

                    .frame(height: 350)
                    .chartXAxis {
                        AxisMarks(values: glucose.map(\.dateString)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    Legend()
                }
                .padding()
            }
        }
    }

//    // MARK: GLUCOSE FOR CHART
//
    private func calculateGlucoseDots(fullSize: CGSize) {
        let dots = glucose.map { value -> CGRect in
            let position = glucoseToCoordinate(value, fullSize: fullSize)
            return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
        }

        let range = getGlucoseYRange(fullSize: fullSize)

        DispatchQueue.main.async {
            glucoseYRange = range
            glucoseDots = dots
        }
    }

    private func getGlucoseYRange(fullSize: CGSize) -> GlucoseYRange {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let (minValue, maxValue) = minMaxYValues()
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(minValue) * stepYFraction + yOffset - bottomYPadding
        let minY = fullSize.height - CGFloat(maxValue) * stepYFraction + yOffset - bottomYPadding
        return (minValue: minValue, minY: minY, maxValue: maxValue, maxY: maxY)
    }

    private func glucoseToCoordinate(_ glucoseEntry: BloodGlucose, fullSize: CGSize) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970, fullSize: fullSize)
        let y = glucoseToYCoordinate(glucoseEntry.glucose ?? 0, fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func glucoseToYCoordinate(_ glucoseValue: Int, fullSize: CGSize) -> CGFloat {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let (minValue, maxValue) = minMaxYValues()
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = fullSize.height - CGFloat(glucoseValue) * stepYFraction + yOffset - bottomYPadding
        return y
    }

    private func timeToXCoordinate(_ time: TimeInterval, fullSize: CGSize) -> CGFloat {
        let xOffset = -Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let stepXFraction = fullGlucoseWidth(viewWidth: fullSize.width) / CGFloat(hours.hours.timeInterval)
        let x = CGFloat(time + xOffset) * stepXFraction
        return x
    }

    private func fullGlucoseWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    private func minMaxYValues() -> (min: Int, max: Int) {
        var maxValue = glucose.compactMap(\.glucose).max() ?? Config.maxGlucose
        if let maxPredValue = maxPredValue() {
            maxValue = max(maxValue, maxPredValue)
        }
        if let maxTargetValue = maxTargetValue() {
            maxValue = max(maxValue, maxTargetValue)
        }
        var minValue = glucose.compactMap(\.glucose).min() ?? Config.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        if let minTargetValue = minTargetValue() {
            minValue = min(minValue, minTargetValue)
        }

        if minValue == maxValue {
            minValue = Config.minGlucose
            maxValue = Config.maxGlucose
        }
        // fix the grah y-axis as long as the min and max BG values are within set borders
        if minValue > Config.minGlucose {
            minValue = Config.minGlucose
        }
        if maxValue < Config.maxGlucose {
            maxValue = Config.maxGlucose
        }
        return (min: minValue, max: maxValue)
    }

    private func maxTargetValue() -> Int? {
        tempTargets.map { $0.targetTop ?? 0 }.filter { $0 > 0 }.max().map(Int.init)
    }

    private func minPredValue() -> Int? {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .min()
    }

    private func minTargetValue() -> Int? {
        tempTargets.map { $0.targetBottom ?? 0 }.filter { $0 > 0 }.min().map(Int.init)
    }

    private func maxPredValue() -> Int? {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .max()
    }
}

// MARK: LEGEND PANEL FOR CHART

struct Legend: View {
    var body: some View {
        HStack {
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.green)
            Text("BG")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.insulin)
            Text("IOB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.purple)
            Text("ZT")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.loopYellow)
            Text("COB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.orange)
            Text("UAM")
                .foregroundColor(.secondary)
        }
        .font(.caption2)
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}

// struct BloodGlucose: Identifiable {
//    let id = UUID()
//    let timestamp: Date
//    let value: Int
// }

// struct ViewMonth: Identifiable {
//    let id = UUID()
//    let date: Date
//    let viewCount: Int
// }

// extension Date {
//    static func from(year: Int, month: Int, day: Int) -> Date {
//        let components = DateComponents(year: year, month: month, day: day)
//        return Calendar.current.date(from: components)!
//    }
// }
