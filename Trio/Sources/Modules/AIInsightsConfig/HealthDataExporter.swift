import CoreData
import Foundation

/// Exports health data for AI analysis
final class HealthDataExporter {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    struct ExportedData {
        let glucoseReadings: [GlucoseReading]
        let carbEntries: [CarbEntry]
        let bolusEvents: [BolusEvent]
        let settings: SettingsSummary
        let statistics: Statistics

        struct GlucoseReading {
            let date: Date
            let value: Int
            let direction: String?
            let isManual: Bool
        }

        struct CarbEntry {
            let date: Date
            let carbs: Double
            let fat: Double
            let protein: Double
            let note: String?
        }

        struct BolusEvent {
            let date: Date
            let amount: Decimal
            let isSMB: Bool
            let isExternal: Bool
        }

        struct SettingsSummary {
            let units: String
            let targetLow: Int
            let targetHigh: Int
            let maxIOB: Decimal
            let maxBolus: Decimal
            let dia: Decimal
            let carbRatio: String
            let isf: String
        }

        struct Statistics {
            let averageGlucose: Int
            let minGlucose: Int
            let maxGlucose: Int
            let timeInRange: Double
            let timeBelowRange: Double
            let timeAboveRange: Double
            let totalCarbs: Double
            let totalBolus: Decimal
            let readingCount: Int
        }
    }

    /// Export the last 7 days of data
    func exportLast7Days(
        units: String,
        targetLow: Int,
        targetHigh: Int,
        maxIOB: Decimal,
        maxBolus: Decimal,
        dia: Decimal,
        carbRatios: String,
        isfs: String
    ) async throws -> ExportedData {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        // Fetch glucose readings
        let glucoseReadings = try await fetchGlucoseReadings(since: sevenDaysAgo)

        // Fetch carb entries
        let carbEntries = try await fetchCarbEntries(since: sevenDaysAgo)

        // Fetch bolus events
        let bolusEvents = try await fetchBolusEvents(since: sevenDaysAgo)

        // Calculate statistics
        let statistics = calculateStatistics(
            glucose: glucoseReadings,
            carbs: carbEntries,
            boluses: bolusEvents,
            lowThreshold: targetLow,
            highThreshold: targetHigh
        )

        let settings = ExportedData.SettingsSummary(
            units: units,
            targetLow: targetLow,
            targetHigh: targetHigh,
            maxIOB: maxIOB,
            maxBolus: maxBolus,
            dia: dia,
            carbRatio: carbRatios,
            isf: isfs
        )

        return ExportedData(
            glucoseReadings: glucoseReadings,
            carbEntries: carbEntries,
            bolusEvents: bolusEvents,
            settings: settings,
            statistics: statistics
        )
    }

