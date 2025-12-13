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
                        showQuickSelect: true
                    ) { day in
                        // Handle conflict tap - could show info about which profile owns this day
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Active Days")
            } footer: {
                if !state.conflictingDays.isEmpty {
                    Text("Days shown in gray are assigned to other profiles.")
                } else {
                    Text("Select which days of the week this profile should be active.")
                }
            }
        }

        @ViewBuilder
        private var therapySettingsSection: some View {
            Section {
                NavigationLink {
                    BasalProfileEditor.RootView(resolver: resolver)
                } label: {
                    settingsRow(
                        title: "Basal Rates",
                        subtitle: basalSummary,
                        systemImage: "waveform.path"
                    )
                }

                NavigationLink {
                    ISFEditor.RootView(resolver: resolver)
                } label: {
                    settingsRow(
                        title: "Insulin Sensitivities",
                        subtitle: isfSummary,
                        systemImage: "arrow.down.right"
                    )
                }

                NavigationLink {
                    CREditor.RootView(resolver: resolver)
                } label: {
                    settingsRow(
                        title: "Carb Ratios",
                        subtitle: carbRatioSummary,
                        systemImage: "fork.knife"
                    )
                }

                NavigationLink {
                    TargetsEditor.RootView(resolver: resolver)
                } label: {
                    settingsRow(
                        title: "Glucose Targets",
                        subtitle: targetsSummary,
                        systemImage: "target"
                    )
                }
            } header: {
                Text("Therapy Settings")
            } footer: {
                Text("Configure the insulin delivery and glucose management settings for this profile.")
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
        private func settingsRow(title: String, subtitle: String, systemImage: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }

        // MARK: - Summaries

        private var basalSummary: String {
            let count = state.basalProfile.count
            if count == 0 {
                return "Not configured"
            }
            let total = state.basalProfile.reduce(Decimal.zero) { $0 + $1.rate }
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
