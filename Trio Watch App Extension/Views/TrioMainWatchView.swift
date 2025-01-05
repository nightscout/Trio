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
    // navigation flag for meal bolus combo
    @State private var continueToBolus = false
    @State private var navigationPath: [NavigationDestinations] = []

    // treatments
    @State private var selectedTreatment: TreatmentOption?

    private var trioBackgroundColor = LinearGradient(
        gradient: Gradient(colors: [Color.bgDarkBlue, Color.bgDarkerDarkBlue]),
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .onAppear {
                state.confirmationProgress = 0 // reset auth progress
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
                        showingTreatmentMenuSheet = true
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
            .fullScreenCover(isPresented: $showingTreatmentMenuSheet) {
                TreatmentMenuView(selectedTreatment: $selectedTreatment) {
                    handleTreatmentSelection()
                }
                .onAppear {
                    continueToBolus = false
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
            .navigationDestination(for: NavigationDestinations.self) { destination in
                switch destination {
                case .acknowledgmentPending:
                    AcknowledgementPendingView(
                        navigationPath: $navigationPath,
                        state: state
                    )
                case .carbInput:
                    CarbsInputView(
                        navigationPath: $navigationPath,
                        state: state,
                        continueToBolus: selectedTreatment == .mealBolusCombo
                    )
                case .bolusInput:
                    BolusInputView(
                        navigationPath: $navigationPath,
                        state: state
                    )
                case .bolusConfirm:
                    BolusConfirmationView(
                        navigationPath: $navigationPath,
                        state: state,
                        bolusAmount: $state.bolusAmount,
                        confirmationProgress: $state.confirmationProgress
                    )
                }
            }
        }
        .blur(radius: state.bolusProgress > 0 && state.bolusProgress < 1.0 && !state.isBolusCanceled ? 3 : 0)
        .overlay {
            if state.bolusProgress > 0 && state.bolusProgress < 1.0 && !state.isBolusCanceled {
                BolusProgressOverlay(state: state)
                    .transition(.opacity)
            }
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
        showingTreatmentMenuSheet = false // Dismiss the sheet

        guard let treatment = selectedTreatment else { return }

        switch treatment {
        case .meal:
            navigationPath.append(NavigationDestinations.carbInput)
        case .bolus:
            navigationPath.append(NavigationDestinations.bolusInput)
        case .mealBolusCombo:
            navigationPath.append(NavigationDestinations.carbInput)
        }
    }
}

#Preview {
    TrioMainWatchView()
}
