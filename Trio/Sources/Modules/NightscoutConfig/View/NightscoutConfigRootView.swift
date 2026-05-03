import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        @StateObject var state = StateModel()
        @State var hintDetent = PresentationDetent.large
        @State private var hintPayload: HintPayload?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var backfillAlert: Alert?
        @State var isBackfillAlertPresented = false

        private struct HintPayload: Identifiable {
            let id = UUID()
            let label: String
            let content: AnyView
        }

        private var shouldDisplayHintBinding: Binding<Bool> {
            Binding(
                get: { hintPayload != nil },
                set: { newValue in if !newValue { hintPayload = nil } }
            )
        }

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
                                            hintPayload = HintPayload(
                                                label: String(localized: "Backfill Glucose from Nightscout"),
                                                content: AnyView(
                                                    Text(
                                                        "This will backfill 24 hours of glucose data from your connected Nightscout URL to Trio"
                                                    )
                                                )
                                            )
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
            .sheet(item: $hintPayload) { payload in
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: shouldDisplayHintBinding,
                    hintLabel: payload.label,
                    hintText: payload.content,
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
