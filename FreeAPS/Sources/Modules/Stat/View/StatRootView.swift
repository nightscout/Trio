import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @FetchRequest(
            entity: TDD.entity(),
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)]
        ) var fetchedTDD: FetchedResults<TDD>

        @FetchRequest(
            entity: InsulinDistribution.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedInsulin: FetchedResults<InsulinDistribution>

        @Environment(\.colorScheme) var colorScheme

        @State var paddingAmount: CGFloat? = 10
        @State var headline: Color = .secondary
        @State var days: Double = 0
        @State var pointSize: CGFloat = 3
        @State var conversionFactor = 0.0555

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        @ViewBuilder func stats() -> some View {
            ZStack {
                Color.gray.opacity(0.05).ignoresSafeArea(.all)
                let filter = DateFilter()
                switch state.selectedDuration {
                case .Today:
                    StatsView(
                        filter: filter.today,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Day:
                    StatsView(
                        filter: filter.day,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Week:
                    StatsView(
                        filter: filter.week,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Month:
                    StatsView(
                        filter: filter.month,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                case .Total:
                    StatsView(
                        filter: filter.total,
                        $state.highLimit,
                        $state.lowLimit,
                        $state.units,
                        $state.overrideUnit
                    )
                }
            }
        }

        @ViewBuilder func chart() -> some View {
            switch state.selectedDuration {
            case .Today:
                ChartsView(
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart,
                    glucose: state.glucoseFromPersistence
                )
            case .Day:
                ChartsView(
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart,
                    glucose: state.glucoseFromPersistence
                )
            case .Week:
                ChartsView(
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart,
                    glucose: state.glucoseFromPersistence
                )
            case .Month:
                ChartsView(
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart,
                    glucose: state.glucoseFromPersistence
                )
            case .Total:
                ChartsView(
                    $state.highLimit,
                    $state.lowLimit,
                    $state.units,
                    $state.overrideUnit,
                    $state.layingChart,
                    glucose: state.glucoseFromPersistence
                )
            }
        }

        var body: some View {
            VStack(alignment: .center) {
                chart().padding(.top, 20)
                Picker("Duration", selection: $state.selectedDuration) {
                    ForEach(Stat.StateModel.Duration.allCases) { duration in
                        Text(NSLocalizedString(duration.rawValue, comment: "")).tag(Optional(duration))
                    }
                }.onChange(of: state.selectedDuration) { newValue in
                    state.setupGlucoseArray(for: newValue)
                }
                .pickerStyle(.segmented).background(.cyan.opacity(0.2))
                stats()
            }.background(color)
                .onAppear(perform: configureView)
                .navigationBarTitle("Statistics")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
