import Foundation
import SwiftUI
import Swinject

/// Lets the user tune how the glucose reading is rendered by the Simple Lock Screen Live Activity.
///
/// The counterpart for the Detailed style is `LiveActivityWidgetConfiguration`, which configures which data
/// points that layout shows instead.
struct LiveActivitySimpleWidgetConfiguration: BaseView {
    let resolver: Resolver

    @ObservedObject var state: LiveActivitySettings.StateModel

    /// Sample readings the preview can show, so the effect of the color setting is visible for each band.
    private enum PreviewGlucose: String, CaseIterable, Identifiable {
        case low
        case inRange
        case high

        var id: String { rawValue }

        /// Sample reading in mg/dL.
        var mgdL: Int {
            switch self {
            case .low:
                return 58
            case .inRange:
                return 112
            case .high:
                return 232
            }
        }

        /// Sample 5-minute delta in mg/dL, matching the direction the sample reading is heading.
        var deltaMgdL: Int {
            switch self {
            case .low:
                return -6
            case .inRange:
                return 2
            case .high:
                return 7
            }
        }

        /// Trend arrow matching the sample delta.
        var direction: String {
            switch self {
            case .low:
                return "↘︎"
            case .inRange:
                return "→"
            case .high:
                return "↗︎"
            }
        }

        var displayName: String {
            switch self {
            case .low:
                return String(localized: "Low", comment: "Sample glucose reading for the Live Activity preview")
            case .inRange:
                return String(localized: "In Range", comment: "Sample glucose reading for the Live Activity preview")
            case .high:
                return String(localized: "High", comment: "Sample glucose reading for the Live Activity preview")
            }
        }
    }

    @State private var previewGlucose: PreviewGlucose = .inRange
    @State private var shouldDisplayHintFont: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: AnyView?
    @State private var hintLabel: String?

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    /// Appearance currently selected in this screen, i.e. what the Live Activity will use.
    private var selectedStyle: LiveActivityAttributes.SimpleViewStyle {
        LiveActivityAttributes.SimpleViewStyle(
            fontFace: state.simpleFontFace,
            fontSize: state.simpleFontSize
        )
    }

    var body: some View {
        List {
            Section {
                previewCard

                Picker(selection: $previewGlucose) {
                    ForEach(PreviewGlucose.allCases) { sample in
                        Text(sample.displayName).tag(sample)
                    }
                } label: {
                    Text("Sample Reading")
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            } header: {
                Text("Preview")
            } footer: {
                Text(
                    "This is how the glucose reading will look on your Lock Screen. The sample reading only changes the preview. Reading color follows your Glucose Color Scheme, under Features - User Interface."
                )
            }.listRowBackground(Color.chart)

            Section {
                Picker(selection: $state.simpleFontFace) {
                    ForEach(LiveActivityFontFace.allCases) { face in
                        Text(face.displayName).fontDesign(face.design).tag(face)
                    }
                } label: {
                    Text("Font Face")
                }

                Picker(selection: $state.simpleFontSize) {
                    ForEach(LiveActivityFontSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                } label: {
                    Text("Font Size")
                }

                hintRow(
                    miniHint: String(localized: "Set the typeface and size of the glucose reading."),
                    shouldDisplayHint: $shouldDisplayHintFont,
                    label: String(localized: "Glucose Reading Font"),
                    verboseHint: AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default: Default typeface, Large").bold()
                            Text(
                                "Changes the typeface and size of the current glucose reading and its trend arrow on the Simple Lock Screen widget. The delta and the time of the last reading are not affected."
                            )
                            Text(
                                "Sizes follow your iPhone's text size setting, so the reading keeps scaling if you change the text size in iOS Settings."
                            )
                        }
                    )
                )
            } header: {
                Text("Glucose Reading Font")
            }.listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHintFont) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHintFont,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Widget Configuration")
        .navigationBarTitleDisplayMode(.automatic)
    }

    /// Mirrors the layout of the Simple Lock Screen Live Activity so changes can be judged without locking the phone.
    private var previewCard: some View {
        HStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(previewGlucoseText)
                Text(previewGlucose.direction)
                    .scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                    .padding(.trailing, -5)
            }
            .font(selectedStyle.glucoseFont)
            .foregroundStyle(previewReadingColor)

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(previewDeltaText)
                    .font(.title3)
                    .foregroundStyle(previewReadingColor)

                HStack {
                    Text("Updated:")
                        .foregroundStyle(.secondary)
                    Text(previewTimeText)
                        .bold()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.all, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05))
        )
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Lock Screen widget preview"))
    }

    private var previewGlucoseText: String {
        LiveActivityAttributes.ContentState.formatGlucose(previewGlucose.mgdL, units: state.units, forceSign: false)
    }

    private var previewDeltaText: String {
        LiveActivityAttributes.ContentState.formatGlucose(previewGlucose.deltaMgdL, units: state.units, forceSign: true)
    }

    private var previewTimeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    /// Resolves the preview's reading color the same way the Live Activity does, so the preview stays truthful.
    ///
    /// Coloring is not configurable here: it follows the app-wide Glucose Color Scheme, which leaves the Simple
    /// layout's reading in the default text color while the Static scheme is selected.
    private var previewReadingColor: Color {
        guard state.glucoseColorScheme != .staticColor else { return .primary }

        let isMgdL = state.units == .mgdL

        // Mirrors LiveActivityView: the dynamic scheme spreads its color shades between hard-coded bounds
        // rather than the user's own low and high thresholds.
        let hardCodedLow = isMgdL ? Decimal(55) : 55.asMmolL
        let hardCodedHigh = isMgdL ? Decimal(220) : 220.asMmolL

        return Trio.getDynamicGlucoseColor(
            glucoseValue: isMgdL ? Decimal(previewGlucose.mgdL) : previewGlucose.mgdL.asMmolL,
            highGlucoseColorValue: hardCodedHigh,
            lowGlucoseColorValue: hardCodedLow,
            targetGlucose: isMgdL ? Decimal(100) : 100.asMmolL,
            glucoseColorScheme: state.glucoseColorScheme
        )
    }

    /// Mini hint row matching `SettingInputSection`'s, for sections that build their own controls.
    private func hintRow(
        miniHint: String,
        shouldDisplayHint: Binding<Bool>,
        label: String,
        verboseHint: AnyView
    ) -> some View {
        HStack(alignment: .center) {
            Text(miniHint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(nil)
            Spacer()
            Button(action: {
                hintLabel = label
                selectedVerboseHint = verboseHint
                shouldDisplayHint.wrappedValue.toggle()
            }) {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(BorderlessButtonStyle())
            .accessibilityLabel(Text("More information about \(label)"))
        }.padding(.vertical)
    }
}
