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

    @State private var shouldDisplayHintFont: Bool = false
    @State private var hintDetent = PresentationDetent.large

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
            } header: {
                Text("Preview")
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

                hintRow
            } header: {
                Text("Glucose Reading Font")
            }.listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .sheet(isPresented: $shouldDisplayHintFont) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHintFont,
                hintLabel: String(localized: "Glucose Reading Font"),
                hintText: AnyView(fontHintText),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Widget Configuration")
        .navigationBarTitleDisplayMode(.automatic)
    }

    /// Mirrors the layout of the Simple Lock Screen Live Activity, showing the real current reading so the preview
    /// matches what the Lock Screen widget displays right now.
    private var previewCard: some View {
        HStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(previewGlucoseText)
                Text(previewDirectionSymbol)
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
        .padding(.horizontal, 14)
        .padding(.vertical, selectedStyle.fontSize.verticalPadding ?? 14)
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
        guard let glucose = state.currentGlucose else { return "--" }
        return LiveActivityAttributes.ContentState.formatGlucose(glucose, units: state.units, forceSign: false)
    }

    private var previewDirectionSymbol: String {
        state.currentDirection?.symbol ?? ""
    }

    private var previewDeltaText: String {
        guard let delta = state.currentDelta else { return "" }
        return LiveActivityAttributes.ContentState.formatGlucose(delta, units: state.units, forceSign: true)
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
        guard state.glucoseColorScheme != .staticColor, let glucose = state.currentGlucose else { return .primary }

        let isMgdL = state.units == .mgdL

        // Mirrors LiveActivityView: the dynamic scheme spreads its color shades between hard-coded bounds
        // rather than the user's own low and high thresholds.
        let hardCodedLow = isMgdL ? Decimal(55) : 55.asMmolL
        let hardCodedHigh = isMgdL ? Decimal(220) : 220.asMmolL

        return Trio.getDynamicGlucoseColor(
            glucoseValue: isMgdL ? Decimal(glucose) : glucose.asMmolL,
            highGlucoseColorValue: hardCodedHigh,
            lowGlucoseColorValue: hardCodedLow,
            targetGlucose: isMgdL ? Decimal(100) : 100.asMmolL,
            glucoseColorScheme: state.glucoseColorScheme
        )
    }

    /// Verbose help shown for the Glucose Reading Font section.
    private var fontHintText: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: Default typeface, Large").bold()
            Text(
                "Changes the typeface and size of the current glucose reading and its trend arrow on the Simple Lock Screen widget. The delta and the time of the last reading are not affected."
            )
            Text(
                "Sizes follow your iPhone's text size setting, so the reading keeps scaling if you change the text size in iOS Settings."
            )
        }
    }

    /// Mini hint row matching `SettingInputSection`'s, for the Glucose Reading Font section.
    private var hintRow: some View {
        HStack(alignment: .center) {
            Text("Set the typeface and size of the glucose reading.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(nil)
            Spacer()
            Button(action: { shouldDisplayHintFont.toggle() }) {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(BorderlessButtonStyle())
            .accessibilityLabel(Text("More information about Glucose Reading Font"))
        }.padding(.vertical)
    }
}
