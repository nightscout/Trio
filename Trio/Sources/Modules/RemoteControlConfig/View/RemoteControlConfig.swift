import Combine
import SwiftUI
import Swinject
import UIKit

extension RemoteControlConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var isCopied: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.isTrioRemoteControlEnabled,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Enable Remote Command")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Enable Remote Control"),
                    miniHint: String(localized: "Allow Trio to receive commands from Loop Follow remotely."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "When Remote Control is enabled, you can send boluses, overrides, temporary targets, carbs, and other commands to Trio via push notifications."
                        )
                        Text(
                            "To ensure security, these commands are protected by a shared secret, which must be entered in the Loop Follow app."
                        )
                    },
                    headerText: String(localized: "Trio Remote Control")
                )

                Section(
                    header: Text("Shared Secret"),
                    content: {
                        TextField("Enter Shared Secret", text: $state.sharedSecret)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                            .padding(8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)

                        Button(action: {
                            UIPasteboard.general.string = state.sharedSecret
                            isCopied = true
                        }) {
                            Label("Copy Secret", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .alert(isPresented: $isCopied) {
                            Alert(
                                title: Text("Copied"),
                                message: Text("Shared Secret copied to clipboard"),
                                dismissButton: .default(Text("OK"))
                            )
                        }

                        Button(action: {
                            state.generateNewSharedSecret()
                        }) {
                            Label("Generate Secret", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                ).listRowBackground(Color.chart)
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Remote Control")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
