import Foundation

import SwiftUI
import Swinject

struct ReviewInsulinActionView: BaseView {
    var resolver: any Swinject.Resolver

    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: AnyView?
    @State private var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $state.importedInsulinActionCurve,
                booleanValue: $booleanPlaceholder,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Duration of Insulin Action"
                    }
                ),
                units: state.units,
                type: .decimal("dia"),
                label: "Duration of Insulin Action",
                miniHint: "Number of hours insulin is active in your body.",
                verboseHint:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default: 10 hours").bold()
                    Text("Number of hours insulin will contribute to IOB after dosing.")
                    Text(
                        "Tip: It is better to use a Custom Peak Time than to adjust Duration of Insulin Action (DIA)."
                    )
                },
                headerText: "Review imported DIA"
            )
        }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: "Help"
            )
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .onAppear(perform: configureView)
        .navigationTitle("Duration of Insulin Action")
        .navigationBarTitleDisplayMode(.automatic)
        .onDisappear {
            state.saveReviewedInsulinAction()
        }
    }
}
