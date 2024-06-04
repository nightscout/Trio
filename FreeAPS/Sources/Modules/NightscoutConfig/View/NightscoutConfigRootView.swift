import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var importAlert: Alert?
        @State private var isImportAlertPresented = false
        @State private var importedHasRun = false

        @FetchRequest(
            entity: ImportError.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "date > %@", Date().addingTimeInterval(-1.minutes.timeInterval) as NSDate)
        ) var fetchedErrors: FetchedResults<ImportError>

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
        }
    }
}
