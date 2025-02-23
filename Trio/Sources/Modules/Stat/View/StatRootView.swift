import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var paddingAmount: CGFloat? = 10
        @State var headline: Color = .secondary
        @State var days: Double = 0
        @State var pointSize: CGFloat = 3
        @State var conversionFactor = 0.0555

        @ViewBuilder func stats() -> some View {
            ZStack {
                Color.gray.opacity(0.05).ignoresSafeArea(.all)
                let filter = DateFilter()
                switch state.selectedDuration {
                case .Today:
                    StatsView(
                        filter: filter.today,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                case .Day:
                    StatsView(
                        filter: filter.day,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                case .Week:
                    StatsView(
                        filter: filter.week,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                case .Month:
                    StatsView(
                        filter: filter.month,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                case .Total:
                    StatsView(
                        filter: filter.total,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        hbA1cDisplayUnit: state.hbA1cDisplayUnit
                    )
                }
            }
        }

        @ViewBuilder func chart() -> some View {
            switch state.selectedDuration {
            case .Today:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Day:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Week:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Month:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            case .Total:
                ChartsView(
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    hbA1cDisplayUnit: state.hbA1cDisplayUnit,
                    timeInRangeChartStyle: state.timeInRangeChartStyle,
                    glucose: state.glucoseFromPersistence
                )
            }
        }

        var body: some View {
            VStack(alignment: .center) {
                chart().padding(.top, 20)
                Picker("Duration", selection: $state.selectedDuration) {
                    ForEach(Stat.StateModel.Duration.allCases) { duration in
                        Text(duration.rawValue).tag(Optional(duration))
                    }
                }.onChange(of: state.selectedDuration) { _, newValue in
                    state.setupGlucoseArray(for: newValue)
                }
                .pickerStyle(.segmented).background(.cyan.opacity(0.2))
                stats()
            }.background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationBarTitle("Statistics")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading, content: {
                        Button(
                            action: { state.hideModal() },
                            label: {
                                HStack {
                                    Text("Close")
                                }
                            }
                        )
                    })
                }
        }
    }
}
