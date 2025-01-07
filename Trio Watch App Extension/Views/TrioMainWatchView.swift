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
//    @State private var navigationPath: [NavigationDestinations] = []
    @State private var navigationPath = NavigationPath()

    // treatments
    @State private var selectedTreatment: TreatmentOption?

    // Active adjustment indicator
    private func isAdjustmentActive<T>(for presets: [T], predicate: (T) -> Bool) -> Bool {
        let sortedPresets = presets.sorted { predicate($0) && !predicate($1) }
        return !sortedPresets.isEmpty && sortedPresets.first(where: predicate) != nil
    }

    private var isTempTargetActive: Bool {
        isAdjustmentActive(for: state.tempTargetPresets) { $0.isEnabled }
    }

    private var isOverrideActive: Bool {
        isAdjustmentActive(for: state.overridePresets) { $0.isEnabled }
    }

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
                // reset input amounts
                state.bolusAmount = 0
                state.carbsAmount = 0
                // reset auth progress
                state.confirmationProgress = 0
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Image(systemName: "syringe.fill")
                            .foregroundStyle(Color.insulin)

                        Text(state.iob ?? "--")
                            .foregroundStyle(.white)
                    }.font(.caption)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Text(state.cob ?? "--")
                            .foregroundStyle(.white)

                        Image(systemName: "fork.knife")
                            .foregroundStyle(Color.orange)
                    }.font(.caption)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingOverrideSheet = true
                    } label: {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundStyle(Color.primary, isOverrideActive ? Color.primary : Color.purple)
                    }.tint(isOverrideActive ? Color.purple : nil)

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
                            .foregroundStyle(isTempTargetActive ? Color.primary : Color.loopGreen.opacity(0.75))
                    }.tint(isTempTargetActive ? Color.loopGreen.opacity(0.75) : nil)
                }
            }
            .fullScreenCover(isPresented: $showingTreatmentMenuSheet) {
                TreatmentMenuView(selectedTreatment: $selectedTreatment) {
                    handleTreatmentSelection()
                }
                .onAppear {
                    // reset the conditional navigation flag when opening
                    continueToBolus = false
                }
            }
            .sheet(isPresented: $showingOverrideSheet) {
                OverridePresetsView(
                    state: state,
                    overridePresets: state.overridePresets
                ) {
                    showingOverrideSheet = false
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }
            }
            .sheet(isPresented: $showingTempTargetSheet) {
                TempTargetPresetsView(
                    state: state,
                    tempTargetPresets: state.tempTargetPresets
                ) {
                    showingTempTargetSheet = false
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }
            }
            .navigationDestination(for: NavigationDestinations.self) { destination in
                switch destination {
                case .acknowledgmentPending:
                    AcknowledgementPendingView(
                        navigationPath: $navigationPath,
                        state: state,
                        shouldNavigateToRoot: $state.shouldNavigateToRoot
                    )
                case .carbsInput:
                    CarbsInputView(
                        navigationPath: $navigationPath,
                        state: state,
                        continueToBolus: continueToBolus
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
            .onChange(of: navigationPath) { _, newPath in
                if newPath.isEmpty {
                    // Reset conditional view navigation when returning to root view
                    continueToBolus = false
                }
            }
        }
        .blur(radius: state.showBolusProgressOverlay ? 3 : 0)
        .overlay {
            if state.showBolusProgressOverlay {
                BolusProgressOverlay(state: state) {
                    state.shouldNavigateToRoot = false
                    navigationPath.append(NavigationDestinations.acknowledgmentPending)
                }.transition(.opacity)
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
            navigationPath.append(NavigationDestinations.carbsInput)
        case .bolus:
            navigationPath.append(NavigationDestinations.bolusInput)
        case .mealBolusCombo:
            continueToBolus = true // Explicitely set subsequent view navigation
            navigationPath.append(NavigationDestinations.carbsInput)
        }
    }
}

#Preview {
    TrioMainWatchView()
}
