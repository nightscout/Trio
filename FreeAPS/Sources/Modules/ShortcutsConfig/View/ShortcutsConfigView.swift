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
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme

        private var color: LinearGradient {
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

        var body: some View {
            Form {
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
                            selectedVerboseHint = $0
                            hintLabel = "Allow Bolusing with Shortcuts"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Allow Bolusing with Shortcuts",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Allow Bolusing with Shortcuts… bla bla bla"
                )
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
