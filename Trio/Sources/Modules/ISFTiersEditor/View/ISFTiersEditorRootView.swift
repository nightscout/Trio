import SwiftUI
import Swinject

extension ISFTiersEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("ISF Sensitivity Tiers"),
                    footer: Text(
                        "When enabled, your profile ISF is multiplied by the tier value matching your current BG. A multiplier below 100% makes corrections more aggressive (lower ISF); above 100% makes them less aggressive."
                    )
                ) {
                    Toggle("Enable ISF Tiers", isOn: $state.enabled)
                }
                .listRowBackground(Color.chart)

                if state.enabled {
                    Section(
                        header: Text("BG Range Tiers"),
                        footer: Text(
                            "Define BG ranges and the ISF multiplier for each. Ranges are in \(state.units == .mmolL ? "mmol/L" : "mg/dL"). Multiplier 100% = no change, 80% = more aggressive, 120% = less aggressive."
                        )
                    ) {
                        ForEach(Array(state.tiers.enumerated()), id: \.element.id) { index, tier in
                            ISFTierRow(
                                tier: Binding(
                                    get: { state.tiers[index] },
                                    set: { state.tiers[index] = $0 }
                                ),
                                units: state.units
                            )
                        }
                        .onDelete { offsets in
                            state.removeTier(at: offsets)
                        }

                        if state.canAddTier {
                            Button(action: state.addTier) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Add Tier")
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.chart)
                }

                if state.hasChanges {
                    Section {
                        Button(action: state.save) {
                            if state.shouldDisplaySaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Text("Save")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .font(.headline)
                            }
                        }
                        .disabled(state.shouldDisplaySaving)
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("ISF Tiers")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}

private struct ISFTierRow: View {
    @Binding var tier: InsulinSensitivityTier
    let units: GlucoseUnits

    @State private var showingEditor = false

    private func displayBG(_ value: Decimal) -> String {
        if units == .mmolL {
            return "\(value.asMmolL)"
        }
        return "\(value)"
    }

    private var unitsLabel: String {
        units.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showingEditor.toggle() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BG \(displayBG(tier.bgMin)) - \(displayBG(tier.bgMax)) \(unitsLabel)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("ISF multiplier: \(Int(truncating: (tier.isfMultiplier * 100) as NSDecimalNumber))%")
                            .font(.caption)
                            .foregroundColor(multiplierColor)
                    }
                    Spacer()
                    Image(systemName: showingEditor ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showingEditor {
                VStack(spacing: 12) {
                    HStack {
                        Text("BG Min")
                            .frame(width: 60, alignment: .leading)
                        Stepper(
                            value: $tier.bgMin,
                            in: 0 ... max(tier.bgMax - 1, 1),
                            step: units == .mmolL ? 18 : 10
                        ) {
                            Text("\(displayBG(tier.bgMin)) \(unitsLabel)")
                                .monospacedDigit()
                        }
                    }

                    HStack {
                        Text("BG Max")
                            .frame(width: 60, alignment: .leading)
                        Stepper(
                            value: $tier.bgMax,
                            in: (tier.bgMin + 1) ... 400,
                            step: units == .mmolL ? 18 : 10
                        ) {
                            Text("\(displayBG(tier.bgMax)) \(unitsLabel)")
                                .monospacedDigit()
                        }
                    }

                    HStack {
                        Text("ISF %")
                            .frame(width: 60, alignment: .leading)
                        Stepper(
                            value: $tier.isfMultiplier,
                            in: 0.5 ... 1.5,
                            step: 0.05
                        ) {
                            Text("\(Int(truncating: (tier.isfMultiplier * 100) as NSDecimalNumber))%")
                                .monospacedDigit()
                                .foregroundColor(multiplierColor)
                        }
                    }
                }
                .padding(.top, 4)
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var multiplierColor: Color {
        if tier.isfMultiplier < 1.0 {
            return .orange // more aggressive
        } else if tier.isfMultiplier > 1.0 {
            return .blue // less aggressive
        }
        return .secondary // no change
    }
}
