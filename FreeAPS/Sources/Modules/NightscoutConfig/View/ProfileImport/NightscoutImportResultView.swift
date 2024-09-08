import SwiftUI
import Swinject

struct NightscoutImportResultView: BaseView {
    var resolver: any Swinject.Resolver

    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: String?
    @State private var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @State private var hasVisitedBasalProfileEditor = false
    @State private var hasVisitedISFEditor = false
    @State private var hasVisitedCREditor = false
    @State private var hasVisitedPumpSettingsEditor = false

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

    private var allViewsVisited: Bool {
        hasVisitedBasalProfileEditor &&
            hasVisitedISFEditor &&
            hasVisitedCREditor &&
            hasVisitedPumpSettingsEditor
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Imported Nightscout Data"),
                    content: {
                        Text(
                            "Trio has successfully imported your default Nightscout profile and stored it as therapy settings. "
                        ) +
                            Text("This has replaced your previous therapy settings.").bold().foregroundColor(.accentColor)
                        Text("Please review the following settings:").bold()
                    }
                ).listRowBackground(Color.chart)

                Section {
                    NavigationLink(
                        destination: BasalProfileEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedBasalProfileEditor = true }
                    ) {
                        HStack {
                            Text("Basal Rates")
                            if hasVisitedBasalProfileEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedBasalProfileEditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: ISFEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedISFEditor = true }
                    ) {
                        HStack {
                            Text("Insulin Sensitivities")
                            if hasVisitedISFEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedISFEditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: CarbRatioEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedCREditor = true }
                    ) {
                        HStack {
                            Text("Carb Ratios")
                            if hasVisitedCREditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedCREditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: ReviewInsulinActionView(resolver: resolver, state: state)
                            .onDisappear { hasVisitedPumpSettingsEditor = true }
                    ) {
                        HStack {
                            Text("Duration of Insulin Action (DIA)")
                            if hasVisitedPumpSettingsEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedPumpSettingsEditor ? .secondary : .primary)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Button {
                            state.isImportResultReviewPresented = false
                        } label: {
                            Text("Finish").font(.title3)
                        }
                        .disabled(!allViewsVisited)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                    }
                }.listRowBackground(allViewsVisited ? Color(.systemBlue) : Color(.systemGray4))
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden).background(color)
            .interactiveDismissDisabled(true)
            .screenNavigation(self)
        }
    }
}
