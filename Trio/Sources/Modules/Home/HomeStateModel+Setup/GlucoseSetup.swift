import CoreData
import Foundation

extension Home.StateModel {
    @MainActor func setupGlucoseController() {
        glucoseControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateGlucoseFromController()
            }
        }

        do {
            try glucoseController.performFetch()
            updateGlucoseFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform glucose fetch: \(error)")
        }
    }

    @MainActor func updateGlucoseFromController() {
        guard let objects = glucoseController.fetchedObjects else { return }
        glucoseFromPersistence = objects
        latestTwoGlucoseValues = Array(objects.suffix(2))
        updateGlucoseChartYAxis(glucoseValues: objects)
        refreshExtendedStatsPanel()
    }

    /// Called from `MainChartView` on `.onChange(of: units)` to recompute the glucose-derived chart state.
    func setupGlucoseArray() {
        Task { @MainActor in
            updateGlucoseFromController()
        }
    }
}

extension Home.StateModel {
    func addManualGlucose(_ amount: Decimal) {
        let glucose = units == .mmolL ? amount.asMgdL : amount
        glucoseStorage.addManualGlucose(glucose: Int(glucose))
    }

    /// Stats panel figures over the configured range.
    ///
    /// Today and the last 24 hours come straight from the chart's in-memory readings;
    /// longer ranges use the result of the last background refresh.
    var statsPanelStats: HomeStatsPanelStats {
        let range = homeStatsPanelRange
        guard range.isCoveredByChartHistory else {
            // until a refresh for this range lands, show no data rather than another range's
            guard let extendedStatsPanel, extendedStatsPanel.range == range else { return HomeStatsPanelStats() }
            return extendedStatsPanel.stats
        }

        let startDate = range.startDate()
        let readings = glucoseFromPersistence
            .filter { ($0.date ?? .distantPast) >= startDate }
            .map { GlucoseReading(value: Int($0.glucose), date: $0.date ?? startDate) }
        // first render happens before service injection
        let timeInRangeType = settingsManager?.settings.timeInRangeType ?? .timeInTightRange
        return HomeStatsPanelStats(readings: readings, startDate: startDate, timeInRangeType: timeInRangeType)
    }

    /// Recomputes `extendedStatsPanel` for ranges the chart's 72 h of glucose doesn't cover.
    ///
    /// Those read up to three months of readings, so the fetch and the math run on a task
    /// context. New readings barely move a week-or-longer figure, so unforced refreshes
    /// (one per glucose update, every minute on some CGMs) are throttled.
    @MainActor func refreshExtendedStatsPanel(force: Bool = false) {
        let range = homeStatsPanelRange
        let face = settingsManager?.settings.homeStatsPanelFace ?? .timeInRange

        guard !range.isCoveredByChartHistory, face != .hidden else {
            extendedStatsPanelTask?.cancel()
            if extendedStatsPanel != nil { extendedStatsPanel = nil }
            return
        }

        if !force, extendedStatsPanel?.range == range, let refreshedAt = extendedStatsPanelRefreshedAt,
           Date().timeIntervalSince(refreshedAt) < Self.extendedStatsPanelRefreshInterval
        {
            return
        }

        let timeInRangeType = settingsManager?.settings.timeInRangeType ?? .timeInTightRange
        extendedStatsPanelTask?.cancel()
        extendedStatsPanelTask = Task { [weak self] in
            do {
                let stats = try await Self.computeStatsPanelStats(range: range, timeInRangeType: timeInRangeType)
                guard let self, !Task.isCancelled else { return }
                self.extendedStatsPanel = (range: range, stats: stats)
                self.extendedStatsPanelRefreshedAt = Date()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) Failed to compute home stats panel: \(error)")
            }
        }
    }

    private static let extendedStatsPanelRefreshInterval: TimeInterval = 5 * 60

    private static func computeStatsPanelStats(
        range: HomeStatsPanelRange,
        timeInRangeType: TimeInRangeType
    ) async throws -> HomeStatsPanelStats {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "HomeStateModel.computeStatsPanelStats"

        let startDate = range.startDate()
        // dictionary rows keep three months of readings light
        let request = NSFetchRequest<NSDictionary>(entityName: "GlucoseStored")
        request.predicate = NSPredicate(format: "date >= %@", startDate as NSDate)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["glucose", "date"]

        return try await context.perform {
            let readings = try context.fetch(request).compactMap { row -> GlucoseReading? in
                guard let value = (row["glucose"] as? NSNumber)?.intValue, let date = row["date"] as? Date else { return nil }
                return GlucoseReading(value: value, date: date)
            }
            return HomeStatsPanelStats(readings: readings, startDate: startDate, timeInRangeType: timeInRangeType)
        }
    }
}

/// What the home stats panel shows for its range.
struct HomeStatsPanelStats: Sendable {
    var veryLowPct: Double = 0
    var lowPct: Double = 0
    var inRangePct: Double = 0
    var highPct: Double = 0
    var veryHighPct: Double = 0
    /// Mean glucose in mg/dL, nil without readings.
    var meanGlucose: Double?

    var hasData: Bool { meanGlucose != nil }

    init() {}

    init(readings: [GlucoseReading], startDate: Date, timeInRangeType: TimeInRangeType) {
        guard !readings.isEmpty else { return }

        let distribution = GlucoseDailyDistributionStats.compute(
            date: startDate,
            readings: readings,
            // fixed consensus TIR bound (StatStateModel.highLimit), not the user's
            // chart threshold, so the banner always matches the Stats screen
            highLimit: 180,
            timeInRangeType: timeInRangeType
        )
        veryLowPct = distribution.veryLowPct
        lowPct = distribution.lowPct
        inRangePct = distribution.inRangePct
        highPct = distribution.highPct
        veryHighPct = distribution.veryHighPct
        meanGlucose = Double(readings.reduce(0) { $0 + $1.value }) / Double(readings.count)
    }
}
