import Foundation

import SwiftUI
import Swinject

struct ReviewInsulinActionView: BaseView {
    var resolver: any Swinject.Resolver

    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: String?
    @State private var hintLabel: String?
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

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $state.importedInsulinActionCurve,
                booleanValue: $booleanPlaceholder,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0
                        hintLabel = "Duration of Insulin Action"
                    }
                ),
                units: state.units,
                type: .decimal("dia"),
                label: "Duration of Insulin Action",
                miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                verboseHint: "Duration of Insulin Action… bla bla bla",
                headerText: "Review imported DIA"
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
        .navigationTitle("Duration of Insulin Action")
        .navigationBarTitleDisplayMode(.automatic)
        .onDisappear {
            state.saveReviewedInsulinAction()
        }
    }
}
