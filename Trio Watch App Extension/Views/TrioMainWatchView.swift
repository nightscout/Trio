import Charts
import SwiftUI

struct TrioMainWatchView: View {
    @State private var state = WatchState()

    // misc
    @State private var currentPage: Int = 0
    @State private var rotationDegrees: Double = 0.0
    @State private var showingTempTargetSheet = false

    // view visbility
    @State private var showingTreatmentMenuSheet: Bool = false
    @State private var showingOverrideSheet: Bool = false
    /// navigation flags
    @State private var navigateToCarbsInput = false
    @State private var navigateToBolusInput = false
    @State private var continueToBolus = false

    // treatments
    @State private var selectedTreatment: TreatmentOption?

    private var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            TabView(selection: $currentPage) {
                // Page 1: Current glucose trend in "BG bobble"
                GlucoseTrendView(state: state, rotationDegrees: rotationDegrees)
                    .tag(0)

                // Page 2: Glucose chart
                GlucoseChartView(glucoseValues: state.glucoseValues)
                    .tag(1)
            }
            .background(trioBackgroundColor)
            .tabViewStyle(.verticalPage)
            .digitalCrownRotation($currentPage.doubleBinding(), from: 0, through: 1, by: 1)
            .onChange(of: state.trend) { _, newTrend in
                withAnimation {
                    updateRotation(for: newTrend)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Image(systemName: "syringe.fill")
                            .foregroundStyle(.blue)

                        Text(state.iob ?? "--")
                            .foregroundStyle(.white)
                    }.font(.caption)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Text(state.cob ?? "--")
                            .foregroundStyle(.white)

                        Image(systemName: "fork.knife")
                            .foregroundStyle(.orange)
                    }.font(.caption)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingOverrideSheet = true
                    } label: {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundStyle(Color.primary, Color.purple)
                    }

                    Button {
                        showingTreatmentMenuSheet.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.bgDarkerDarkBlue)
                    }
                    .controlSize(.large)
                    .buttonStyle(WatchOSButtonStyle())

                    Button {
                        showingTempTargetSheet = true
                    } label: {
                        Image(systemName: "target")
                            .foregroundStyle(.green.opacity(0.75))
                    }
                }
            }
            .sheet(isPresented: $showingTreatmentMenuSheet) {
                TreatmentMenuView(selectedTreatment: $selectedTreatment)
                    .onAppear {
                        navigateToCarbsInput = false
                        navigateToBolusInput = false
                        continueToBolus = false
                    }
                    .onDisappear {
                        handleTreatmentSelection()
                    }
            }
            .sheet(isPresented: $showingOverrideSheet) {
                OverridePresetsView(
                    overridePresets: state.overridePresets,
                    state: state
                )
            }
            .sheet(isPresented: $showingTempTargetSheet) {
                TempTargetPresetsView(
                    tempTargetPresets: state.tempTargetPresets,
                    state: state
                )
            }
            .navigationDestination(isPresented: $navigateToCarbsInput) {
                CarbsInputView(state: state, continueToBolus: continueToBolus)
            }
            .navigationDestination(isPresented: $navigateToBolusInput) {
                BolusInputView(state: state)
            }
        }
    }

    struct WatchOSButtonStyle: ButtonStyle {
        var backgroundGradient = LinearGradient(colors: [
            Color(red: 0.721, green: 0.341, blue: 1),
            Color(red: 0.486, green: 0.545, blue: 0.953),
            Color(red: 0.262, green: 0.733, blue: 0.914)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        var foregroundColor: Color = .white
        var fontSize: Font = .title2

        private var is40mm: Bool {
            let size = WKInterfaceDevice.current().screenBounds.size
            return size.height < 225 && size.width < 185
        }

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(fontSize)
                .fontWeight(is40mm ? .medium : .semibold)
                .padding(is40mm ? 6 : 10)
                .background(
                    backgroundGradient.opacity(configuration.isPressed ? 0.8 : 1.0)
                )
                .clipShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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

    private func handleTreatmentSelection() {
        guard let treatment = selectedTreatment else { return }
        switch treatment {
        case .mealBolusCombo:
            navigateToCarbsInput = true
            continueToBolus = true
        case .meal:
            navigateToCarbsInput = true
        case .bolus:
            navigateToBolusInput = true
        }
    }
}

extension Binding where Value == Int {
    func doubleBinding() -> Binding<Double> {
        Binding<Double>(
            get: { Double(self.wrappedValue) },
            set: { self.wrappedValue = Int($0) }
        )
    }
}

extension Color {
    static let bgDarkBlue = Color("Background_DarkBlue")
    static let bgDarkerDarkBlue = Color("Background_DarkerDarkBlue")
}

#Preview {
    TrioMainWatchView()
}
