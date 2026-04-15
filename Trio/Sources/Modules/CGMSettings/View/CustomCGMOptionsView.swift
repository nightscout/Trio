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

        // Simulator settings
        @State private var centerValue: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_CenterValue")
        @State private var amplitude: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_Amplitude")
        @State private var period: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_Period")
        @State private var noiseAmplitude: Double = UserDefaults.standard.double(forKey: "GlucoseSimulator_NoiseAmplitude")
        @State private var produceStaleValues: Bool = UserDefaults.standard.bool(forKey: "GlucoseSimulator_ProduceStaleValues")

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
                            xDripConfigurationSection
                        } else if cgmCurrent.type == .simulator {
                            simulatorConfigurationSection
                        }

                        if let appURL = cgmCurrent.type.appURL {
                            Section {
                                Button {
                                    UIApplication.shared.open(appURL, options: [:]) { success in
                                        if !success {
                                            self.router.alertMessage
                                                .send(MessageContent(
                                                    content: "Unable to open the app",
                                                    type: .warning
                                                ))
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
                .confirmationDialog("Delete CGM", isPresented: $shouldDisplayDeletionConfirmation) {
                    Button(role: .destructive) {
                        deleteCGM()
                    } label: {
                        Text("Delete \(cgmCurrent.displayName)")
                            .font(.headline)
                            .tint(.red)
                    }
                } message: { Text("Are you sure you want to delete \(cgmCurrent.displayName)?") }
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
                                    self.router.alertMessage
                                        .send(MessageContent(
                                            content: "No URL available",
                                            type: .warning
                                        ))
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
            Section(
                header: Text("Configuration"),
                content: {
                    VStack(alignment: .leading) {
                        if let cgmTransmitterDeviceAddress = UserDefaults.standard
                            .cgmTransmitterDeviceAddress
                        {
                            Text("CGM address :").padding(.top)
                            Text(cgmTransmitterDeviceAddress)
                        } else {
                            Text("CGM is not used as heartbeat.").padding(.top)
                        }

                        HStack(alignment: .center) {
                            Text(
                                "A heartbeat tells Trio to start a loop cycle. This is required for closed loop."
                            )
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(nil)
                            Spacer()
                        }.padding(.vertical)

                        if let link = cgmCurrent.type.externalLink {
                            Button {
                                UIApplication.shared.open(link, options: [:], completionHandler: nil)
                            } label: {
                                HStack {
                                    Text("About this source")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            ).listRowBackground(Color.chart)
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
