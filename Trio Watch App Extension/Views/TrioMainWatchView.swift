import Charts
import SwiftUI

struct TrioMainWatchView: View {
    @State private var state = WatchState()
    @State private var showingCarbsSheet = false
    @State private var showingBolusSheet = false
    @State private var showingOverrideSheet = false
    @State private var currentPage: Double = 0
    @State private var rotationDegrees: Double = 0.0

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Current glucose and action buttons
            ScrollView {
                VStack(spacing: 10) {
                    // IOB, COB, lastLoopTime Display
                    VStack(alignment: .leading) {
                        HStack {
                            HStack {
                                Image(systemName: "syringe.fill")
                                    .foregroundStyle(.blue)
                                Text(state.iob ?? "--")
                            }

                            Spacer()

                            HStack {
                                Image(systemName: "fork.knife")
                                    .foregroundStyle(.orange)
                                Text(state.cob ?? "--")
                            }

                            Spacer()

                            // TODO: set loop colors conditionally, not hard coded
                            HStack {
                                Image(systemName: "circle")
                                    .foregroundStyle(.green)
                                Text(state.lastLoopTime ?? "--")
                                    .padding(.trailing)
                            }
                        }
                    }

                    // Main Glucose Display
                    ZStack {
                        TrendShape(rotationDegrees: rotationDegrees)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: rotationDegrees)

                        VStack(alignment: .center) {
                            Text(state.currentGlucose)
                                .fontWeight(.semibold)
                                .font(.system(.title, design: .rounded))

                            if let delta = state.delta {
                                Text(delta)
                                    .fontWeight(.semibold)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.top)
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
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingOverrideSheet = true
                    } label: {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundStyle(Color.primary, Color.purple)
                    }

                    Button {
                        // Perform an action here.
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.black)
                    }
                    .controlSize(.large)
                    .buttonStyle(WatchOSButtonStyle(backgroundGradient: LinearGradient(colors: [
                        Color(red: 0.7215686275, green: 0.3411764706, blue: 1), // #B857FF
                        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569), // #9F6CFA
                        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765), // #7C8BF3
                        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961), // #57AAEC
                        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902), // #43BBE9
                        Color(
                            red: 0.7215686275,
                            green: 0.3411764706,
                            blue: 1
                        ) // #B857FF (repeated for seamless transition)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)))

                    Button {
                        // Perform an action here.
                    } label: {
                        Image(systemName: "target").foregroundStyle(.green.opacity(0.75))
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
        .sheet(isPresented: $showingOverrideSheet) {
            OverridePresetsView(
                overridePresets: state.overridePresets,
                state: state
            )
        }
        .sheet(isPresented: $showingCarbsSheet) {
            CarbsInputView(state: state)
        }
        .sheet(isPresented: $showingBolusSheet) {
            BolusInputView(state: state)
        }
    }

    struct WatchOSButtonStyle: ButtonStyle {
        var backgroundGradient: LinearGradient
        var foregroundColor: Color = .white
        var fontSize: Font = .title2

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(fontSize)
                .fontWeight(.semibold)
                .foregroundColor(foregroundColor)
                .padding()
                .background(
                    backgroundGradient // Custom background color
                        .opacity(configuration.isPressed ? 0.8 : 1.0) // Simulates the press effect
                )
                .clipShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0) // Adds subtle scaling for press
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed) // Smooth animation
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
