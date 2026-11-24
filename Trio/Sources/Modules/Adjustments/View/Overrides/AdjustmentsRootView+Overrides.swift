import CoreData
import SwiftUI

extension Adjustments.RootView {
    @ViewBuilder func overrides() -> some View {
        if state.isOverrideEnabled, state.activeOverrideName.isNotEmpty {
            currentActiveAdjustment
        }
        if state.overridePresets.isNotEmpty {
            overridePresets
        } else {
            defaultText
        }
    }

    var overridePresets: some View {
        Section {
            // objectID instead of the optional `id` field, which can be nil/duplicated and
            // crashes SwiftUI's ForEach.
            ForEach(state.overridePresets, id: \.objectID) { preset in
                overridesView(for: preset, showCheckMark: showOverrideCheckmark) {
                    requestOverridePresetActivation(preset)
                }
                .contextMenu {
                    actionButtonsForOverrides(for: preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    actionButtonsForOverrides(for: preset, deleteRole: nil)
                }
            }
            .onMove(perform: state.reorderOverride)
            .listRowBackground(Color.chart)
        } header: {
            Text("Override Presets")
        } footer: {
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text("Swipe left to edit or delete an override preset. Hold, drag and drop to reorder a preset.")
            }
        }
    }

    func overrideDeleteConfirmation(_ content: some View) -> some View {
        let target = overrideToDelete
        let isRunning = target != nil && state.currentActiveOverride == target

        return content.glassActionSheet(
            "Delete the Override Preset \"\(target?.name ?? "")\"?",
            message: isRunning ? Text("This override preset is currently running. Deleting will stop it.") : nil,
            isPresented: Binding(
                get: { overrideToDelete != nil },
                set: { if !$0 { overrideToDelete = nil } }
            ),
            actions: [
                GlassSheetAction(
                    isRunning ? "Stop and Delete" : "Delete",
                    role: .destructive
                ) {
                    guard let target else { return }
                    if isRunning {
                        Task {
                            await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                        }
                    }
                    Task {
                        await state.invokeOverridePresetDeletion(target.objectID)
                    }
                }
            ]
        )
    }

    private func requestOverridePresetActivation(_ preset: OverrideStored) {
        let activation = PendingPresetActivation.override(
            objectID: preset.objectID,
            presetID: preset.id,
            name: preset.name ?? ""
        )

        requestPresetActivation(activation)
    }

    func actionButtonsForOverrides(
        for preset: OverrideStored,
        deleteRole: ButtonRole? = .destructive
    ) -> some View {
        Group {
            Button(role: deleteRole) {
                overrideToDelete = preset
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            .tint(.red)
            Button {
                // Set the selected Override to the chosen Preset and pass it to the Edit Sheet
                selectedOverride = preset
                state.showOverrideEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    var overrideLabelDivider: some View {
        Divider()
            .frame(width: 1, height: 20)
    }

    var stickyStopOverrideButton: some View {
        ZStack {
            Rectangle()
                .frame(height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())
                .ignoresSafeArea(edges: .horizontal)

            Button(action: {
                showCancelOverrideConfirmDialog = true
            }, label: {
                Text("Stop Override")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
            })
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.9 }
                .frame(height: 40)
                .disabled(!state.isOverrideEnabled)
                .background(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                .padding(5)
        }
    }

    @ViewBuilder func overridesView(
        for preset: OverrideStored,
        showCheckMark _: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let isSelected = preset.id == selectedOverridePresetID
        let name = preset.name ?? ""
        let indefinite = preset.indefinite
        let duration = preset.duration?.decimalValue ?? Decimal(0)
        let percentage = preset.percentage
        let smbMinutes = preset.smbMinutes?.decimalValue ?? Decimal(0)
        let uamMinutes = preset.uamMinutes?.decimalValue ?? Decimal(0)

        let target: String = {
            guard let targetValue = preset.target, targetValue != 0 else { return "" }
            return targetValue.decimalValue.formatted(for: state.units)
        }()

        let targetString = target.isEmpty ? "" : "\(target) \(state.units.rawValue)"

        let durationLabel: (text: String, spoken: String) = {
            guard !indefinite else { return ("", "") }
            let span = Duration(minutes: duration)
            return (span.formattedTimeSpan(), span.formattedSpokenTimeSpan())
        }()

        let maxSmbMins: (text: String, spoken: String) = {
            guard smbMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  smbMinutes != state.defaultSmbMinutes else { return ("", "") }
            let span = Duration(minutes: smbMinutes)
            return ("SMB\u{00A0}" + span.formattedTimeSpan(.minutes), "SMB\u{00A0}" + span.formattedSpokenTimeSpan(.minutes))
        }()

        let maxUamMins: (text: String, spoken: String) = {
            guard uamMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  uamMinutes != state.defaultUamMinutes else { return ("", "") }
            let span = Duration(minutes: uamMinutes)
            return ("UAM\u{00A0}" + span.formattedTimeSpan(.minutes), "UAM\u{00A0}" + span.formattedSpokenTimeSpan(.minutes))
        }()

        let isfAndCrString: String = {
            switch (preset.isfAndCr, preset.isf, preset.cr) {
            case (_, true, true),
                 (true, _, _):
                return " ISF/CR"
            case (false, true, false):
                return " ISF"
            case (false, false, true):
                return " CR"
            default:
                return ""
            }
        }()

        let percentageString = percentage == 100 ? "" : (percentage / 100).formatted(.wholePercent) + isfAndCrString

        let otherLabels = [percentageString, targetString, preset.smbOffText]
        let labels = ([durationLabel.text] + otherLabels + [maxSmbMins.text, maxUamMins.text])
            .filter { !$0.isEmpty }
        let spokenLabels = ([durationLabel.spoken] + otherLabels + [maxSmbMins.spoken, maxUamMins.spoken])
            .filter { !$0.isEmpty }

        if !name.isEmpty {
            ZStack(alignment: .trailing) {
                HStack {
                    VStack {
                        HStack {
                            Text(name)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                if label != labels.last { // Add divider between labels
                                    overrideLabelDivider
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
                }
                // show checkmark to indicate if the preset was actually pressed
                if showOverrideCheckmark && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(name))
            .accessibilityValue(Text(spokenLabels.joined(separator: ", ")))
            .accessibilityHint(Text(String(localized: "Double tap to enable this override", comment: "Accessibility hint")))
            .accessibilityAddTraits(showOverrideCheckmark && isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onTap?() }
        }
    }
}
