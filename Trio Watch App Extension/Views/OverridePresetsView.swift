import SwiftUI

struct OverridePresetsView: View {
    let state: WatchState
    let overridePresets: [OverridePresetWatch]
    var onPresetAction: () -> Void // Callback to handle selection of preset, or cancellation, and dismiss the sheet

    private let activePresetGradient = LinearGradient(
        colors: [
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902), // #43BBE9
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961) // #57AAEC
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var sortedPresets: [OverridePresetWatch] {
        overridePresets.sorted { $0.isEnabled && !$1.isEnabled }
    }

    private var activeOverride: OverridePresetWatch? {
        sortedPresets.first { $0.isEnabled }
    }

    var body: some View {
        NavigationView {
            List {
                if let active = activeOverride {
                    Button("Stop \(active.name)") {
                        state.sendCancelOverrideRequest()
                        onPresetAction()
                    }
                    .foregroundColor(.white)
                    .listRowBackground(
                        Color.loopRed
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                }

                if sortedPresets.isEmpty {
                    Text("No Override Presets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sortedPresets, id: \.name) { preset in
                        Button(action: {
                            if !preset.isEnabled {
                                state.sendActivateOverrideRequest(presetName: preset.name)
                            }
                            onPresetAction()
                        }) {
                            HStack {
                                Text(preset.name)
                                    .font(.caption)

                                if preset.isEnabled {
                                    Spacer()
                                    Text("is running")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .listRowBackground(
                            preset.isEnabled ?
                                activePresetGradient
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                : nil
                        )
                        .foregroundColor(preset.isEnabled ? .white : .primary)
                    }
                }
            }
            .navigationTitle("Override Presets")
        }
    }
}
