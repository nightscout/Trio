import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var backfillAlert: Alert?
        @State var isBackfillAlertPresented = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            ZStack {
                List {
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
                            NavigationLink("Fetch", destination: NightscoutFetchView(state: state))
                        }
                    ).listRowBackground(Color.chart)

                    Section(
                        content:
                        {
                            VStack {
                                Button {
                                    Task {
                                        await state.backfillGlucose()
                                        if !state.message.isEmpty && state.message.hasPrefix("Error:") {
                                            DispatchQueue.main.async {
                                                backfillAlert = Alert(
                                                    title: Text("Backfill Failed"),
                                                    message: Text(state.message),
                                                    dismissButton: .default(Text("OK"))
                                                )
                                                isBackfillAlertPresented = true
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Backfill Glucose")
                                        .font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)
                                    .disabled(state.url.isEmpty || state.connecting || state.backfilling)

                                HStack(alignment: .center) {
                                    Text(
                                        "Backfill missing glucose data from Nightscout."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(
                                        action: {
                                            hintLabel = String(localized: "Backfill Glucose from Nightscout")
                                            selectedVerboseHint =
                                                AnyView(
                                                    Text(
                                                        "This will backfill 24 hours of glucose data from your connected Nightscout URL to Trio"
                                                    )
                                                )
                                            shouldDisplayHint.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                        .alert(isPresented: $isBackfillAlertPresented) {
                                            backfillAlert ?? Alert(title: Text("Unknown Error"))
                                        }
                                }.padding(.top)
                            }.padding(.vertical)
                        }
                    ).listRowBackground(Color.chart)
                }
                .listSectionSpacing(sectionSpacing)
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .navigationBarTitle("Nightscout")
            .navigationBarTitleDisplayMode(.automatic)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
        }
    }
}
