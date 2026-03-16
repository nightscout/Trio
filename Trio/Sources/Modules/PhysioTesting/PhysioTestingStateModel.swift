import Combine
import CoreData
import Observation
import SwiftUI

extension PhysioTesting {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Injected Dependencies

        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var physioTestStorage: PhysioTestStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var apsManager: APSManager!

        // MARK: - Test Configuration

        var selectedTestType: TestType = .pureCarbs
        var carbGrams: Double = 30
        var fatGrams: Double = 15
        var proteinGrams: Double = 20

        // MARK: - Active Test State

        var isTestActive = false
        var activeTestPhase: TestPhase = .baseline
        var activeTest: PhysioTestStored?
        var testStartDate: Date?
        var mealTime: Date?
        var bolusTime: Date?
        var bolusAmount: Double = 0
        var baselineGlucose: Double = 0
        var elapsedMinutes: Int = 0

        // MARK: - Stability

        var stabilityMinutes: Int = 0
        var isStable: Bool = false
        var currentGlucose: Double = 0
        var stabilityRange: (min: Double, max: Double) = (0, 0)
        static let requiredStabilityMinutes = 60
        static let stabilityThreshold = 8.0 // +/- 8 mg/dL

        // MARK: - Safety

        static let lowSafetyThreshold: Double = 70
        static let highSafetyThreshold: Double = 300
        var safetyAlertTriggered = false
        var safetyAlertMessage = ""

        // MARK: - Results

        var completedTests: [PhysioTestStored] = []
        var capturedReadings: [PhysioGlucoseReading] = []
        var computedMetrics: AbsorptionMetrics?

        // MARK: - UI State

        var showNewTestSheet = false
        var showResultsSheet = false
        var showSafetyAlert = false
        var showStabilityOverrideConfirm = false

        // Core Data
        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        // Timer
        @ObservationIgnored private var updateTimer: Timer?

        // MARK: - Lifecycle

        override func subscribe() {
            loadCompletedTests()
            checkForActiveTest()
        }

        // MARK: - Test Management

        func startTest() async {
            await MainActor.run {
                isTestActive = true
                activeTestPhase = .active
                testStartDate = Date()
                capturedReadings = []
                safetyAlertTriggered = false
            }

            // Create the override (SMBs off, 100% basal)
            await createTestOverride()

            // Create Core Data entry
            await createTestEntry()

            // Start the monitoring timer
            await MainActor.run {
                startMonitoringTimer()
            }
        }

        func stopTest(cancelled: Bool = false) async {
            await MainActor.run {
                updateTimer?.invalidate()
                updateTimer = nil
                activeTestPhase = cancelled ? .cancelled : .complete
                isTestActive = false
            }

            // Remove the test override
            await removeTestOverride()

            // Finalize the test entry
            await finalizeTestEntry(cancelled: cancelled)

            if !cancelled {
                await MainActor.run {
                    computedMetrics = AbsorptionMetrics.compute(
                        readings: capturedReadings,
                        baselineGlucose: baselineGlucose,
                        mealTime: mealTime ?? testStartDate ?? Date()
                    )
                    showResultsSheet = true
                }
            }

            loadCompletedTests()
        }

        func markMealTime() {
            mealTime = Date()
            if let test = activeTest {
                viewContext.perform {
                    test.mealTime = Date()
                    try? self.viewContext.save()
                }
            }
        }

        func recordBolus(amount: Double) {
            bolusAmount = amount
            bolusTime = Date()
            if let test = activeTest {
                viewContext.perform {
                    test.bolusAmount = amount
                    test.bolusTime = Date()
                    try? self.viewContext.save()
                }
            }
        }

        func resumeAutomation() async {
            await stopTest(cancelled: true)
        }

        // MARK: - Monitoring

