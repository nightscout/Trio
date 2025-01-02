import Charts
import SwiftUI

struct ContentView: View {
    @State private var state = WatchState()
    @State private var showingCarbsSheet = false
    @State private var showingBolusSheet = false
    @State private var currentPage: Double = 0
    @State private var rotationDegrees: Double = 0.0

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Current glucose and trend
            ZStack {
                TrendShape(rotationDegrees: rotationDegrees)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)

                VStack(alignment: .center) {
                    Text(state.currentGlucose)
                        .fontWeight(.bold)
                        .font(.system(size: 40))

                    if let delta = state.delta {
                        Text(delta)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tag(0.0)
            .onChange(of: state.trend) { newTrend in
                withAnimation {
                    updateRotation(for: newTrend)
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingCarbsSheet = true
                    } label: {
                        Image(systemName: "fork.knife")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingBolusSheet = true
                    } label: {
                        Image(systemName: "drop.fill")
                    }
                }
            }

            // Page 2: Glucose chart
            GlucoseChartView(glucoseValues: state.glucoseValues)
                .tag(1.0)
        }
        .tabViewStyle(.verticalPage)
        .navigationBarHidden(true)
        .digitalCrownRotation($currentPage, from: 0, through: 1, by: 1)
        .sheet(isPresented: $showingCarbsSheet) {
            CarbsInputView(state: state)
        }
        .sheet(isPresented: $showingBolusSheet) {
            BolusInputView(state: state)
        }
    }

    private func updateRotation(for trend: String?) {
        switch trend {
        case "↑",
             "↑↑": // DoubleUp, SingleUp
            rotationDegrees = -90
        case "↗": // FortyFiveUp
            rotationDegrees = -45
        case "→": // Flat
            rotationDegrees = 0
        case "↘": // FortyFiveDown
            rotationDegrees = 45
        case "↓",
             "↓↓": // SingleDown, DoubleDown
            rotationDegrees = 90
        default:
            rotationDegrees = 0
        }
    }
}

struct GlucoseChartView: View {
    let glucoseValues: [(date: Date, glucose: Double)]
    @State private var timeWindow: TimeWindow = .threeHours

    enum TimeWindow: Int {
        case threeHours = 3
        case sixHours = 6
        case twelveHours = 12
        case twentyFourHours = 24

        var next: TimeWindow {
            switch self {
            case .threeHours: return .sixHours
            case .sixHours: return .twelveHours
            case .twelveHours: return .twentyFourHours
            case .twentyFourHours: return .threeHours
            }
        }
    }

    private var filteredValues: [(date: Date, glucose: Double)] {
        let cutoffDate = Date().addingTimeInterval(-Double(timeWindow.rawValue) * 3600)
        return glucoseValues.filter { $0.date > cutoffDate }
    }

    private func glucoseColor(_ value: Double) -> Color {
        if value > 180 {
            return .orange
        } else if value < 70 {
            return .red
        } else {
            return .green
        }
    }

    var body: some View {
        Chart {
            ForEach(filteredValues, id: \.date) { reading in
                LineMark(
                    x: .value("Time", reading.date),
                    y: .value("Glucose", reading.glucose)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Time", reading.date),
                    y: .value("Glucose", reading.glucose)
                )
                .foregroundStyle(glucoseColor(reading.glucose))
                .symbolSize(40) // Kleinere Punkte
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .padding()
        .onTapGesture {
            withAnimation {
                timeWindow = timeWindow.next
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(timeWindow.rawValue)h")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading)
        }
    }
}

// Rest der View-Komponenten bleiben unverändert...
