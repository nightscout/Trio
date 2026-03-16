import SwiftUI

extension PhysioTesting {
    struct NewTestFormView: View {
        @ObservedObject var state: StateModel
        @Environment(\.dismiss) var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    stabilitySection
                    testTypeSection
                    macrosSection
                    startSection
                }
                .navigationTitle("New Physio Test")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .onAppear {
                    Task { await state.updateStability() }
                }
                .alert("Start Without Stability?", isPresented: $state.showStabilityOverrideConfirm) {
                    Button("Start Anyway", role: .destructive) {
                        Task {
                            await state.startTest()
                            dismiss()
                        }
                    }
                    Button("Wait", role: .cancel) {}
                } message: {
                    Text(
                        "BG has only been stable for \(state.stabilityMinutes) minutes. " +
                            "\(StateModel.requiredStabilityMinutes) minutes is recommended for accurate results."
                    )
                }
            }
        }

        // MARK: - Stability Section

        private var stabilitySection: some View {
            Section(header: Text("BG Stability")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: state.isStable ? "checkmark.circle.fill" : "clock.fill")
                            .foregroundColor(state.isStable ? .green : .orange)
                        Text(state.isStable ? "BG is stable" : "Waiting for stability")
                            .fontWeight(.medium)
                    }

                    ProgressView(
                        value: min(Double(state.stabilityMinutes), Double(StateModel.requiredStabilityMinutes)),
                        total: Double(StateModel.requiredStabilityMinutes)
                    )
                    .tint(state.isStable ? .green : .orange)

                    HStack {
                        Text(
                            "Flat for \(state.stabilityMinutes) / \(StateModel.requiredStabilityMinutes) min"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Spacer()

                        if state.currentGlucose > 0 {
                            Text("Current: \(Int(state.currentGlucose)) mg/dL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if state.stabilityRange.min > 0 {
                        Text(
                            "Range: \(Int(state.stabilityRange.min)) - \(Int(state.stabilityRange.max)) mg/dL"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Button {
                        Task { await state.updateStability() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        // MARK: - Test Type Section

        private var testTypeSection: some View {
            Section(header: Text("Test Type")) {
                ForEach(TestType.allCases) { type in
                    Button {
                        state.selectedTestType = type
                    } label: {
                        HStack {
                            Image(systemName: type.iconName)
                                .foregroundColor(.accentColor)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text("Day \(type.dayNumber): \(type.displayName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text(type.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if state.selectedTestType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Macros Section

        private var macrosSection: some View {
            Section(header: Text("Meal Macros")) {
                HStack {
                    Text("Carbs")
                    Spacer()
                    TextField("g", value: $state.carbGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("g")
                        .foregroundColor(.secondary)
                }

                if state.selectedTestType.requiresFat {
                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("g", value: $state.fatGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }

                if state.selectedTestType.requiresProtein {
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("g", value: $state.proteinGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundColor(.secondary)
                    }
                }

                Text("Use the same carb count and bolus amount for all 4 test days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        // MARK: - Start Section

        private var startSection: some View {
            Section {
                Button {
                    if state.isStable {
                        Task {
                            await state.startTest()
                            dismiss()
                        }
                    } else {
                        state.showStabilityOverrideConfirm = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            state.isStable ? "Start Test" : "Start (Stability Not Met)",
                            systemImage: "play.circle.fill"
                        )
                        .font(.headline)
                        Spacer()
                    }
                }
                .disabled(state.carbGrams <= 0)

                Text("Starting the test will disable SMBs and temp basals. Normal scheduled basal will continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
