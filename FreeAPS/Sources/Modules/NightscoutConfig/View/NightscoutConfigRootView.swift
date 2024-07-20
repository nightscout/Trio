import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
<<<<<<< HEAD
        @State var importAlert: Alert?
        @State var isImportAlertPresented = false
        @State var importedHasRun = false

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        @FetchRequest(
            entity: ImportError.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "date > %@", Date().addingTimeInterval(-1.minutes.timeInterval) as NSDate
            )
        ) var fetchedErrors: FetchedResults<ImportError>

        private var portFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            formatter.usesGroupingSeparator = false
            return formatter
        }
=======
        @State private var importAlert: Alert?
        @State private var isImportAlertPresented = false
        @State private var importedHasRun = false

        @FetchRequest(
            entity: ImportError.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", Date().addingTimeInterval(-1.minutes.timeInterval) as NSDate)
        ) var fetchedErrors: FetchedResults<ImportError>
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133

        var body: some View {
            Form {
                NavigationLink("Connect", destination: NightscoutConnectView(state: state))
                NavigationLink("Upload", destination: NightscoutUploadView(state: state))
                NavigationLink("Fetch and Remote Control", destination: NightscoutFetchView(state: state))

                Section(
                    header: Text("Import Settings from Nightscout"),
                    footer: VStack(alignment: .leading, spacing: 2) {
                        Text(
                            "Importing settings from Nightscout will overwrite these settings in Trio Settings -> Configuration:"
                        )
                        Text(" • ") + Text("DIA (Pump settings)")
                        Text(" • ") + Text("Basal Profile")
                        Text(" • ") + Text("Insulin Sensitivities")
                        Text(" • ") + Text("Carb Ratios")
                        Text(" • ") + Text("Target Glucose")
                    }
                ) {
                    Button("Import settings") {
                        importAlert = Alert(
                            title: Text("Import settings?"),
                            message: Text(
                                "\n" +
                                    NSLocalizedString(
                                        "This will replace some or all of your current pump settings. Are you sure you want to import profile settings from Nightscout?",
                                        comment: "Profile Import Alert"
                                    ) +
                                    "\n"
                            ),
                            primaryButton: .destructive(
                                Text("Yes, Import"),
                                action: {
                                    state.importSettings()
                                    importedHasRun = true
                                }
                            ),
                            secondaryButton: .cancel()
                        )
                        isImportAlertPresented.toggle()
                    }.disabled(state.url.isEmpty || state.connecting)
                        .alert(isPresented: $importedHasRun) {
                            Alert(
                                title: Text((fetchedErrors.first?.error ?? "").count < 4 ? "Settings imported" : "Import Error"),
                                message: Text(
                                    (fetchedErrors.first?.error ?? "").count < 4 ?
                                        NSLocalizedString(
                                            "\nNow please verify all of your new settings thoroughly: \n\n • DIA (Pump settings)\n • Basal Profile\n • Insulin Sensitivities\n • Carb Ratios\n • Target Glucose\n\n in Trio Settings -> Configuration.\n\nBad or invalid profile settings could have disastrous effects.",
                                            comment: "Imported Profiles Alert"
                                        ) :
                                        NSLocalizedString(fetchedErrors.first?.error ?? "", comment: "Import Error")
                                ),
                                primaryButton: .destructive(
                                    Text("OK")
                                ),
                                secondaryButton: .cancel()
                            )
                        }
                }
<<<<<<< HEAD

                Section {
                    Button("Connect") { state.connect() }
                        .disabled(state.url.isEmpty || state.connecting)
                    Button("Delete") { state.delete() }.foregroundColor(.red).disabled(state.connecting)
                }

                Section {
                    Toggle("Upload", isOn: $state.isUploadEnabled)
                    if state.isUploadEnabled {
                        Toggle("Statistics", isOn: $state.uploadStats)
                        HStack(alignment: .top) {
                            Image(systemName: "pencil.circle.fill")
                            VStack {
                                Text(
                                    "This enables uploading of statistics.json to Nightscout, which can be used by the Community Statistics and Demographics Project.\n\nParticipation in Community Statistics is opt-in, and requires separate registration at:\n"
                                )
                                .font(.caption)
                                Text(
                                    "https://iaps-stats.hub.org"
                                )
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            }
                        }
                        .foregroundColor(Color.secondary)
                        Toggle("Glucose", isOn: $state.uploadGlucose)
                    }
                } header: {
                    Text("Allow Uploads")
                }

                Section {
                    Button("Import settings from Nightscout") {
                        importAlert = Alert(
                            title: Text("Import settings?"),
                            message: Text(
                                "\n" +
                                    NSLocalizedString(
                                        "This will replace some or all of your current pump settings. Are you sure you want to import profile settings from Nightscout?",
                                        comment: "Profile Import Alert"
                                    ) +
                                    "\n"
                            ),
                            primaryButton: .destructive(
                                Text("Yes, Import"),
                                action: {
                                    state.importSettings()
                                    importedHasRun = true
                                }
                            ),
                            secondaryButton: .cancel()
                        )
                        isImportAlertPresented.toggle()
                    }.disabled(state.url.isEmpty || state.connecting)

                } header: { Text("Import from Nightscout") }

                    .alert(isPresented: $importedHasRun) {
                        Alert(
                            title: Text((fetchedErrors.first?.error ?? "").count < 4 ? "Settings imported" : "Import Error"),
                            message: Text(
                                (fetchedErrors.first?.error ?? "").count < 4 ?
                                    NSLocalizedString(
                                        "\nNow please verify all of your new settings thoroughly:\n\n* Basal Settings\n * Carb Ratios\n * Glucose Targets\n * Insulin Sensitivities\n * DIA\n\n in iAPS Settings > Configuration.\n\nBad or invalid profile settings could have disatrous effects.",
                                        comment: "Imported Profiles Alert"
                                    ) :
                                    NSLocalizedString(fetchedErrors.first?.error ?? "", comment: "Import Error")
                            ),
                            primaryButton: .destructive(
                                Text("OK")
                            ),
                            secondaryButton: .cancel()
                        )
                    }

                Section {
                    Toggle("Use local glucose server", isOn: $state.useLocalSource)
                    HStack {
                        Text("Port")
                        TextFieldWithToolBar(
                            text: $state.localPort,
                            placeholder: "",
                            keyboardType: .numberPad,
                            numberFormatter: portFormater,
                            allowDecimalSeparator: false
                        )
                    }
                } header: { Text("Local glucose source") }
                Section {
                    Button("Backfill glucose") {
                        Task {
                            await state.backfillGlucose()
                        }
                    }
                    .disabled(state.url.isEmpty || state.connecting || state.backfilling)
                }

                Section {
                    Toggle("Remote control", isOn: $state.allowAnnouncements)
                } header: { Text("Allow Remote control of iAPS") }
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationBarTitle("Nightscout Config")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(isPresented: $isImportAlertPresented) {
                importAlert!
            }
=======
                Section {
                    Button("Backfill glucose") { state.backfillGlucose() }
                        .disabled(state.url.isEmpty || state.connecting || state.backfilling)
                } header: { Text("Backfill glucose from Nightscout")
                }
            }
            .navigationBarTitle("Nightscout Config")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
            .alert(isPresented: $isImportAlertPresented) {
                importAlert!
            }

            .onAppear(perform: configureView)
>>>>>>> 9672da256c317a314acc76d6e4f6e82cc174d133
        }
    }
}
