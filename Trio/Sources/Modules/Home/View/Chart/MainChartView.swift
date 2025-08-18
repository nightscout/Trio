import Charts
import CoreData
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

struct MainChartView: View {
    var geo: GeometryProxy
    var safeAreaSize: CGFloat
    var units: GlucoseUnits
    var hours: Int
    var highGlucose: Decimal
    var lowGlucose: Decimal
    var currentGlucoseTarget: Decimal
    var glucoseColorScheme: GlucoseColorScheme
    var screenHours: Int16
    var displayXgridLines: Bool
    var displayYgridLines: Bool
    var thresholdLines: Bool
    var state: Home.StateModel

    @State var basalProfiles: [BasalProfile] = []
    @State var preparedTempBasals: [(start: Date, end: Date, rate: Double)] = []
    @State var selection: Date? = nil
    @State private var selectionCache: (date: Date, data: (glucose: GlucoseStored?, determination: OrefDetermination?))? = nil

    @State var mainChartHasInitialized = false

    let now = Date.now

    private let context = CoreDataStack.shared.persistentContainer.viewContext

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar

    var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    // Cached selection data for better performance
    private var selectionData: (glucose: GlucoseStored?, determination: OrefDetermination?)? {
        guard let selection = selection else {
            selectionCache = nil
            return nil
        }

        // Use cache if we have recent data for the same time point (within 30 seconds)
        if let cache = selectionCache,
           abs(cache.date.timeIntervalSince(selection)) < 30
        {
            return cache.data
        }

        let range = selection.addingTimeInterval(-150) ... selection.addingTimeInterval(150)

        // Use optimized search for better performance on large datasets
        let glucose = findNearestGlucose(for: selection, in: range)
        let determination = findNearestDetermination(for: selection, in: range)

        let data = (glucose, determination)
        selectionCache = (selection, data)

        return data
    }

    private func findNearestGlucose(for _: Date, in range: ClosedRange<Date>) -> GlucoseStored? {
        // Since glucose data is typically time-ordered, we can optimize this
        state.glucoseFromPersistence.first { glucose in
            guard let date = glucose.date else { return false }
            return range.contains(date)
        }
    }

    private func findNearestDetermination(for _: Date, in range: ClosedRange<Date>) -> OrefDetermination? {
        // Optimized search for determinations
        state.enactedAndNonEnactedDeterminations.first { determination in
            let deliverAt = determination.deliverAt ?? now
            return range.contains(deliverAt)
        }
    }

    private var selectedGlucose: GlucoseStored? {
        selectionData?.glucose
    }

    var selectedCOBValue: OrefDetermination? {
        selectionData?.determination
    }

    var selectedIOBValue: OrefDetermination? {
        selectionData?.determination
    }

    var body: some View {
        VStack {
            ZStack {
                VStack(spacing: 5) {
                    dummyBasalChart
                    staticYAxisChart
                    Spacer()
                    dummyCobChart
                }

                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(spacing: 5) {
                            basalChart
                            mainChart
                            Spacer()
                            cobIobChart
                        }.onChange(of: screenHours) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: state.glucoseFromPersistence.last?.glucose) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                            state.updateStartEndMarkers()
                        }
                        .onChange(of: state.enactedAndNonEnactedDeterminations.first?.deliverAt) {
                            scroller.scrollTo("MainChart", anchor: .trailing)
                        }
                        .onChange(of: units) {
                            // TODO: - Refactor this to only update the Y Axis Scale
                            state.setupGlucoseArray()
                        }
                        .onAppear {
                            if !mainChartHasInitialized {
                                scroller.scrollTo("MainChart", anchor: .trailing)
                                state.updateStartEndMarkers()
                                calculateTempBasalsInBackground()
                                mainChartHasInitialized = true
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Main Chart with selection Popover

extension MainChartView {
    private var mainChart: some View {
        VStack {
            Chart {
                drawStartRuleMark()
                drawEndRuleMark()
                drawCurrentTimeMarker()

                GlucoseTargetsView(
                    targetProfiles: state.targetProfiles
                )

                OverrideView(
                    state: state,
                    overrides: state.overrides,
                    overrideRunStored: state.overrideRunStored,
                    units: state.units,
                    viewContext: context
                )

                TempTargetView(
                    tempTargetStored: state.tempTargetStored,
                    tempTargetRunStored: state.tempTargetRunStored,
                    units: state.units,
                    viewContext: context
                )

                GlucoseChartView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    isSmoothingEnabled: state.isSmoothingEnabled,
                    glucoseColorScheme: state.glucoseColorScheme
                )

                InsulinView(
                    glucoseData: state.glucoseFromPersistence,
                    insulinData: state.insulinFromPersistence,
                    units: state.units
                )

                CarbView(
                    glucoseData: state.glucoseFromPersistence,
                    units: state.units,
                    carbData: state.carbsFromPersistence,
                    fpuData: state.fpusFromPersistence,
                    minValue: units == .mgdL ? state.minYAxisValue : state.minYAxisValue
                        .asMmolL
                )

                ForecastView(
                    preprocessedData: state.preprocessedData,
                    minForecast: state.minForecast,
                    maxForecast: state.maxForecast,
                    units: state.units,
                    maxValue: state.maxYAxisValue,
                    forecastDisplayType: state.forecastDisplayType,
                    lastDeterminationDate: state.determinationsFromPersistence.first?.deliverAt ?? .distantPast
                )

                /// show glucose value when hovering over it
                if let selectedGlucose {
                    SelectionPopoverView(
                        selectedGlucose: selectedGlucose,
                        selectedIOBValue: selectedIOBValue,
                        selectedCOBValue: selectedCOBValue,
                        units: units,
                        highGlucose: highGlucose,
                        lowGlucose: lowGlucose,
                        currentGlucoseTarget: currentGlucoseTarget,
                        glucoseColorScheme: glucoseColorScheme
                    )
                }
            }
            .id("MainChart")
            .frame(
                minHeight: geo.size.height * (0.28 - safeAreaSize)
            )
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .chartXScale(domain: state.startMarker ... state.endMarker)
            .chartXAxis { mainChartXAxis }
            .chartYAxis { mainChartYAxis }
            .chartYAxis(.hidden)
            .chartXSelection(value: $selection)
            .chartYScale(
                domain: units == .mgdL ? state.minYAxisValue ... state.maxYAxisValue : state.minYAxisValue
                    .asMmolL ... state.maxYAxisValue.asMmolL
            )
            .chartLegend(.hidden)
            .chartForegroundStyleScale([
                "iob": Color.insulin,
                "uam": Color.uam,
                "zt": Color.zt,
                "cob": Color.orange
            ])
        }
    }
}