    private func fetchGlucoseReadings(since date: Date) async throws -> [ExportedData.GlucoseReading] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "GlucoseStored")
            request.predicate = NSPredicate(format: "date >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.GlucoseReading? in
                guard let objDate = obj.value(forKey: "date") as? Date else { return nil }
                let glucose = obj.value(forKey: "glucose") as? Int16 ?? 0
                let direction = obj.value(forKey: "direction") as? String
                let isManual = obj.value(forKey: "isManual") as? Bool ?? false

                return ExportedData.GlucoseReading(
                    date: objDate,
                    value: Int(glucose),
                    direction: direction,
                    isManual: isManual
                )
            }
        }
    }

    private func fetchCarbEntries(since date: Date) async throws -> [ExportedData.CarbEntry] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CarbEntryStored")
            request.predicate = NSPredicate(format: "date >= %@ AND isFPU == NO", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.CarbEntry? in
                guard let objDate = obj.value(forKey: "date") as? Date else { return nil }
                let carbs = obj.value(forKey: "carbs") as? Double ?? 0
                let fat = obj.value(forKey: "fat") as? Double ?? 0
                let protein = obj.value(forKey: "protein") as? Double ?? 0
                let note = obj.value(forKey: "note") as? String

                return ExportedData.CarbEntry(
                    date: objDate,
                    carbs: carbs,
                    fat: fat,
                    protein: protein,
                    note: note
                )
            }
        }
    }

    private func fetchBolusEvents(since date: Date) async throws -> [ExportedData.BolusEvent] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "PumpEventStored")
            request.predicate = NSPredicate(format: "timestamp >= %@ AND type == %@", date as NSDate, "bolus")
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.BolusEvent? in
                guard let timestamp = obj.value(forKey: "timestamp") as? Date,
                      let bolus = obj.value(forKey: "bolus") as? NSManagedObject
                else { return nil }

                let amount = (bolus.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0
                let isSMB = bolus.value(forKey: "isSMB") as? Bool ?? false
                let isExternal = bolus.value(forKey: "isExternal") as? Bool ?? false

                return ExportedData.BolusEvent(
                    date: timestamp,
                    amount: amount,
                    isSMB: isSMB,
                    isExternal: isExternal
                )
            }
        }
    }

    private func calculateStatistics(
        glucose: [ExportedData.GlucoseReading],
        carbs: [ExportedData.CarbEntry],
        boluses: [ExportedData.BolusEvent],
        lowThreshold: Int,
        highThreshold: Int
    ) -> ExportedData.Statistics {
        let glucoseValues = glucose.map(\.value)

        let average = glucoseValues.isEmpty ? 0 : glucoseValues.reduce(0, +) / glucoseValues.count
        let minVal = glucoseValues.min() ?? 0
        let maxVal = glucoseValues.max() ?? 0

        let inRange = glucoseValues.filter { $0 >= lowThreshold && $0 <= highThreshold }.count
        let belowRange = glucoseValues.filter { $0 < lowThreshold }.count
        let aboveRange = glucoseValues.filter { $0 > highThreshold }.count

        let total = Double(glucoseValues.count)
        let tir = total > 0 ? Double(inRange) / total * 100 : 0
        let tbr = total > 0 ? Double(belowRange) / total * 100 : 0
        let tar = total > 0 ? Double(aboveRange) / total * 100 : 0

        let totalCarbs = carbs.reduce(0.0) { $0 + $1.carbs }
        let totalBolus = boluses.reduce(Decimal(0)) { $0 + $1.amount }

        return ExportedData.Statistics(
            averageGlucose: average,
            minGlucose: minVal,
            maxGlucose: maxVal,
            timeInRange: tir,
            timeBelowRange: tbr,
            timeAboveRange: tar,
            totalCarbs: totalCarbs,
            totalBolus: totalBolus,
            readingCount: glucoseValues.count
        )
    }

    /// Format data as a prompt for Claude
    func formatForPrompt(_ data: ExportedData, analysisType: AnalysisType) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        var prompt = """
        Here is my diabetes data from the last 7 days:

        ## Settings
        - Units: \(data.settings.units)
        - Target Range: \(data.settings.targetLow)-\(data.settings.targetHigh) \(data.settings.units)
        - Max IOB: \(data.settings.maxIOB) U
        - Max Bolus: \(data.settings.maxBolus) U
        - DIA: \(data.settings.dia) hours
        - Carb Ratios: \(data.settings.carbRatio)
        - ISF: \(data.settings.isf)

        ## Statistics (Last 7 Days)
        - Average Glucose: \(data.statistics.averageGlucose) \(data.settings.units)
        - Min: \(data.statistics.minGlucose), Max: \(data.statistics.maxGlucose)
        - Time in Range (\(data.settings.targetLow)-\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeInRange))%
        - Time Below Range: \(String(format: "%.1f", data.statistics.timeBelowRange))%
        - Time Above Range: \(String(format: "%.1f", data.statistics.timeAboveRange))%
        - Total Carbs: \(String(format: "%.0f", data.statistics.totalCarbs))g
        - Total Bolus Insulin: \(data.statistics.totalBolus) U
        - Reading Count: \(data.statistics.readingCount)

        """

        switch analysisType {
        case .quick:
            prompt += """

            Please provide a quick analysis (3-4 paragraphs) covering:
            1. Notable patterns you observe
            2. Any concerns or areas for attention
            3. One actionable suggestion to discuss with my healthcare provider
            """

        case .weeklyReport:
            // Add more detailed data for weekly report
            prompt += """

            ## Recent Glucose Readings (sample of last 24 hours)
            \(formatRecentGlucose(data.glucoseReadings, dateFormatter: dateFormatter))

            ## Carb Entries
            \(formatCarbEntries(data.carbEntries, dateFormatter: dateFormatter))

            ## Bolus History
            \(formatBolusEvents(data.bolusEvents, dateFormatter: dateFormatter))

            Please provide a comprehensive weekly report with:
            1. **Summary Statistics** - Overview of glucose control
            2. **Pattern Analysis** - Time-of-day trends, post-meal responses
            3. **What's Working Well** - Positive observations
            4. **Areas for Improvement** - Concerns or patterns to address
            5. **Recommendations** - Conservative percentage adjustments (5-15%) to discuss with my healthcare provider

            Format this as a report I can share with my doctor.
            """

        case .chat:
            // For chat, just include the context
            prompt += "\n\nBased on this data, please answer my question."
        }

        return prompt
    }

    private func formatRecentGlucose(_ readings: [ExportedData.GlucoseReading], dateFormatter: DateFormatter) -> String {
        let last24Hours = readings.filter {
            $0.date > Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        }

        if last24Hours.isEmpty {
            return "No readings in last 24 hours"
        }

        // Sample every 30 minutes to keep prompt size manageable
        var sampled: [ExportedData.GlucoseReading] = []
        var lastTime: Date?
        for reading in last24Hours {
            if let last = lastTime {
                if reading.date.timeIntervalSince(last) >= 1800 { // 30 minutes
                    sampled.append(reading)
                    lastTime = reading.date
                }
            } else {
                sampled.append(reading)
                lastTime = reading.date
            }
        }

        return sampled.map { "\(dateFormatter.string(from: $0.date)): \($0.value)" }.joined(separator: "\n")
    }

    private func formatCarbEntries(_ entries: [ExportedData.CarbEntry], dateFormatter: DateFormatter) -> String {
        if entries.isEmpty {
            return "No carb entries"
        }

        return entries.prefix(50).map { entry in
            var str = "\(dateFormatter.string(from: entry.date)): \(String(format: "%.0f", entry.carbs))g carbs"
            if entry.fat > 0 || entry.protein > 0 {
                str += " (F: \(String(format: "%.0f", entry.fat))g, P: \(String(format: "%.0f", entry.protein))g)"
            }
            if let note = entry.note, !note.isEmpty {
                str += " - \(note)"
            }
            return str
        }.joined(separator: "\n")
    }

    private func formatBolusEvents(_ events: [ExportedData.BolusEvent], dateFormatter: DateFormatter) -> String {
        if events.isEmpty {
            return "No bolus events"
        }

        return events.prefix(100).map { event in
            var str = "\(dateFormatter.string(from: event.date)): \(event.amount) U"
            if event.isSMB {
                str += " (SMB)"
            } else if event.isExternal {
                str += " (External)"
            } else {
                str += " (Manual)"
            }
            return str
        }.joined(separator: "\n")
    }

    enum AnalysisType {
        case quick
        case weeklyReport
        case chat
    }
}
