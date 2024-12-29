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
        @Environment(AppState.self) var appState

        var body: some View {
            ZStack {
                Form {
                    Section(
                        header: Text("Nightscout Integration"),
                        content: {
                            NavigationLink(destination: NightscoutConnectView(state: state), label: {
                                HStack {
                                    Text("Connect")
                                    ZStack {
                                        if state.isConnectedToNS {
                                            Image(systemName: "network")
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption2)
                                                .offset(x: 9, y: 6)
                                        } else {
                                            Image(systemName: "network.slash")
                                        }
                                    }
                                }
                            })
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
                                        "Are you sure you want to import profile settings from Nightscout?\n\nThis will overwrite the following Trio therapy settings: Basal Rates, Insulin Sensitivities, Carb Ratios, Target Glucose, and Duration of Insulin Action."
                                    ),
                                    primaryButton: .default(
                                        Text("Yes, Import!"),
                                        action: {
                                            Task {
                                                await state.importSettings()
                                                // Check the import status and errors after the import process finishes
                                                if state.importStatus == .failed, state.importErrors.isNotEmpty,
                                                   let errorMessage = state.importErrors.first
                                                {
                                                    DispatchQueue.main.async {
                                                        importAlert = Alert(
                                                            title: Text("Import Failed"),
                                                            message: Text(errorMessage.description),
                                                            dismissButton: .default(Text("OK"))
                                                        )
                                                        isImportAlertPresented = true
                                                    }
                                                }
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
                                            "This will overwrite the following Trio therapy settings: \n • Basal Rates \n • Insulin Sensitivities \n • Carb Ratios \n • Target Glucose \n • Duration of Insulin Action"
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
                importAlert ?? Alert(title: Text("Unknown Error"))
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
        }
    }
}
