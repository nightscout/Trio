import CoreData
import SwiftUI
import Swinject

extension PhysioTesting {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                if state.isTestActive {
                    activeTestSection
                }

                newTestSection

                if !state.completedTests.isEmpty {
                    completedTestsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Physio Testing")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear(perform: configureView)
            .sheet(isPresented: $state.showNewTestSheet) {
                NewTestFormView(state: state)
            }
            .sheet(isPresented: $state.showResultsSheet) {
                if let metrics = state.computedMetrics {
                    TestResultsView(
                        metrics: metrics,
                        testType: state.selectedTestType,
                        readings: state.capturedReadings
                    )
                }
            }
            .alert("Safety Alert", isPresented: $state.showSafetyAlert) {
                Button("Resume Automation", role: .destructive) {
                    Task { await state.resumeAutomation() }
                }
                Button("Continue Test", role: .cancel) {
                    state.safetyAlertTriggered = false
                }
            } message: {
                Text(state.safetyAlertMessage)
            }
        }

        // MARK: - Active Test Section

        private var activeTestSection: some View {
            Section(header: Text("Active Test")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: state.selectedTestType.iconName)
                            .foregroundColor(.orange)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(state.selectedTestType.displayName)
                                .font(.headline)
                            Text(state.activeTestPhase.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(state.elapsedMinutes) min")
                            .font(.title3)
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }

                    // Meal time button
                    if state.mealTime == nil {
                        Button {
                            state.markMealTime()
                        } label: {
                            Label("Mark Meal Start", systemImage: "fork.knife")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Meal started \(timeAgo(state.mealTime!))")
                                .font(.subheadline)
                        }
                    }

                    // Bolus info
                    if state.bolusAmount > 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                            Text("Bolus: \(String(format: "%.2f", state.bolusAmount)) U")
                                .font(.subheadline)
                        }
                    } else {
                        HStack {
                            Image(systemName: "syringe")
                                .foregroundColor(.secondary)
                            Text("Use + button to deliver bolus")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Current BG
                    if state.currentGlucose > 0 {
                        HStack {
                            Text("Current BG:")
                                .font(.subheadline)
                            Text("\(Int(state.currentGlucose)) mg/dL")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Baseline: \(Int(state.baselineGlucose))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Stop button
                    HStack {
                        Button {
                            Task { await state.stopTest(cancelled: false) }
                        } label: {
                            Label("End Test", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button {
                            Task { await state.stopTest(cancelled: true) }
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - New Test Section

        private var newTestSection: some View {
            Section(header: Text("Start New Test")) {
                if !state.isTestActive {
                    Button {
                        Task { await state.updateStability() }
                        state.showNewTestSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("New Physio Test")
                                    .font(.headline)
                                Text("Test carbohydrate absorption with controlled meals")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("A test is currently active. End it before starting a new one.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - Completed Tests Section

        private var completedTestsSection: some View {
            Section(header: Text("Completed Tests")) {
                ForEach(state.completedTests) { test in
                    NavigationLink {
                        if let readings = PhysioGlucoseReadingCoder.decode(test.glucoseReadings) as [PhysioGlucoseReading]?,
                           !readings.isEmpty
                        {
                            TestResultsView(
                                metrics: AbsorptionMetrics.compute(
                                    readings: readings,
                                    baselineGlucose: test.baselineGlucose,
                                    mealTime: test.mealTime ?? test.startDate ?? Date()
                                ),
                                testType: TestType(rawValue: test.testType ?? "") ?? .pureCarbs,
                                readings: readings
                            )
                        } else {
                            Text("No data available for this test")
                        }
                    } label: {
                        completedTestRow(test)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        state.deleteTest(state.completedTests[index])
                    }
                }
            }
            .listRowBackground(Color.chart)
        }

        private func completedTestRow(_ test: PhysioTestStored) -> some View {
            let testType = TestType(rawValue: test.testType ?? "") ?? .pureCarbs
            return HStack {
                Image(systemName: testType.iconName)
                    .foregroundColor(test.isComplete ? .green : .gray)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(testType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let date = test.startDate {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if test.isComplete {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Peak: \(Int(test.peakGlucose))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("AUC: \(Int(test.totalAUC))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Incomplete")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }

        // MARK: - Helpers

        private func timeAgo(_ date: Date) -> String {
            let minutes = Int(Date().timeIntervalSince(date) / 60)
            if minutes < 1 { return "just now" }
            return "\(minutes) min ago"
        }
    }
}
