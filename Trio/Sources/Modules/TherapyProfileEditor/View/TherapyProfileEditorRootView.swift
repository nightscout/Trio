import SwiftUI
import Swinject

extension TherapyProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Form {
                basicInfoSection
                schedulingSection
                copySettingsSection
                therapySettingsSection
                optionsSection
            }
            .navigationTitle(state.name.isEmpty ? "New Profile" : state.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(state.hasChanges)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if state.hasChanges {
                        Button("Cancel") {
                            state.confirmDiscard()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        state.save()
                    }
                    .disabled(!state.canSave)
                    .fontWeight(.semibold)
                }
            }
            .alert("Discard Changes?", isPresented: $state.showDiscardAlert) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    state.discardChanges()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
            .sheet(isPresented: $state.showCopySheet) {
                CopySettingsSheet(state: state)
            }
            .onAppear {
                configureView()
            }
        }

        // MARK: - Sections

        @ViewBuilder
        private var basicInfoSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Profile Name", text: $state.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: state.name) { _, _ in
                            state.validateName()
                        }

                    if let error = state.nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Profile Name")
            }
        }

        @ViewBuilder
        private var schedulingSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    WeekdayPickerView(
                        selectedDays: $state.activeDays,
                        conflictingDays: state.conflictingDays,
                        conflictingDayOwners: state.conflictingDayOwners,
                        showQuickSelect: true
                    )
                }
                .padding(.vertical, 8)
            } header: {
                Text("Active Days")
            } footer: {
                Text("Select which days of the week this profile should be active.")
            }
        }

        @ViewBuilder
        private var copySettingsSection: some View {
            Section {
                Button(action: state.showCopyOptions) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Settings From...")
                    }
                }
            } footer: {
                Text("Copy therapy settings from another profile or from your current active settings.")
            }
        }

        @ViewBuilder
        private var therapySettingsSection: some View {
            Section {
                // Basal Rates
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { state.expandedSection == .basal },
                        set: { _ in state.toggleSection(.basal) }
                    )
                ) {
                    InlineBasalRatesEditor(state: state)
                } label: {
                    settingsRowLabel(
                        title: "Basal Rates",
                        subtitle: basalSummary,
                        systemImage: "waveform.path"
                    )
                }

                // Insulin Sensitivities
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { state.expandedSection == .isf },
                        set: { _ in state.toggleSection(.isf) }
                    )
                ) {
                    InlineISFEditor(state: state)
                } label: {
                    settingsRowLabel(
                        title: "Insulin Sensitivities",
                        subtitle: isfSummary,
                        systemImage: "arrow.down.right"
                    )
                }

                // Carb Ratios
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { state.expandedSection == .carbRatio },
                        set: { _ in state.toggleSection(.carbRatio) }
                    )
                ) {
                    InlineCarbRatioEditor(state: state)
                } label: {
                    settingsRowLabel(
                        title: "Carb Ratios",
                        subtitle: carbRatioSummary,
                        systemImage: "fork.knife"
                    )
                }

                // Glucose Targets
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { state.expandedSection == .targets },
                        set: { _ in state.toggleSection(.targets) }
                    )
                ) {
                    InlineTargetsEditor(state: state)
                } label: {
                    settingsRowLabel(
                        title: "Glucose Targets",
                        subtitle: targetsSummary,
                        systemImage: "target"
                    )
                }
            } header: {
                Text("Therapy Settings")
            } footer: {
                Text("Configure the insulin delivery and glucose management settings for this profile. These settings only apply when this profile is active.")
            }
        }

        @ViewBuilder
        private var optionsSection: some View {
            Section {
                Toggle("Set as Default Profile", isOn: $state.isDefault)
            } header: {
                Text("Options")
            } footer: {
                Text("The default profile is used when no specific profile is scheduled for a day.")
            }
        }

        // MARK: - Helper Views

        @ViewBuilder
        private func settingsRowLabel(title: String, subtitle: String, systemImage: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        // MARK: - Summaries

        private var basalSummary: String {
            let count = state.basalProfile.count
            if count == 0 {
                return "Not configured"
            }
            return "\(count) rate\(count == 1 ? "" : "s")"
        }

        private var isfSummary: String {
            guard let isf = state.insulinSensitivities else {
                return "Not configured"
            }
            let count = isf.sensitivities.count
            return "\(count) value\(count == 1 ? "" : "s")"
        }

        private var carbRatioSummary: String {
            guard let cr = state.carbRatios else {
                return "Not configured"
            }
            let count = cr.schedule.count
            return "\(count) ratio\(count == 1 ? "" : "s")"
        }

        private var targetsSummary: String {
            guard let targets = state.bgTargets else {
                return "Not configured"
            }
            let count = targets.targets.count
            return "\(count) target\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Copy Settings Sheet

private struct CopySettingsSheet: View {
    @ObservedObject var state: TherapyProfileEditor.StateModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if state.hasCurrentActiveSettings {
                    Section {
                        Button(action: {
                            state.copyFromCurrentActiveSettings()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text("Current Active Settings")
                                        .foregroundColor(.primary)
                                    Text("Copy from your pump's current settings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Active Settings")
                    }
                }

                if !state.availableProfilesForCopy.isEmpty {
                    Section {
                        ForEach(state.availableProfilesForCopy) { profile in
                            Button(action: {
                                state.copySettingsFrom(profile: profile)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "person.crop.circle")
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(profile.name)
                                            .foregroundColor(.primary)
                                        Text(profile.activeDays.formattedString)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Existing Profiles")
                    }
                }
            }
            .navigationTitle("Copy Settings From")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Inline Basal Rates Editor

private struct InlineBasalRatesEditor: View {
    @ObservedObject var state: TherapyProfileEditor.StateModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.basalProfile.enumerated()), id: \.element.minutes) { index, entry in
                BasalEntryRow(
                    entry: entry,
                    onRateChanged: { newRate in
                        state.updateBasalEntry(at: index, rate: newRate)
                    },
                    onDelete: {
                        state.deleteBasalEntry(at: index)
                    }
                )
                if index < state.basalProfile.count - 1 {
                    Divider()
                }
            }

            Button(action: state.addBasalEntry) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Time Slot")
                }
                .font(.subheadline)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
}

private struct BasalEntryRow: View {
    let entry: BasalProfileEntry
    let onRateChanged: (Decimal) -> Void
    let onDelete: () -> Void

    @State private var rateText: String = ""

    var body: some View {
        HStack {
            Text(entry.start)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            TextField("Rate", text: $rateText)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
                .onChange(of: rateText) { _, newValue in
                    if let rate = Decimal(string: newValue) {
                        onRateChanged(rate)
                    }
                }

            Text("U/hr")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            rateText = "\(entry.rate)"
        }
    }
}

// MARK: - Inline ISF Editor

private struct InlineISFEditor: View {
    @ObservedObject var state: TherapyProfileEditor.StateModel

    var body: some View {
        VStack(spacing: 0) {
            if let isf = state.insulinSensitivities {
                ForEach(Array(isf.sensitivities.enumerated()), id: \.element.offset) { index, entry in
                    ISFEntryRow(
                        entry: entry,
                        units: state.units,
                        onSensitivityChanged: { newValue in
                            state.updateISFEntry(at: index, sensitivity: newValue)
                        },
                        onDelete: {
                            state.deleteISFEntry(at: index)
                        }
                    )
                    if index < isf.sensitivities.count - 1 {
                        Divider()
                    }
                }
            }

            Button(action: state.addISFEntry) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Time Slot")
                }
                .font(.subheadline)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
}

private struct ISFEntryRow: View {
    let entry: InsulinSensitivityEntry
    let units: GlucoseUnits
    let onSensitivityChanged: (Decimal) -> Void
    let onDelete: () -> Void

    @State private var valueText: String = ""

    var body: some View {
        HStack {
            Text(entry.start)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            TextField("ISF", text: $valueText)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
                .onChange(of: valueText) { _, newValue in
                    if let value = Decimal(string: newValue) {
                        onSensitivityChanged(value)
                    }
                }

            Text(units == .mgdL ? "mg/dL" : "mmol/L")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            valueText = "\(entry.sensitivity)"
        }
    }
}

// MARK: - Inline Carb Ratio Editor

private struct InlineCarbRatioEditor: View {
    @ObservedObject var state: TherapyProfileEditor.StateModel

    var body: some View {
        VStack(spacing: 0) {
            if let cr = state.carbRatios {
                ForEach(Array(cr.schedule.enumerated()), id: \.element.offset) { index, entry in
                    CarbRatioEntryRow(
                        entry: entry,
                        onRatioChanged: { newValue in
                            state.updateCarbRatioEntry(at: index, ratio: newValue)
                        },
                        onDelete: {
                            state.deleteCarbRatioEntry(at: index)
                        }
                    )
                    if index < cr.schedule.count - 1 {
                        Divider()
                    }
                }
            }

            Button(action: state.addCarbRatioEntry) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Time Slot")
                }
                .font(.subheadline)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
}

private struct CarbRatioEntryRow: View {
    let entry: CarbRatioEntry
    let onRatioChanged: (Decimal) -> Void
    let onDelete: () -> Void

    @State private var valueText: String = ""

    var body: some View {
        HStack {
            Text(entry.start)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            TextField("Ratio", text: $valueText)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
                .onChange(of: valueText) { _, newValue in
                    if let value = Decimal(string: newValue) {
                        onRatioChanged(value)
                    }
                }

            Text("g/U")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            valueText = "\(entry.ratio)"
        }
    }
}

// MARK: - Inline Targets Editor

private struct InlineTargetsEditor: View {
    @ObservedObject var state: TherapyProfileEditor.StateModel

    var body: some View {
        VStack(spacing: 0) {
            if let targets = state.bgTargets {
                ForEach(Array(targets.targets.enumerated()), id: \.element.offset) { index, entry in
                    TargetEntryRow(
                        entry: entry,
                        units: state.units,
                        onValuesChanged: { low, high in
                            state.updateTargetEntry(at: index, low: low, high: high)
                        },
                        onDelete: {
                            state.deleteTargetEntry(at: index)
                        }
                    )
                    if index < targets.targets.count - 1 {
                        Divider()
                    }
                }
            }

            Button(action: state.addTargetEntry) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Time Slot")
                }
                .font(.subheadline)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 8)
    }
}

private struct TargetEntryRow: View {
    let entry: BGTargetEntry
    let units: GlucoseUnits
    let onValuesChanged: (Decimal, Decimal) -> Void
    let onDelete: () -> Void

    @State private var lowText: String = ""
    @State private var highText: String = ""

    var body: some View {
        HStack {
            Text(entry.start)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            TextField("Low", text: $lowText)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 60)
                .onChange(of: lowText) { _, _ in
                    updateValues()
                }

            Text("-")
                .foregroundColor(.secondary)

            TextField("High", text: $highText)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 60)
                .onChange(of: highText) { _, _ in
                    updateValues()
                }

            Text(units == .mgdL ? "mg/dL" : "mmol/L")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .onAppear {
            lowText = "\(entry.low)"
            highText = "\(entry.high)"
        }
    }

    private func updateValues() {
        if let low = Decimal(string: lowText), let high = Decimal(string: highText) {
            onValuesChanged(low, high)
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct TherapyProfileEditorRootView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                Text("Preview requires resolver setup")
            }
        }
    }
#endif
