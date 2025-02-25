import Combine
import SwiftUI
import Swinject
import UIKit

extension ShortcutsConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Shortcuts Integration"),
                    content: {
                        Text(
                            "Trio lets you create automations using iOS Shortcuts. Go to the Shortcuts app to create new automations."
                        )
                    }
                ).listRowBackground(Color.chart)

                Section {
                    Button {
                        UIApplication.shared.open(URL(string: "shortcuts://")!)
                    }
                    label: { Label("Open iOS Shortcuts", systemImage: "arrow.triangle.branch").font(.title3).padding() }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowBolusByShortcuts,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Allow Bolusing with Shortcuts")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Allow Bolusing with Shortcuts"),
                    miniHint: String(localized: "Automate boluses using the iOS Shortcuts App."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enabling this setting allows the iOS Shortcuts App to send bolus commands to Trio.")
                            Text(
                                "Disabling this setting will still allow other commands, like Temp Targets, Add Carbs, and Start/End Overrides"
                            )
                        }
                    }
                )
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
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
