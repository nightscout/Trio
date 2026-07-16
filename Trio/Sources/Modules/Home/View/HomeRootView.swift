import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()

        @State var settingsPath = NavigationPath()
        @State var settingsSearchHighlight = SettingsSearchHighlight()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var showCancelConfirmDialog = false
        @State var isConfirmStopOverrideShown = false
        @State var isConfirmStopOverridePresented = false
        @State var isConfirmStopTempTargetShown = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State var showQuickBolusPicker = false
        @State var showQuickBolusNoHistory = false
        @State var showPumpSelection: Bool = false
        @State var showCGMSelection: Bool = false
        @State var showSnoozeSheet: Bool = false
        @State var showManualGlucose: Bool = false
        @State var alarmsSnoozeUntil: Date = .distantPast
        @State var notificationsDisabled = false

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(fetchRequest: TempTargetStored.fetch(
            NSPredicate.lastActiveTempTarget,
            ascending: false,
            fetchLimit: 1
        )) var latestTempTarget: FetchedResults<TempTargetStored>

        var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
            }
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            // the chart is the only flexible zone: it takes what the fixed slots leave over
            let chartHeight = max(
                geo.size.height - HomeLayout.headerHeight - HomeLayout.mealSlotHeight - HomeLayout.bottomZoneHeight,
                HomeLayout.chartMinHeight
            )
            ZStack {
                MainChartView(
                    geo: geo,
                    chartHeight: chartHeight,
                    units: state.units,
                    hours: state.filteredHours,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    screenHours: state.hours,
                    displayXgridLines: state.displayXgridLines,
                    displayYgridLines: state.displayYgridLines,
                    thresholdLines: state.thresholdLines,
                    state: state
                )
            }
            // enforce the zone budget; panes flex within it
            .frame(height: chartHeight)
            .overlay(alignment: .bottomTrailing) {
                chartInfoButton
                    .offset(x: 0, y: -10)
            }
            .overlay(alignment: .topTrailing) {
                // borderless capsule (not a control); centered in the basal
                // pane band so it clears the y-axis labels on every device size
                if let rate = currentBasalRateLabel {
                    Text(rate)
                        .font(.system(size: 14, weight: .semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.insulin)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .frame(height: chartHeight * 0.10)
                        .padding(.trailing, 16)
                }
            }
        }

        private var currentBasalRateLabel: String? {
            guard let rate = state.tempBasals.last?.tempBasal?.rate else { return nil }
            let value = Formatter.decimalFormatterWithTwoFractionDigits.string(from: rate) ?? "\(rate)"
            return value + String(localized: " U/hr", comment: "Unit per hour with space")
        }

        @ViewBuilder private var chartInfoButton: some View {
            Button {
                state.isLegendPresented.toggle()
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .contentShape(Circle())
            .padding(.bottom, 6)
            // same trailing inset as the alarm bell in the meal row
            .padding(.trailing, 16)
        }

        @ViewBuilder func mainViewElements(_ geo: GeometryProxy) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    if let apsManager = state.apsManager, let bluetoothManager = apsManager.bluetoothManager,
                       bluetoothManager.bluetoothAuthorization != .authorized
                    {
                        BluetoothRequiredView()
                    } else {
                        /// right panel with loop status and evBG
                        HStack {
                            Spacer()
                            rightHeaderPanel()
                        }.padding(.trailing, 20)

                        /// glucose bobble
                        glucoseView

                        /// left panel with pump related info
                        HStack {
                            pumpView
                            Spacer()
                        }.padding(.leading, 20)
                    }
                }
                // fixed slot: header state changes never reflow the zones below
                .frame(height: HomeLayout.headerHeight)

                mealPanel().frame(height: HomeLayout.mealSlotHeight)

                mainChart(geo: geo)
            }
            // fill the screen; zones stay top-aligned, chart takes the slack
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // safe-area anchor: the tab bar can never cover the bottom controls
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls()
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onReceive(
                resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
                perform: {
                    if notificationsDisabled != $0 {
                        notificationsDisabled = $0
                        if notificationsDisabled {
                            debug(.default, "notificationsDisabled")
                        }
                    }
                }
            )
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                mainViewElements(geo)
                    // fixed zones bust beyond XXL; cap dashboard type size
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            // no inline text input here; a stale keyboard inset must never shrink the zone budget
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                configureView()
                refreshAlarmsSnooze()
            }
            // UserDefaults changes don't invalidate views; refresh on sheet dismissal
            .onChange(of: showSnoozeSheet) {
                if !showSnoozeSheet { refreshAlarmsSnooze() }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .blur(radius: state.isLoopStatusPresented ? 3 : 0)
            .sheet(isPresented: $state.isLoopStatusPresented) {
                LoopStatusView(state: state)
            }
            .sheet(isPresented: $state.isLegendPresented) {
                ChartLegendView(state: state)
            }
            .sheet(isPresented: $showSnoozeSheet) {
                SnoozeAlertsSheetView(resolver: resolver, isPresented: $showSnoozeSheet)
            }
            .sheet(isPresented: $showManualGlucose) {
                ManualGlucoseEntryView(units: state.units, isPresented: $showManualGlucose) { amount in
                    state.addManualGlucose(amount)
                }
            }
            // PUMP RELATED
            .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                Button("Medtronic") { state.addPump(.minimed) }
                Button("All Omnipod Types") { state.addPump(.omni) }
                Button("Dana(RS/-i)") { state.addPump(.dana) }
                Button("Medtrum Nano") { state.addPump(.medtrum) }
                Button("Pump Simulator") { state.addPump(.simulator) }
            } message: { Text("Select Pump Model") }
            .sheet(isPresented: $state.shouldDisplayPumpSetupSheet) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpConfig.PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else {
                    PumpConfig.PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: state.pumpInitialSettings,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            // CGM RELATED
            .confirmationDialog("CGM Model", isPresented: $showCGMSelection) {
                cgmSelectionButtons
            } message: {
                Text("Select CGM Model")
            }
            .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                switch state.cgmCurrent.type {
                case .enlite,
                     .nightscout,
                     .none,
                     .simulator,
                     .xdrip:
                    CGMSettings.CustomCGMOptionsView(
                        resolver: self.resolver,
                        state: state.cgmStateModel,
                        cgmCurrent: state.cgmCurrent,
                        deleteCGM: state.deleteCGM
                    )
                case .plugin:
                    if let fetchGlucoseManager = state.fetchGlucoseManager,
                       let cgmManager = fetchGlucoseManager.cgmManager,
                       state.cgmCurrent.type == fetchGlucoseManager.cgmGlucoseSourceType,
                       state.cgmCurrent.id == fetchGlucoseManager.cgmGlucosePluginId
                    {
                        CGMSettings.CGMSettingsView(
                            cgmManager: cgmManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSettings.CGMSetupView(
                            CGMType: state.cgmCurrent,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state,
                            pluginCGMManager: self.state.pluginCGMManager
                        )
                    }
                }
            }
        }

        @ViewBuilder func tabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                              state.showCarbsRequiredBadge
                        else {
                            return nil
                        }
                        let carbsRequiredDecimal = Decimal(carbsRequired)
                        if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                            return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
                        }
                        return nil
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { History.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }.tag(1)

                    Spacer()

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Adjustments",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(2)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .environment(settingsSearchHighlight)
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(3)
                }
                .tint(Color.tabBar)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.tabBar)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.showModal(for: .treatmentView)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard state.enableQuickBolus else { return }
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        Task {
                            await state.loadQuickBolusSuggestions()
                            if state.quickBolusHistory.isEmpty {
                                showQuickBolusNoHistory = true
                            } else {
                                showQuickBolusPicker = true
                            }
                        }
                    }
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) {
                    // reset only when leaving Settings; programmatic pushes survive the switch
                    if selectedTab != 3, !settingsPath.isEmpty {
                        settingsPath = NavigationPath()
                    }
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: String(localized: "Updating IOB...", comment: "Progress text when updating IOB"))
                }
            }
            .sheet(isPresented: $showQuickBolusPicker) {
                QuickPickBolusesView(
                    suggestions: state.quickBolusHistory,
                    onEnact: { amount in await state.enactQuickBolus(amount: amount) },
                    isPresented: $showQuickBolusPicker
                )
            }
            .alert(
                String(localized: "No bolus history yet", comment: "Alert title when no quick-pick boluses history exists"),
                isPresented: $showQuickBolusNoHistory
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(
                    localized: "Quick-Pick Boluses learns from your manual boluses over time. Once you've delivered a few boluses, it will suggest amounts based on what you typically enact at this time of day.",
                    comment: "Alert body explaining that quick-pick boluses history is empty"
                ))
            }
        }
    }
}

