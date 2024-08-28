import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State var importAlert: Alert?
        @State var isImportAlertPresented = false
        @State var importedHasRun = false
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

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

        var body: some View {
            ZStack {
                Form {
                    Section(
                        header: Text("Nightscout Integration"),
                        content: {
                            NavigationLink("Connect", destination: NightscoutConnectView(state: state))
                            NavigationLink("Upload", destination: NightscoutUploadView(state: state))
                            NavigationLink("Fetch & Remote Control", destination: NightscoutFetchView(state: state))
                        }
                    ).listRowBackground(Color.chart)

                    Section {
                        VStack {
                            Button {
                                importAlert = Alert(
                                    title: Text("Import Therapy Settings?"),
                                    message: Text(
                                        NSLocalizedString(
                                            "This will replace some or all of your current therapy settings. Are you sure you want to import profile settings from Nightscout?",
                                            comment: "Nightscout Settings Import Alert"
                                        )
                                    ),
                                    primaryButton: .default(
                                        Text("Yes, Import!"),
                                        action: {
                                            Task {
                                                await state.importSettings()
                                            }
                                        }
                                    ),
                                    secondaryButton: .cancel()
                                )
                                isImportAlertPresented = true
                            } label: {
                                Text("Import Settings")
                                    .font(.title3) }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(.bordered)
                                .disabled(state.url.isEmpty || state.connecting)

                            HStack(alignment: .top) {
                                Text(
                                    "You can import therapy settings from Nightscout. See hint for more information which settings will be overwritten."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = "Import Settings from Nightscout"
                                        selectedVerboseHint =
                                            "Importing settings from Nightscout will overwrite the following Trio therapy settings: \n • DIA (Pump settings) \n • Basal Profile \n • Insulin Sensitivities \n • Carb Ratios \n • Target Glucose"
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle")
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.vertical)
                    }.listRowBackground(Color.chart)

                    Section(
                        content:
                        {
                            VStack {
                                Button {
                                    Task {
                                        await state.backfillGlucose()
                                    }
                                } label: {
                                    Text("Backfill Glucose")
                                        .font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                                    .disabled(state.url.isEmpty || state.connecting || state.backfilling)

                                HStack(alignment: .top) {
                                    Text(
                                        "You can backfill missing glucose data from Nightscout."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = "Backfill Glucose from Nightscout"
                                            selectedVerboseHint =
                                                "Explanation… limitation… etc."
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.vertical)
                        }
                    ).listRowBackground(Color.chart)
                }.blur(radius: state.importStatus == .running ? 5 : 0)

                if state.importStatus == .running {
                    CustomProgressView(text: "Importing Profile...")
                }
                //            .alert(isPresented: $importedHasRun) {
                //                Alert(
                //                    title: Text(
                //                        (fetchedErrors.first?.error ?? "")
                //                            .count < 4 ? "Settings imported" : "Import Error"
                //                    ),
                //                    message: Text(
                //                        (fetchedErrors.first?.error ?? "").count < 4 ?
                //                            NSLocalizedString(
                //                                "\nNow please verify all of your new settings thoroughly: \n\n • DIA (Pump settings)\n • Basal Rates\n • Insulin Sensitivities\n • Carb Ratios\n • Target Glucose\n\n in Trio Settings -> Configuration.\n\nBad or invalid profile settings could have disastrous effects.",
                //                                comment: "Imported Profiles Alert"
                //                            ) :
                //                            NSLocalizedString(
                //                                fetchedErrors.first?.error ?? "",
                //                                comment: "Import Error"
                //                            )
                //                    ),
                //                    primaryButton: .destructive(
                //                        Text("OK")
                //                    ),
                //                    secondaryButton: .cancel()
                //                )
                //            }
            }
            .fullScreenCover(isPresented: $state.isImportResultReviewPresented, content: {
                NightscoutImportResultView(resolver: resolver, state: state)
            })
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .navigationBarTitle("Nightscout")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(isPresented: $isImportAlertPresented) {
                importAlert!
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
        }
    }
}
