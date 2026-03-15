import HealthKit
import SwiftDate
import SwiftUI

struct MainView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @EnvironmentObject var state: WatchStateModel

    @State var isCarbsActive = false
    @State var isTargetsActive = false
    @State var isBolusActive = false
    @State private var pulse = 0
    @State private var steps = 0

    @GestureState var isDetectingLongPress = false
    @State var completedLongPress = false

    @State var completedLongPressOfBG = false
    @GestureState var isDetectingLongPressOfBG = false

    private var healthStore = HKHealthStore()
    let heartRateQuantity = HKUnit(from: "count/min")

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !completedLongPressOfBG {
                if state.timerDate.timeIntervalSince(state.lastUpdate) > 10 {
                    HStack {
                        withAnimation {
                            BlinkingView(count: 5, size: 3)
                                .frame(width: 14, height: 14)
                                .padding(2)
                        }
                        Text("Updating...").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            VStack {
                if !completedLongPressOfBG {
                    header
                    Spacer()
                    buttons
                } else {
                    bigHeader
                }
            }

            if state.isConfirmationViewActive {
                ConfirmationView(success: $state.confirmationSuccess)
                    .background(Rectangle().fill(.black))
            }

            if state.isConfirmationBolusViewActive {
                BolusConfirmationView()
                    .environmentObject(state)
                    .background(Rectangle().fill(.black))
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
        .onReceive(state.timer) { date in
            state.timerDate = date
            state.requestState()
        }
        .onAppear {
            state.requestState()
        }
    }

    var header: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(state.glucose).font(.title)
                        Text(state.trend)
                            .scaledToFill()
                            .minimumScaleFactor(0.5)
                    }
                    Text(state.delta).font(.caption2).foregroundColor(.gray)
                }
                Spacer()

                VStack(spacing: 0) {
                    HStack {
                        Circle().stroke(color, lineWidth: 5).frame(width: 26, height: 26).padding(10)
                    }

                    if state.lastLoopDate != nil {
                        Text(timeString).font(.caption2).foregroundColor(.gray)
                    } else {
                        Text("--").font(.caption2).foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline) {
                Text(iobFormatter.string(from: (state.cob ?? 0) as NSNumber)!)
                    .font(.caption2)
                    .scaledToFill()
                    .foregroundColor(Color.white)
                    .minimumScaleFactor(0.5)
                Text("g").foregroundColor(.loopYellow)
                    .font(.caption2)
                    .scaledToFill()
                    .minimumScaleFactor(0.5)
                Spacer()
                Text(iobFormatter.string(from: (state.iob ?? 0) as NSNumber)!)
                    .font(.caption2)
                    .scaledToFill()
                    .foregroundColor(Color.white)
                    .minimumScaleFactor(0.5)

                Text("U").foregroundColor(.insulin)
                    .font(.caption2)
                    .scaledToFill()
                    .minimumScaleFactor(0.5)

                switch state.displayOnWatch {
                case .HR:
                    Spacer()
                    HStack {
                        if completedLongPress {
                            HStack {
                                Text("❤️" + " \(pulse)")
                                    .fontWeight(.regular)
                                    .font(.custom("activated", size: 20))
                                    .scaledToFill()
                                    .foregroundColor(.white)
                                    .minimumScaleFactor(0.5)
                            }
                            .scaleEffect(isDetectingLongPress ? 3 : 1)
                            .gesture(longPress)

                        } else {
                            HStack {
                                Text("❤️" + " \(pulse)")
                                    .fontWeight(.regular)
                                    .font(.caption2)
                                    .scaledToFill()
                                    .foregroundColor(.white)
                                    .minimumScaleFactor(0.5)
                            }
                            .scaleEffect(isDetectingLongPress ? 3 : 1)
                            .gesture(longPress)
                        }
                    }
                case .BGTarget:
                    if let eventualBG = state.eventualBG.nonEmpty {
                        Spacer()
                        HStack {
                            Text(eventualBG)
                                .font(.caption2)
                                .scaledToFill()
                                .foregroundColor(.secondary)
                                .minimumScaleFactor(0.5)
                        }
                    }
                case .steps:
                    Spacer()
                    HStack {
                        Text("🦶" + " \(steps)")
                            .fontWeight(.regular)
                            .font(.caption2)
                            .scaledToFill()
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                    }
                case .isf:
                    Spacer()
                    let isf: String = state.isf != nil ? "\(state.isf ?? 0)" : "-"
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 12, height: 12)
                            .foregroundColor(.loopGreen)
                        Text("\(isf)")
                            .fontWeight(.regular)
                            .font(.caption2)
                            .scaledToFill()
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                    }
                case .override:
                    Spacer()
                    let override: String = state.override != nil ? state.override! : "-"
                    HStack {
                        Text("👤 \(override)")
                            .fontWeight(.regular)
                            .font(.caption2)
                            .scaledToFill()
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            Spacer()
                .onAppear(perform: start)
        }
        .padding()
        // .scaleEffect(isDetectingLongPressOfBG ? 3 : 1)
        .gesture(longPresBGs)
    }

    var bigHeader: some View {
        VStack(alignment: .center) {
            HStack {
                Text(state.glucose).font(.custom("Big BG", size: 55))
                Text(state.trend != "→" ? state.trend : "")
                    .scaledToFill()
                    .minimumScaleFactor(0.5)
            }.padding(.bottom, 35)

            HStack {
                Circle().stroke(color, lineWidth: 5).frame(width: 20, height: 20).padding(10)
            }
        }
        .gesture(longPresBGs)
    }

    var longPress: some Gesture {
        LongPressGesture(minimumDuration: 1)
            .updating($isDetectingLongPress) { currentState, gestureState,
                _ in
                gestureState = currentState
            }
            .onEnded { _ in
                if completedLongPress {
                    completedLongPress = false
                } else { completedLongPress = true }
            }
    }

    var longPresBGs: some Gesture {
        LongPressGesture(minimumDuration: 1)
            .updating($isDetectingLongPressOfBG) { currentState, gestureState,
                _ in
                gestureState = currentState
            }
            .onEnded { _ in
                if completedLongPressOfBG {
                    completedLongPressOfBG = false
                } else { completedLongPressOfBG = true }
            }
    }

    var buttons: some View {
        HStack(alignment: .center) {
            NavigationLink(isActive: $state.isCarbsViewActive) {
                CarbsView()
                    .environmentObject(state)
            } label: {
                Image("carbs", bundle: nil)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.loopYellow)
            }

            NavigationLink(isActive: $state.isTempTargetViewActive) {
                TempTargetsView()
                    .environmentObject(state)
            } label: {
                VStack {
                    Image("target", bundle: nil)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.loopGreen)
                    if let until = state.tempTargets.compactMap(\.until).first, until > Date() {
                        Text(until, style: .timer)
                            .scaledToFill()
                            .font(.system(size: 8))
                    }
                }
            }

            NavigationLink(isActive: $state.isBolusViewActive) {
                BolusView()
                    .environmentObject(state)
            } label: {
                Image("bolus", bundle: nil)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.insulin)
            }
        }
    }

    func start() {
        autorizeHealthKit()
        startHeartRateQuery(quantityTypeIdentifier: .heartRate)
        startStepsQuery(quantityTypeIdentifier: .stepCount)
    }

    func autorizeHealthKit() {
        let healthKitTypes: Set = [
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!,
            HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)!
        ]
        healthStore.requestAuthorization(toShare: healthKitTypes, read: healthKitTypes) { _, _ in }
    }

    private func startStepsQuery(quantityTypeIdentifier _: HKQuantityTypeIdentifier) {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        var interval = DateComponents()
        interval.day = 1
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: nil,
            options: [.cumulativeSum],
            anchorDate: startOfDay,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, result, _ in
            var resultCount = 0.0
            guard let result = result else {
                self.steps = 0
                return
            }
            result.enumerateStatistics(from: startOfDay, to: now) { statistics, _ in

                if let sum = statistics.sumQuantity() {
                    // Get steps (they are of double type)
                    resultCount = sum.doubleValue(for: HKUnit.count())
                } // end if
                // Return
                self.steps = Int(resultCount)
            }
        }

        query.statisticsUpdateHandler = {
            _, statistics, _, _ in

            // If new statistics are available
            if let sum = statistics?.sumQuantity() {
                let resultCount = sum.doubleValue(for: HKUnit.count())
                // Return
                self.steps = Int(resultCount)
            } // end if
        }
        healthStore.execute(query)
    }

    private func startHeartRateQuery(quantityTypeIdentifier: HKQuantityTypeIdentifier) {
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
        let updateHandler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            _, samples, _, _, _ in
            guard let samples = samples as? [HKQuantitySample] else {
                return
            }
            self.process(samples, type: quantityTypeIdentifier)
        }
        let query = HKAnchoredObjectQuery(
            type: HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier)!,
            predicate: devicePredicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: updateHandler
        )
        query.updateHandler = updateHandler
        healthStore.execute(query)
    }

    private func process(_ samples: [HKQuantitySample], type: HKQuantityTypeIdentifier) {
        var lastHeartRate = 0.0
        for sample in samples {
            if type == .heartRate {
                lastHeartRate = sample.quantity.doubleValue(for: heartRateQuantity)
            }
            pulse = Int(lastHeartRate)
        }
    }

    private var iobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter
    }

    private var timeString: String {
        let minAgo = Int((Date().timeIntervalSince(state.lastLoopDate ?? .distantPast) - Config.lag) / 60) + 1
        if minAgo > 1440 {
            return "--"
        }
        return "\(minAgo) " + NSLocalizedString("min", comment: "Minutes ago since last loop")
    }

    private var color: Color {
        guard let lastLoopDate = state.lastLoopDate else {
            return .loopGray
        }
        let delta = Date().timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = WatchStateModel()

        state.glucose = "15,8"
        state.delta = "+888"
        state.iob = 100.38
        state.cob = 112.123
        state.lastLoopDate = Date().addingTimeInterval(-200)
        state
            .tempTargets =
            [TempTargetWatchPreset(name: "Test", id: "test", description: "", until: Date().addingTimeInterval(3600 * 3))]

        return Group {
            MainView()
            MainView().previewDevice("Apple Watch Series 5 - 40mm")
            MainView().previewDevice("Apple Watch Series 3 - 38mm")
        }.environmentObject(state)
    }
}
