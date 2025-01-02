import Charts
import SwiftUI

struct TrioMainWatchView: View {
    @State private var state = WatchState()
    @State private var showingCarbsSheet = false
    @State private var showingBolusSheet = false
    @State private var currentPage: Double = 0
    @State private var rotationDegrees: Double = 0.0

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Current glucose and action buttons
            VStack(spacing: 20) {
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

                HStack(spacing: 20) {
                    Button {
                        showingCarbsSheet = true
                    } label: {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        showingBolusSheet = true
                    } label: {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }
            .tag(0.0)
            .onChange(of: state.trend) { _, newTrend in
                withAnimation {
                    updateRotation(for: newTrend)
                }
            }

            // Page 2: Glucose chart
            GlucoseChartView(glucoseValues: state.glucoseValues)
                .tag(1.0)
        }
        .tabViewStyle(.verticalPage)
        .digitalCrownRotation($currentPage, from: 0, through: 1, by: 1)
        .sheet(isPresented: $showingCarbsSheet) {
            CarbsInputView(state: state)
        }
        .sheet(isPresented: $showingBolusSheet) {
            BolusInputView(state: state)
        }
    }

    // TODO: - Refactor this like in CurrentGlucoseView
    private func updateRotation(for trend: String?) {
        switch trend {
        case "DoubleUp",
             "SingleUp":
            rotationDegrees = -90
        case "FortyFiveUp":
            rotationDegrees = -45
        case "Flat":
            rotationDegrees = 0
        case "FortyFiveDown":
            rotationDegrees = 45
        case "DoubleDown",
             "SingleDown":
            rotationDegrees = 90
        default:
            rotationDegrees = 0
        }
    }
}

#Preview {
    TrioMainWatchView()
}