/// Checks if the device is using a 24-hour time format.
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

/// Converts a duration in minutes to a formatted string (e.g., "1 h 30 m").
func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m)\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    case let (h, 0):
        return "\(h)\u{00A0}" + String(localized: "h", comment: "h")
    default:
        return hours.description + "\u{00A0}" + String(localized: "h", comment: "h") + "\u{00A0}" + minutes
            .description + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    }
}

// Helper function to convert a start and end hour to either 24-hour or AM/PM format
func formatTimeRange(start: String?, end: String?) -> String {
    guard let start = start, let end = end else {
        return ""
    }

    // Check if the format is 24-hour or AM/PM
    if is24HourFormat() {
        // Return the original 24-hour format
        return "\(start)-\(end)"
    } else {
        // Convert to AM/PM format using DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"

        if let startHour = Int(start), let endHour = Int(end) {
            let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
            let endDate = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()

            // Customize the format to "2p" or "2a"
            formatter.dateFormat = "ha"
            let startFormatted = formatter.string(from: startDate).lowercased().replacingOccurrences(of: "m", with: "")
            let endFormatted = formatter.string(from: endDate).lowercased().replacingOccurrences(of: "m", with: "")

            return "\(startFormatted)-\(endFormatted)"
        } else {
            return ""
        }
    }
}
