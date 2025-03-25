import CoreData
import SwiftUI

extension Adjustments.RootView {
    @ViewBuilder func tempTargets() -> some View {
        if state.isTempTargetEnabled, state.activeTempTargetName.isNotEmpty {
            currentActiveAdjustment
        }
        if state.scheduledTempTargets.isNotEmpty {
            scheduledTempTargets
        }
        if state.tempTargetPresets.isNotEmpty {
            tempTargetPresets
        } else {
            defaultText
        }
    }

    private var scheduledTempTargets: some View {
        Section {
            ForEach(state.scheduledTempTargets) { tempTarget in
                tempTargetView(for: tempTarget)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        swipeActionsForTempTargets(for: tempTarget)
                    }
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Scheduled Temp Targets")
        }
    }

    private var tempTargetPresets: some View {
        Section {
            ForEach(state.tempTargetPresets) { preset in
                tempTargetView(for: preset, showCheckmark: showTempTargetCheckmark) {
                    enactTempTargetPreset(preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActionsForTempTargets(for: preset)
                }
            }
            .onMove(perform: state.reorderTempTargets)
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $isConfirmDeletePresented,
                titleVisibility: .visible
            ) {
                deleteConfirmationButtons()
            } message: {
                deleteConfirmationMessage
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Temporary Target Presets")
        } footer: {
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text("Swipe left to edit or delete a temporary target preset. Hold, drag and drop to reorder a preset.")
            }
        }
    }

    private func enactTempTargetPreset(_ preset: TempTargetStored) {
        Task {
            let objectID = preset.objectID
            await state.enactTempTargetPreset(withID: objectID)
            selectedTempTargetPresetID = preset.id?.uuidString
            showTempTargetCheckmark = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showTempTargetCheckmark = false
            }
        }
    }

    private func swipeActionsForTempTargets(for tempTarget: TempTargetStored) -> some View {
        Group {
            Button {
                Task {
                    selectedTempTarget = tempTarget
                    isConfirmDeletePresented = true
                }
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .tint(.red)
            }
            Button(action: {
                selectedTempTarget = tempTarget
                state.showTempTargetEditSheet = true
            }, label: {
                Label("Edit", systemImage: "pencil")
                    .tint(.blue)
            })
        }
    }

    private var deleteConfirmationTitle: String {
        let presetName = selectedTempTarget?.name ?? ""
        return String(
            localized: "Delete the Temp Target Preset \"\(presetName)\"?",
            comment: "Delete confirmation title for temporary target presets"
        )
    }

    private func deleteConfirmationButtons() -> some View {
        Group {
            if let itemToDelete = selectedTempTarget {
                Button(
                    state.currentActiveTempTarget == selectedTempTarget ? "Stop and Delete" : "Delete",
                    role: .destructive
                ) {
                    if state.currentActiveTempTarget == selectedTempTarget {
                        Task {
                            await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                        }
                    }
                    Task {
                        await state.invokeTempTargetPresetDeletion(itemToDelete.objectID)
                    }
                    selectedTempTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                selectedTempTarget = nil
            }
        }
    }

    private var deleteConfirmationMessage: Text? {
        if state.currentActiveTempTarget == selectedTempTarget {
            return Text("This Temp Target preset is currently running. Deleting will stop it.")
        }
        return nil
    }

    var stickyStopTempTargetButton: some View {
        ZStack {
            Rectangle()
                .frame(width: UIScreen.main.bounds.width, height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())

            Button(action: {
                Task {
                    // Save cancelled Temp Targets in TempTargetRunStored Entity
                    // Cancel ALL active Temp Targets
                    await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                    // Update View
                    state.updateLatestTempTargetConfiguration()
                }
            }, label: {
                Text("Stop Temp Target")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
            })
                .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                .disabled(!state.isTempTargetEnabled)
                .background(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(5)
        }
    }

    private func tempTargetView(
        for tempTarget: TempTargetStored,
        showCheckmark: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let target = tempTarget.target ?? 100
        let tempTargetValue = Decimal(target as! Double.RawValue)
        let isSelected = tempTarget.id?.uuidString == selectedTempTargetPresetID
        let tempTargetHalfBasal = Decimal(
            tempTarget.halfBasalTarget as? Double
                .RawValue ?? Double(state.settingHalfBasalTarget)
        )
        let percentage = Int(
            state.computeAdjustedPercentage(usingHBT: tempTargetHalfBasal, usingTarget: tempTargetValue)
        )
        let remainingTime = tempTarget.date?.timeIntervalSinceNow ?? 0

        return ZStack(alignment: .trailing) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(tempTarget.name ?? "")
                        Spacer()
                        if remainingTime > 0 {
                            Text("Starts in \(formattedTimeRemaining(remainingTime))")
                                .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                        }
                    }
                    HStack(spacing: 2) {
                        Text(formattedGlucose(glucose: target as Decimal))
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(Formatter.integerFormatter.string(from: (tempTarget.duration ?? 0) as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        if state.isAdjustSensEnabled(usingTarget: tempTargetValue) {
                            Text(", \(percentage)%")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap?()
                }
            }
            if showCheckmark && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.green)
            } else if onTap != nil {
                Image(systemName: "line.3.horizontal")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
