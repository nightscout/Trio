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
            ScrollView {
                VStack(spacing: 15) {
                    // Main Glucose Display
                    ZStack {
                        TrendShape(rotationDegrees: rotationDegrees)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)

                        VStack(alignment: .center, spacing: 4) {
                            Text(state.currentGlucose)
                                .fontWeight(.semibold)
                                .font(.system(size: 44, design: .rounded))

                            if let delta = state.delta {
                                Text(delta)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 5)

                    // IOB and COB Display
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "drop.fill")
                                    .foregroundStyle(.blue)
                                Text(state.iob ?? "--")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(.orange)
                                Text(state.cob ?? "--")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .scenePadding()
            }
            .tag(0.0)
            .onChange(of: state.trend) { _, newTrend in
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
                            .foregroundStyle(.orange)
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showingBolusSheet = true
                    } label: {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
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
