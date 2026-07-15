import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

struct TimePicker: Identifiable {
    var active: Bool
    let hours: Int16
    var id: String { hours.description }
}

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
        @State var notificationsDisabled = false
        @State var timeButtons: [TimePicker] = [
            TimePicker(active: false, hours: 4),
            TimePicker(active: false, hours: 6),
            TimePicker(active: false, hours: 12),
            TimePicker(active: false, hours: 24)
        ]

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

        private var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
            }
        }

        // Returns the scheduled basal rate for the current time based on the saved basal scheduled.
        // Would be better if in the future BasalDeliveryStatus could be updated to include this info.

        var timeIntervalButtons: some View {
            let buttonColor = (colorScheme == .dark ? Color.white : Color.black).opacity(0.8)

            return HStack(alignment: .center) {
                ForEach(timeButtons) { button in
                    Button(action: {
                        state.hours = button.hours
                    }) {
                        Group {
                            if button.active {
                                Text(
                                    button.hours.description + "\u{00A0}" +
                                        String(localized: "h", comment: "h")
                                )
                            } else {
                                Text(button.hours.description)
                            }
                        }
                        .font(.footnote)
                        .fontWeight(button.active ? .semibold : .regular)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .foregroundColor(
                            button
                                .active ? (colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white) : buttonColor
                        )
                        .background(button.active ? buttonColor.opacity(colorScheme == .dark ? 1 : 0.8) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(button.active ? buttonColor.opacity(0.4) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }

        var statsIconString: String {
            if #available(iOS 18, *) {
                return "chart.line.text.clipboard"
            } else {
                return "list.clipboard"
            }
        }

        @ViewBuilder private func tappableButton(
            buttonColor: Color,
            label: String,
            iconString: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: {
                action()
            }) {
                HStack {
                    Image(systemName: iconString)
                    Text(label)
                }
                .font(.footnote)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .foregroundStyle(buttonColor)
                .overlay(
                    Capsule()
                        .stroke(buttonColor.opacity(0.4), lineWidth: 2)
                )
            }
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            // the chart is the only flexible zone: it takes what the fixed slots leave over
            let chartHeight = max(
                geo.size.height - HomeLayout.headerHeight - HomeLayout.mealSlotHeight - HomeLayout
                    .timeButtonsRowHeight - HomeLayout.bottomZoneHeight,
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
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
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
                // layout-inert warnings; the multi-use panel absorbs these later
                .overlay(alignment: .top) {
                    VStack(spacing: 4) {
                        if notificationsDisabled {
                            alertSafetyNotificationsView(geo: geo)
                        }
                        if let badgeImage = state.pumpStatusBadgeImage, let badgeColor = state.pumpStatusBadgeColor {
                            pumpTimezoneView(badgeImage, badgeColor)
                                .padding(.horizontal, 20)
                        }
                    }
                }

                mealPanel().frame(height: HomeLayout.mealSlotHeight)

                mainChart(geo: geo)

                HStack {
                    tappableButton(
                        buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
                        label: String(localized: "Stats", comment: "Stats icon in main view"),
                        iconString: statsIconString,
                        action: { state.showModal(for: .statistics) }
                    )

                    Spacer()

                    timeIntervalButtons

                    Spacer()

                    tappableButton(
                        buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
                        label: String(localized: "Info", comment: "Info icon in main view"),
                        iconString: "info",
                        action: { state.isLegendPresented.toggle() }
                    )
                }
                .padding(.horizontal)
                .frame(height: HomeLayout.timeButtonsRowHeight)
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
            .onChange(of: state.hours) {
                highlightButtons()
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
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
                    if !settingsPath.isEmpty {
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