        private func startMonitoringTimer() {
            updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.updateTestState()
                }
            }
        }

        @MainActor
        private func updateTestState() async {
            guard isTestActive else { return }

            // Update elapsed time
            if let start = testStartDate {
                elapsedMinutes = Int(Date().timeIntervalSince(start) / 60)
            }

            // Capture latest glucose
            await captureGlucoseReading()

            // Check safety
            checkSafetyThresholds()

            // Update phase based on glucose movement
            updatePhase()
        }

        private func captureGlucoseReading() async {
            let readings = await fetchRecentGlucoseReadings(minutes: 5)
            for reading in readings {
                let exists = capturedReadings.contains { abs($0.date.timeIntervalSince(reading.date)) < 30 }
                if !exists {
                    capturedReadings.append(reading)
                    currentGlucose = Double(reading.glucose)
                }
            }

            // Update stored readings
            if let test = activeTest {
                await viewContext.perform {
                    test.glucoseReadings = PhysioGlucoseReadingCoder.encode(self.capturedReadings)
                    try? self.viewContext.save()
                }
            }
        }

        private func checkSafetyThresholds() {
            guard !safetyAlertTriggered else { return }

            if currentGlucose < Self.lowSafetyThreshold, currentGlucose > 0 {
                safetyAlertTriggered = true
                safetyAlertMessage = String(
                    localized: "BG has dropped below \(Int(Self.lowSafetyThreshold)) mg/dL. Consider resuming automation.",
                    comment: "Physio test safety alert"
                )
                showSafetyAlert = true
            } else if currentGlucose > Self.highSafetyThreshold {
                safetyAlertTriggered = true
                safetyAlertMessage = String(
                    localized: "BG has risen above \(Int(Self.highSafetyThreshold)) mg/dL. Consider resuming automation.",
                    comment: "Physio test safety alert"
                )
                showSafetyAlert = true
            }
        }

        private func updatePhase() {
            guard let meal = mealTime, isTestActive else { return }

            let minutesSinceMeal = Date().timeIntervalSince(meal) / 60

            if capturedReadings.count < 3 { return }

            let recent = capturedReadings.suffix(3)
            let avgRate: Double = {
                let sorted = recent.sorted { $0.date < $1.date }
                guard sorted.count >= 2 else { return 0 }
                let dt = sorted.last!.date.timeIntervalSince(sorted.first!.date) / 60
                guard dt > 0 else { return 0 }
                return (Double(sorted.last!.glucose) - Double(sorted.first!.glucose)) / dt
            }()

            if avgRate > 0.5 {
                activeTestPhase = .rising
            } else if avgRate < -0.5 {
                activeTestPhase = .descending
            } else if minutesSinceMeal > 30, activeTestPhase == .rising || activeTestPhase == .peaking {
                activeTestPhase = .peaking
            } else if minutesSinceMeal > 60,
                      abs(currentGlucose - baselineGlucose) < Self.stabilityThreshold,
                      activeTestPhase == .descending
            {
                activeTestPhase = .returning
            }
        }

        // MARK: - Stability Checking

        func updateStability() async {
            let readings = await fetchRecentGlucoseReadings(minutes: Self.requiredStabilityMinutes + 10)
            guard readings.count >= 6 else {
                await MainActor.run {
                    stabilityMinutes = 0
                    isStable = false
                }
                return
            }

            let sorted = readings.sorted { $0.date > $1.date }

            // Walk backward from most recent, counting consecutive stable minutes
            var stableCount = 0
            let referenceGlucose = Double(sorted.first!.glucose)
            var minGlucose = referenceGlucose
            var maxGlucose = referenceGlucose

            for reading in sorted {
                let g = Double(reading.glucose)
                let tempMin = min(minGlucose, g)
                let tempMax = max(maxGlucose, g)

                if (tempMax - tempMin) <= Self.stabilityThreshold * 2 {
                    minGlucose = tempMin
                    maxGlucose = tempMax
                    stableCount = Int(sorted.first!.date.timeIntervalSince(reading.date) / 60)
                } else {
                    break
                }
            }

            await MainActor.run {
                stabilityMinutes = stableCount
                isStable = stableCount >= Self.requiredStabilityMinutes
                currentGlucose = referenceGlucose
                baselineGlucose = (minGlucose + maxGlucose) / 2
                stabilityRange = (minGlucose, maxGlucose)
            }
        }

        // MARK: - Glucose Fetching

        private func fetchRecentGlucoseReadings(minutes: Int) async -> [PhysioGlucoseReading] {
            let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
            do {
                let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: GlucoseStored.self,
                    onContext: coredataContext,
                    predicate: NSPredicate(format: "date >= %@", cutoff as NSDate),
                    key: "date",
                    ascending: true
                )

                return await coredataContext.perform {
                    guard let fetched = results as? [GlucoseStored] else { return [] }
                    return fetched.map { glucose in
                        PhysioGlucoseReading(
                            date: glucose.date ?? Date(),
                            glucose: glucose.glucose,
                            direction: glucose.direction
                        )
                    }
                }
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to fetch glucose readings: \(error)")
                return []
            }
        }

        // MARK: - Override Management

        private func createTestOverride() async {
            let override = Override(
                name: "Physio Test Mode",
                enabled: true,
                date: Date(),
                duration: 480, // 8 hours max
                indefinite: false,
                percentage: 100,
                smbIsOff: true,
                isPreset: false,
                id: UUID().uuidString,
                overrideTarget: false,
                target: 0,
                advancedSettings: false,
                isfAndCr: true,
                isf: true,
                cr: true,
                smbIsScheduledOff: false,
                start: 0,
                end: 0,
                smbMinutes: 0,
                uamMinutes: 0
            )

            do {
                try await overrideStorage.storeOverride(override: override)
                try await apsManager.determineBasalSync()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to create test override: \(error)")
            }
        }

        private func removeTestOverride() async {
            // Fetch and disable the test override
            do {
                let ids = try await overrideStorage.loadLatestOverrideConfigurations(fetchLimit: 1)
                await viewContext.perform {
                    for id in ids {
                        if let override = try? self.viewContext.existingObject(with: id) as? OverrideStored,
                           override.name == "Physio Test Mode"
                        {
                            // Create run entry
                            let runEntry = OverrideRunStored(context: self.viewContext)
                            runEntry.id = UUID()
                            runEntry.name = override.name
                            runEntry.startDate = override.date ?? .distantPast
                            runEntry.endDate = Date()
                            runEntry.target = override.target
                            runEntry.override = override
                            runEntry.isUploadedToNS = true // Don't upload test overrides

                            override.enabled = false
                        }
                    }
                    if self.viewContext.hasChanges {
                        try? self.viewContext.save()
                    }
                }
                try await apsManager.determineBasalSync()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to remove test override: \(error)")
            }
        }

        // MARK: - Core Data Test Entry

        private func createTestEntry() async {
            await viewContext.perform {
                let test = PhysioTestStored(context: self.viewContext)
                test.id = UUID()
                test.startDate = self.testStartDate
                test.testType = self.selectedTestType.rawValue
                test.carbs = self.carbGrams
                test.fat = self.selectedTestType.requiresFat ? self.fatGrams : 0
                test.protein = self.selectedTestType.requiresProtein ? self.proteinGrams : 0
                test.baselineGlucose = self.baselineGlucose
                test.isComplete = false

                do {
                    try self.viewContext.save()
                    self.activeTest = test
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to create physio test entry: \(error)")
                }
            }
        }

        private func finalizeTestEntry(cancelled: Bool) async {
            guard let test = activeTest else { return }
            await viewContext.perform {
                test.endDate = Date()
                test.isComplete = !cancelled
                test.glucoseReadings = PhysioGlucoseReadingCoder.encode(self.capturedReadings)

                if !cancelled, let metrics = AbsorptionMetrics.compute(
                    readings: self.capturedReadings,
                    baselineGlucose: self.baselineGlucose,
                    mealTime: self.mealTime ?? self.testStartDate ?? Date()
                ) {
                    test.onsetDelay = metrics.onsetDelay
                    test.peakAbsorptionRate = metrics.peakAbsorptionRate
                    test.timeToPeak = metrics.timeToPeakBG
                    test.peakGlucose = metrics.peakGlucose
                    test.totalAUC = metrics.totalAUC
                    test.absorptionDuration = metrics.absorptionDuration
                }

                try? self.viewContext.save()
            }
        }

        // MARK: - Load Tests

        func loadCompletedTests() {
            Task {
                do {
                    let ids = try await physioTestStorage.fetchAllTests()
                    await MainActor.run {
                        completedTests = ids.compactMap { id in
                            try? viewContext.existingObject(with: id) as? PhysioTestStored
                        }
                    }
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to load completed tests: \(error)")
                }
            }
        }

        private func checkForActiveTest() {
            Task {
                do {
                    if let id = try await physioTestStorage.fetchActiveTest() {
                        await MainActor.run {
                            if let test = try? viewContext.existingObject(with: id) as? PhysioTestStored {
                                activeTest = test
                                isTestActive = true
                                testStartDate = test.startDate
                                mealTime = test.mealTime
                                bolusTime = test.bolusTime
                                bolusAmount = test.bolusAmount
                                baselineGlucose = test.baselineGlucose
                                selectedTestType = TestType(rawValue: test.testType ?? "") ?? .pureCarbs
                                capturedReadings = PhysioGlucoseReadingCoder.decode(test.glucoseReadings)
                                activeTestPhase = .active
                                startMonitoringTimer()
                            }
                        }
                    }
                } catch {
                    debugPrint("\(DebuggingIdentifiers.failed) Failed to check for active test: \(error)")
                }
            }
        }

        func deleteTest(_ test: PhysioTestStored) {
            Task {
                await physioTestStorage.deleteTest(test.objectID)
                loadCompletedTests()
            }
        }
    }
}
