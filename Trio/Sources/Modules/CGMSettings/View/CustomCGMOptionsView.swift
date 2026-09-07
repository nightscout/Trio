import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension CGMSettings {
    struct CustomCGMOptionsView: BaseView {
        let resolver: Resolver
        @ObservedObject var state: CGMSettings.StateModel
        let cgmCurrent: CGMModel
        let deleteCGM: () -> Void

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.presentationMode) var presentationMode

        @State private var shouldDisplayDeletionConfirmation: Bool = false
        // The heartbeat address is useful for troubleshooting but too long to keep in the main configuration list.
        @State private var shouldDisplayCGMAddress: Bool = false

        // Simulator settings
        @State private var centerValue: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_CenterValue")
        @State private var amplitude: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_Amplitude")
        @State private var period: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_Period")
        @State private var noiseAmplitude: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_NoiseAmplitude")
        @State private var produceStaleValues: Bool = UserDefaults.standard.bool(forKey: "GlucoseSimulator_ProduceStaleValues")

        /// Drives the synthetic `cgmStatusHighlight`
        @State private var simulatedScenarioRaw: String = UserDefaults.standard
            .string(forKey: "GlucoseSimulator.simulatedScenario") ?? SimulatedSensorScenario.runningNormally.rawValue

        /// Routes "open URL failed" warnings through `TrioAlertManager` so
        /// they share the same in-app banner UI as the rest of the alert
        /// pipeline (no more SwiftMessages roundtrip).
        private func warnOpenFailed(identifier: String, title: String, body: String) {
            let content = Alert.Content(
                title: title,
                body: body,
                acknowledgeActionButtonLabel: String(localized: "OK")
            )
            let alert = Alert(
                identifier: Alert.Identifier(managerIdentifier: "trio.cgmSettings", alertIdentifier: identifier),
                foregroundContent: content,
                backgroundContent: content,
                trigger: .immediate,
                interruptionLevel: .active,
                sound: nil
            )
            resolver.resolve(TrioAlertManager.self)?.issueAlert(alert)
        }

        // Initialize state variables with defaults if needed
        private func initializeSimulatorSettings() {
            if centerValue == 0 {
                centerValue = OscillatingGenerator.Defaults.centerValue
            }
            if amplitude == 0 {
                amplitude = OscillatingGenerator.Defaults.amplitude
            }
            if period == 0 {
                period = OscillatingGenerator.Defaults.period
            }
            if noiseAmplitude == 0 {
                noiseAmplitude = OscillatingGenerator.Defaults.noiseAmplitude
            }
            // produceStaleValues is already initialized as false by default
        }

        // Save simulator settings to UserDefaults
        private func saveSimulatorSettings() {
            UserDefaults.standard.set(centerValue, forKey: "GlucoseSimulator_CenterValue")
            UserDefaults.standard.set(amplitude, forKey: "GlucoseSimulator_Amplitude")
            UserDefaults.standard.set(period, forKey: "GlucoseSimulator_Period")
            UserDefaults.standard.set(noiseAmplitude, forKey: "GlucoseSimulator_NoiseAmplitude")
            UserDefaults.standard.set(produceStaleValues, forKey: "GlucoseSimulator_ProduceStaleValues")
        }

        var body: some View {
            NavigationView {
                Form {
                    if cgmCurrent.type != .none {
                        if cgmCurrent.type == .nightscout {
                            nightscoutSection
                        } else if cgmCurrent.type == .xdrip {
                            // Older xDrip4iOS versions simply omit these optional rich-information views.
                            if let producer = state.xDripCGMInformation?.producer {
                                xDripProducerBanner(producer)
                            }
                            xDripConfigurationSection
                            if let information = state.xDripCGMInformation {
                                xDripSensorSection(information)
                                xDripReadingsSection(information)
                            }
                        } else if cgmCurrent.type == .simulator {
                            simulatorConfigurationSection
                        }

                        if let appURL = cgmCurrent.type.appURL {
                            Section {
                                Button {
                                    UIApplication.shared.open(appURL, options: [:]) { success in
                                        if !success {
                                            warnOpenFailed(
                                                identifier: "cgm.app.open.failed",
                                                title: String(localized: "Open failed"),
                                                body: String(localized: "Unable to open the app")
                                            )
                                        }
                                    }
                                }

                                label: {
                                    Label(
                                        "Open \(cgmCurrent.displayName)",
                                        systemImage: "waveform.path.ecg.rectangle"
                                    ).font(.title3)
                                        .padding() }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                            }.listRowBackground(Color.clear)
                        }
                    }
                }
                .navigationTitle(cgmCurrent.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    /// proper positioning should be .leading
                    /// LoopKit submodules set placement to .trailing; we'll keep it "proper" here
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .safeAreaInset(
                    edge: .bottom,
                    spacing: 0
                ) {
                    stickyDeleteButton
                }
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .glassActionSheet(
                    "Delete CGM",
                    message: Text("Are you sure you want to delete \(cgmCurrent.displayName)?"),
                    isPresented: $shouldDisplayDeletionConfirmation,
                    actions: [
                        GlassSheetAction("Delete \(cgmCurrent.displayName)", role: .destructive) {
                            deleteCGM()
                        }
                    ]
                )
                .alert("CGM Address", isPresented: $shouldDisplayCGMAddress) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(state.cgmTransmitterDeviceAddress ?? "")
                }
                .onAppear {
                    if cgmCurrent.type == .simulator {
                        initializeSimulatorSettings()
                    }
                }
            }
        }

        var nightscoutSection: some View {
            Group {
                Section(
                    header: Text("Configuration"),
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CGM is not used as heartbeat.").padding(.top)

                            Text(
                                state.url == nil ?
                                    "To configure your CGM, tap the button below. In the form that opens, enter your Nightscout credentials to connect to your instance." :
                                    "Tap the button below to open your Nightscout instance in your iPhone's default browser."
                            ).font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(nil)
                                .padding(.vertical)
                        }

                        NavigationLink(
                            destination: NightscoutConfig.RootView(resolver: resolver, displayClose: false),
                            label: { Text("Configure Nightscout").foregroundStyle(Color.accentColor) }
                        )
                    }
                ).listRowBackground(Color.chart)

                if let url = state.url {
                    Section {
                        Button {
                            UIApplication.shared.open(url, options: [:]) { success in
                                if !success {
                                    warnOpenFailed(
                                        identifier: "nightscout.open.failed",
                                        title: String(localized: "Open failed"),
                                        body: String(localized: "No URL available")
                                    )
                                }
                            }
                        }
                        label: {
                            Label(
                                "Open Nightscout",
                                systemImage: "waveform.path.ecg.rectangle"
                            ).font(.title3)
                                .padding() }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }

        var xDripConfigurationSection: some View {
            Section {
                if state.cgmTransmitterDeviceAddress != nil {
                    // Keep the row neutral in appearance and reveal the full address only when requested.
                    Button {
                        shouldDisplayCGMAddress = true
                    } label: {
                        HStack {
                            Text("Heartbeat")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Enabled")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("Heartbeat")
                        Spacer()
                        Text("Not used")
                            .foregroundStyle(.secondary)
                    }
                }

                // The producer banner becomes the About link when app identity is available.
                if !hasXDripProducerBanner, let link = cgmCurrent.type.externalLink {
                    Button {
                        UIApplication.shared.open(link, options: [:], completionHandler: nil)
                    } label: {
                        HStack {
                            Text("About xDrip4iOS")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("xDrip4iOS is providing a CGM heartbeat to Trio.")
            }
            .listRowBackground(Color.chart)
        }

        @ViewBuilder private func xDripProducerBanner(_ producer: AppGroupCGMInformation.Producer) -> some View {
            if producer.appName != nil || producer.version != nil {
                Section {
                    if let link = cgmCurrent.type.externalLink {
                        Button {
                            UIApplication.shared.open(link, options: [:], completionHandler: nil)
                        } label: {
                            xDripProducerBannerContent(producer, showsDisclosureIndicator: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        xDripProducerBannerContent(producer, showsDisclosureIndicator: false)
                    }
                }
                .listRowBackground(Color.chart)
            }
        }

        private func xDripProducerBannerContent(
            _ producer: AppGroupCGMInformation.Producer,
            showsDisclosureIndicator: Bool
        ) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "app.badge.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    if let appName = producer.appName {
                        Text(appName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    if let version = producer.version {
                        Text("Version \(version)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if showsDisclosureIndicator {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }

        private var hasXDripProducerBanner: Bool {
            guard let producer = state.xDripCGMInformation?.producer else { return false }
            return producer.appName != nil || producer.version != nil
        }

        @ViewBuilder private func xDripSensorSection(_ information: AppGroupCGMInformation) -> some View {
            let sensor = information.sensor
            let calibration = information.calibration?.state
            let quality = information.latestData?.qualityCode
            let hasSensorInformation = sensor != nil || information.transmitter != nil ||
                calibration == "required" || calibration == "error" ||
                (quality != nil && quality != "reliable")
            if hasSensorInformation {
                Section("Sensor") {
                    optionalValueRow("Status", value: sensor?.state.map(displayCode))
                    optionalValueRow("Sensor", value: sensor?.model ?? sensor?.type.map(displayCode))
                    optionalValueRow("Serial", value: sensor?.serialNumber)
                    optionalDateRow("Started", date: sensor?.startedAt)

                    // Warmup end is useful during warmup but becomes unnecessary once normal readings begin.
                    if sensor?.state == "warmup" {
                        optionalDateRow("Warmup", date: sensor?.warmupEndsAt)
                    }

                    optionalDateRow("Expires", date: sensor?.expiresAt)
                    optionalDateRow("Grace", date: sensor?.graceEndsAt)

                    if let end = information.lifecycleEnd {
                        liveDurationRow("Remaining", target: end)
                    }

                    optionalValueRow("Transmitter", value: information.transmitter?.identifier)
                    if let battery = information.transmitter?.battery {
                        informationRow("Battery", value: batteryDescription(value: battery.value, unit: battery.unit))
                    }

                    // Normal calibration and quality states add noise, so only surface states requiring attention.
                    if calibration == "required" || calibration == "error", let calibration {
                        informationRow("Calibration", value: displayCode(calibration))
                    }

                    if let quality, quality != "reliable" {
                        informationRow("Quality", value: displayCode(quality))
                    }
                }
                .listRowBackground(Color.chart)
            }
        }

        @ViewBuilder private func xDripReadingsSection(_ information: AppGroupCGMInformation) -> some View {
            if let latestReading = information.recentReadings.first {
                Section("Readings") {
                    informationRow("Last Reading", value: latestReading.glucoseMgDl.formatted(withUnits: state.units))
                    relativeDateRow("Timestamp", date: latestReading.date)

                    // Keep the main screen compact while still making every shared recent reading available.
                    NavigationLink {
                        XDripHistoricalReadingsView(
                            readings: information.recentReadings,
                            units: state.units
                        )
                    } label: {
                        HStack {
                            Text("History")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(information.recentReadings.count) readings")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.chart)
            }
        }

        private struct XDripHistoricalReadingsView: View {
            let readings: [AppGroupCGMInformation.RecentReading]
            let units: GlucoseUnits

            var body: some View {
                List(readings) { reading in
                    HStack(alignment: .firstTextBaseline) {
                        Text(reading.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        Spacer()
                        Text(reading.glucoseMgDl.formatted(withUnits: units))
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.chart)
                }
                .navigationTitle("Historical Readings")
                .navigationBarTitleDisplayMode(.inline)
            }
        }

        @ViewBuilder private func optionalValueRow(_ title: LocalizedStringKey, value: String?) -> some View {
            if let value, !value.isEmpty { informationRow(title, value: value) }
        }

        @ViewBuilder private func optionalDateRow(_ title: LocalizedStringKey, date: Date?) -> some View {
            if let date {
                informationRow(title, value: date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            }
        }

        private func relativeDateRow(_ title: LocalizedStringKey, date: Date) -> some View {
            HStack {
                Text(title)
                Spacer()
                // Refresh relative text locally; xDrip4iOS does not need to republish metadata for display updates.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(relativeDescription(for: date, relativeTo: context.date))
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func liveDurationRow(_ title: LocalizedStringKey, target: Date) -> some View {
            HStack {
                Text(title)
                Spacer()
                // Lifecycle countdowns continue to move even when no new glucose arrives.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(duration(from: context.date, to: target))
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func informationRow(_ title: LocalizedStringKey, value: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }

        private func displayCode(_ code: String) -> String {
            // Stable bridge codes are converted to Trio-owned display text only at the UI boundary.
            switch code {
            case "not_started": return String(localized: "Not started")
            case "warmup": return String(localized: "Warming up")
            case "active": return String(localized: "Active")
            case "grace": return String(localized: "Grace period")
            case "expired": return String(localized: "Expired")
            case "stopped": return String(localized: "Stopped")
            case "failed": return String(localized: "Failed")
            case "required": return String(localized: "Required")
            case "error": return String(localized: "Error")
            case "temporary_sensor_issue": return String(localized: "Temporary sensor issue")
            case "excess_noise": return String(localized: "Excess noise")
            case "persistent_noise": return String(localized: "Persistent noise")
            case "flatline": return String(localized: "Flatline")
            case "sensor_error": return String(localized: "Sensor error")
            default: return code.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        private func batteryDescription(value: Double, unit: String?) -> String {
            // Preserve unknown units as a plain numeric value instead of guessing.
            switch unit {
            case "percent": return "\(Int(value.rounded()))%"
            case "millivolts": return "\(Int(value.rounded())) mV"
            default: return value.formatted()
            }
        }

        private func duration(from start: Date, to end: Date) -> String {
            let seconds = max(0, end.timeIntervalSince(start))
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = seconds >= 24 * 60 * 60 ? [.day, .hour] : [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 2
            return formatter.string(from: seconds) ?? String(localized: "Unavailable")
        }

        private func relativeDescription(for date: Date, relativeTo referenceDate: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: referenceDate)
        }

        var simulatorConfigurationSection: some View {
            Group {
                Section(
                    header: Text("Configuration"),
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CGM is not used as heartbeat.").lineLimit(nil)
                                .padding(.top)

                            Text("Glucose trace WILL NOT be affected by any insulin or carb entries.").lineLimit(nil)
                                .bold()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                "The simulator creates a wave-like pattern that mimics natural glucose fluctuations throughout the day."
                            ).lineLimit(nil)

                            Text("Configuration changes will take effect on the next glucose reading.")
                                .padding(.bottom).lineLimit(nil)
                        }.foregroundStyle(Color.secondary).font(.footnote)
                    }
                ).listRowBackground(Color.chart)

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $produceStaleValues) {
                            VStack(alignment: .leading) {
                                Text("Produce Stale Values")
                            }
                        }
                        .padding(.top)
                        .onChange(of: produceStaleValues) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator_ProduceStaleValues")
                        }

                        Text(
                            "When stale values are enabled, the simulator will repeatedly output the last generated glucose value."
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(nil)
                        .padding(.bottom)
                    }
                }.listRowBackground(Color.chart)

                Section(
                    header: Text("Sensor Lifecycle Scenario"),
                    footer: Text(
                        "Drives the outer-ring + tag on the home screen's glucose bobble."
                    )
                ) {
                    Picker("Scenario", selection: $simulatedScenarioRaw) {
                        ForEach(SimulatedSensorScenario.allCases) { scenario in
                            Text(scenario.displayName).tag(scenario.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: simulatedScenarioRaw) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator.simulatedScenario")
                        // Push the change through the active simulator
                        // instance so subjects emit immediately.
                        if let scenario = SimulatedSensorScenario(rawValue: newValue),
                           let sim = resolver.resolve(FetchGlucoseManager.self)?.glucoseSource as? GlucoseSimulatorSource
                        {
                            sim.applySimulatedScenario(scenario)
                        }
                    }

                    if let scenario = SimulatedSensorScenario(rawValue: simulatedScenarioRaw) {
                        Text(scenario.devNotes)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(nil)
                    }
                }.listRowBackground(Color.chart)

                if !produceStaleValues {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Center Value:").bold()

                                Spacer()

                                Text(state.units == .mgdL ? centerValue.description : centerValue.formattedAsMmolL).bold()

                                Text(state.units.rawValue).foregroundStyle(Color.secondary)
                            }.padding(.top)

                            Slider(value: $centerValue, in: 80 ... 200, step: 1)
                                .accentColor(.accentColor)
                                .onChange(of: centerValue) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator_CenterValue")
                                }
                                .padding(.vertical)

                            Text("The average glucose level around which values will oscillate.")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(nil)
                                .padding(.bottom)
                        }
                    }.listRowBackground(Color.chart)

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Amplitude:").bold()

                                Spacer()

                                Text("±")
                                Text(state.units == .mgdL ? amplitude.description : amplitude.formattedAsMmolL).bold()

                                Text(state.units.rawValue).foregroundStyle(Color.secondary)
                            }.padding(.top)

                            Slider(value: $amplitude, in: 10 ... 100, step: 5)
                                .accentColor(.accentColor)
                                .onChange(of: amplitude) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator_Amplitude")
                                }
                                .padding(.vertical)

                            Text(
                                "Range: \(state.units == .mgdL ? (centerValue - amplitude).description : (centerValue - amplitude).formattedAsMmolL)–\(state.units == .mgdL ? (centerValue + amplitude).description : (centerValue + amplitude).formattedAsMmolL) \(state.units.rawValue)"
                            )
                            .bold()
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(nil)

                            Text("The maximum deviation from the center value. Higher values create wider swings.")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(nil)
                                .padding(.bottom)
                        }
                    }.listRowBackground(Color.chart)

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Period:").bold()

                                Spacer()

                                Text(Int(period / 3600).description).bold()

                                Text("hours").foregroundStyle(Color.secondary)
                            }.padding(.top)

                            Slider(value: $period, in: 3600 ... 21600, step: 1800)
                                .accentColor(.accentColor)
                                .onChange(of: period) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator_Period")
                                }
                                .padding(.vertical)

                            Text("The time it takes to complete one full cycle from high to low and back to high.")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(nil)
                                .padding(.bottom)
                        }
                    }.listRowBackground(Color.chart)

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Noise:").bold()

                                Spacer()

                                Text("±")

                                Text(state.units == .mgdL ? noiseAmplitude.description : noiseAmplitude.formattedAsMmolL).bold()

                                Text(state.units.rawValue).foregroundStyle(Color.secondary)
                            }.padding(.top)

                            Slider(value: $noiseAmplitude, in: 0 ... 20, step: 1)
                                .accentColor(.accentColor)
                                .onChange(of: noiseAmplitude) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "GlucoseSimulator_NoiseAmplitude")
                                }
                                .padding(.vertical)

                            Text("Random variation added to each reading to simulate real-world sensor noise.")
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(nil)
                                .padding(.bottom)
                        }
                    }.listRowBackground(Color.chart)
                }

                Section {
                    Button(action: {
                        centerValue = OscillatingGenerator.Defaults.centerValue
                        amplitude = OscillatingGenerator.Defaults.amplitude
                        period = OscillatingGenerator.Defaults.period
                        noiseAmplitude = OscillatingGenerator.Defaults.noiseAmplitude
                        produceStaleValues = OscillatingGenerator.Defaults.produceStaleValues
                        saveSimulatorSettings()
                    }, label: {
                        Text("Reset to Defaults")

                    })
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }.listRowBackground(Color.accentColor)

            }.listSectionSpacing(sectionSpacing)
        }

        var stickyDeleteButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 120)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())
                    .padding(.bottom, -55)

                Button(action: {
                    shouldDisplayDeletionConfirmation.toggle()
                }, label: {
                    Text("Delete CGM")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                })
                    .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                    .background(Color(.systemRed))
                    .tint(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(5)
            }
        }
    }
}
