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
        let loopStates: [LoopState]
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

        /// Loop state snapshot from OrefDetermination - captured every ~5 minutes
        struct LoopState {
            let date: Date
            let glucose: Decimal
            let iob: Decimal
            let cob: Int
            let tempBasalRate: Decimal
            let scheduledBasalRate: Decimal
            let smbDelivered: Decimal
            let eventualBG: Decimal?
            let insulinReq: Decimal
            let reason: String?
        }

        struct SettingsSummary {
            let units: String
            let targetLow: Int
            let targetHigh: Int
            let maxIOB: Decimal
            let maxBolus: Decimal
            let dia: Decimal
            let carbRatioSchedule: [(time: String, ratio: Decimal)]
            let isfSchedule: [(time: String, sensitivity: Decimal)]
            let basalSchedule: [(time: String, rate: Decimal)]
            let targetSchedule: [(time: String, low: Decimal, high: Decimal)]
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
            let totalBasal: Decimal
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
        carbRatioSchedule: [(time: String, ratio: Decimal)],
        isfSchedule: [(time: String, sensitivity: Decimal)],
        basalSchedule: [(time: String, rate: Decimal)],
        targetSchedule: [(time: String, low: Decimal, high: Decimal)]
    ) async throws -> ExportedData {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        // Fetch glucose readings
        let glucoseReadings = try await fetchGlucoseReadings(since: sevenDaysAgo)

        // Fetch carb entries
        let carbEntries = try await fetchCarbEntries(since: sevenDaysAgo)

        // Fetch bolus events
        let bolusEvents = try await fetchBolusEvents(since: sevenDaysAgo)

        // Fetch loop states (OrefDetermination data)
        let loopStates = try await fetchLoopStates(since: sevenDaysAgo)

        // Calculate statistics
        let statistics = calculateStatistics(
            glucose: glucoseReadings,
            carbs: carbEntries,
            boluses: bolusEvents,
            loopStates: loopStates,
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
            carbRatioSchedule: carbRatioSchedule,
            isfSchedule: isfSchedule,
            basalSchedule: basalSchedule,
            targetSchedule: targetSchedule
        )

        return ExportedData(
            glucoseReadings: glucoseReadings,
            carbEntries: carbEntries,
            bolusEvents: bolusEvents,
            loopStates: loopStates,
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
            // Fetch directly from BolusStored entity (like BolusStatsSetup does)
            let request = NSFetchRequest<NSManagedObject>(entityName: "BolusStored")
            // Filter by the parent pumpEvent's timestamp
            request.predicate = NSPredicate(format: "pumpEvent.timestamp >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "pumpEvent.timestamp", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { bolus -> ExportedData.BolusEvent? in
                // Get the timestamp from the related pumpEvent
                guard let pumpEvent = bolus.value(forKey: "pumpEvent") as? NSManagedObject,
                      let timestamp = pumpEvent.value(forKey: "timestamp") as? Date
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

    private func fetchLoopStates(since date: Date) async throws -> [ExportedData.LoopState] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "OrefDetermination")
            request.predicate = NSPredicate(format: "deliverAt >= %@", date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: true)]

            let results = try self.context.fetch(request)

            return results.compactMap { obj -> ExportedData.LoopState? in
                guard let deliverAt = obj.value(forKey: "deliverAt") as? Date else { return nil }

                let glucose = (obj.value(forKey: "glucose") as? NSDecimalNumber)?.decimalValue ?? 0
                let iob = (obj.value(forKey: "iob") as? NSDecimalNumber)?.decimalValue ?? 0
                let cob = obj.value(forKey: "cob") as? Int16 ?? 0
                let rate = (obj.value(forKey: "rate") as? NSDecimalNumber)?.decimalValue ?? 0
                let scheduledBasal = (obj.value(forKey: "scheduledBasal") as? NSDecimalNumber)?.decimalValue ?? 0
                let smbToDeliver = (obj.value(forKey: "smbToDeliver") as? NSDecimalNumber)?.decimalValue ?? 0
                let eventualBG = (obj.value(forKey: "eventualBG") as? NSDecimalNumber)?.decimalValue
                let insulinReq = (obj.value(forKey: "insulinReq") as? NSDecimalNumber)?.decimalValue ?? 0
                let reason = obj.value(forKey: "reason") as? String

                return ExportedData.LoopState(
                    date: deliverAt,
                    glucose: glucose,
                    iob: iob,
                    cob: Int(cob),
                    tempBasalRate: rate,
                    scheduledBasalRate: scheduledBasal,
                    smbDelivered: smbToDeliver,
                    eventualBG: eventualBG,
                    insulinReq: insulinReq,
                    reason: reason
                )
            }
        }
    }

    private func calculateStatistics(
        glucose: [ExportedData.GlucoseReading],
        carbs: [ExportedData.CarbEntry],
        boluses: [ExportedData.BolusEvent],
        loopStates: [ExportedData.LoopState],
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

        // Estimate total basal from loop states (temp basal rate * 5min intervals)
        let totalBasal = loopStates.reduce(Decimal(0)) { sum, state in
            sum + (state.tempBasalRate * Decimal(5) / Decimal(60)) // rate * 5min in hours
        }

        return ExportedData.Statistics(
            averageGlucose: average,
            minGlucose: minVal,
            maxGlucose: maxVal,
            timeInRange: tir,
            timeBelowRange: tbr,
            timeAboveRange: tar,
            totalCarbs: totalCarbs,
            totalBolus: totalBolus,
            totalBasal: totalBasal,
            readingCount: glucoseValues.count
        )
    }

    /// Format data as a prompt for Claude
    func formatForPrompt(_ data: ExportedData, analysisType: AnalysisType) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "MM/dd HH:mm"

        var prompt = """
        Here is my diabetes data from the last 7 days:

        ⚙️ SETTINGS
        • Units: \(data.settings.units)
        • Target Range: \(data.settings.targetLow)-\(data.settings.targetHigh) \(data.settings.units)
        • Max IOB: \(data.settings.maxIOB) U
        • Max Bolus: \(data.settings.maxBolus) U
        • DIA: \(data.settings.dia) hours

        📋 CARB RATIOS (1 unit insulin per X grams)
        \(formatSchedule(data.settings.carbRatioSchedule.map { "\($0.time): 1:\($0.ratio)" }))

        📋 INSULIN SENSITIVITY FACTORS (1 unit drops BG by X \(data.settings.units))
        \(formatSchedule(data.settings.isfSchedule.map { "\($0.time): \($0.sensitivity)" }))

        📋 BASAL RATES (U/hr)
        \(formatSchedule(data.settings.basalSchedule.map { "\($0.time): \($0.rate) U/hr" }))

        📋 TARGET GLUCOSE RANGES
        \(formatSchedule(data.settings.targetSchedule.map { "\($0.time): \($0.low)-\($0.high) \(data.settings.units)" }))

        📊 STATISTICS (Last 7 Days)
        • Average Glucose: \(data.statistics.averageGlucose) \(data.settings.units)
        • Range: \(data.statistics.minGlucose) - \(data.statistics.maxGlucose) \(data.settings.units)
        • Time in Range (\(data.settings.targetLow)-\(data.settings.targetHigh)): \(String(format: "%.1f", data.statistics.timeInRange))%
        • Time Below Range: \(String(format: "%.1f", data.statistics.timeBelowRange))%
        • Time Above Range: \(String(format: "%.1f", data.statistics.timeAboveRange))%
        • Total Carbs: \(String(format: "%.0f", data.statistics.totalCarbs))g
        • Total Bolus Insulin: \(data.statistics.totalBolus) U
        • Total Basal Insulin: \(String(format: "%.1f", NSDecimalNumber(decimal: data.statistics.totalBasal).doubleValue)) U
        • CGM Readings: \(data.statistics.readingCount)

        """

        switch analysisType {
        case .quick:
            // Add sampled raw data for quick analysis (every 15 min for last 24h)
            prompt += """

            📈 RAW LOOP DATA (Last 24 hours, ~15 min intervals)
            Format: Time | BG | IOB | COB | TempBasal | SMB
            \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: 24, intervalMinutes: 15))

            🍽️ RECENT MEALS
            \(formatCarbEntries(data.carbEntries.filter { $0.date > Calendar.current.date(byAdding: .day, value: -1, to: Date())! }, dateFormatter: timeFormatter))

            Please provide a quick analysis using these sections:
            📊 **Overview** - Brief summary of glucose control
            🔍 **Key Patterns** - Notable trends you observe
            ⚠️ **Concerns** - Any issues needing attention
            💡 **Quick Tip** - One actionable suggestion
            """

        case .weeklyReport:
            // Add comprehensive raw data for weekly report
            prompt += """

            📈 RAW LOOP DATA (Last 7 days, ~15 min intervals)
            Format: Time | BG | IOB | COB | TempBasal | SMB
            \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: 168, intervalMinutes: 15))

            🍽️ ALL CARB ENTRIES
            \(formatCarbEntries(data.carbEntries, dateFormatter: timeFormatter))

            💉 BOLUS HISTORY
            \(formatBolusEvents(data.bolusEvents, dateFormatter: timeFormatter))

            Please provide a comprehensive weekly report with these sections:

            📊 **Summary**
            - Overall glucose control assessment
            - Key metrics interpretation

            📈 **Pattern Analysis**
            - Time-of-day trends (morning, afternoon, evening, overnight)
            - Post-meal responses
            - Any recurring issues

            ✅ **What's Working Well**
            - Positive observations
            - Good control periods

            ⚠️ **Areas for Improvement**
            - Concerning patterns
            - Missed meals or unlogged carbs

            💡 **Recommendations**
            - Specific setting adjustments (be specific with numbers)
            - Behavioral suggestions
            - Follow-up items to monitor

            Format this as a professional report suitable for sharing with a healthcare provider.
            """

        case .chat:
            // For chat, include recent context
            prompt += """

            📈 RECENT LOOP DATA (Last 6 hours)
            Format: Time | BG | IOB | COB | TempBasal | SMB
            \(formatLoopStatesCompact(data.loopStates, timeFormatter: timeFormatter, hours: 6, intervalMinutes: 10))

            Based on this data, please answer my question.
            """
        }

        return prompt
    }

    private func formatSchedule(_ entries: [String]) -> String {
        if entries.isEmpty {
            return "Not configured"
        }
        return entries.joined(separator: " | ")
    }

    private func formatLoopStatesCompact(
        _ states: [ExportedData.LoopState],
        timeFormatter: DateFormatter,
        hours: Int,
        intervalMinutes: Int
    ) -> String {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        let filtered = states.filter { $0.date > cutoff }

        if filtered.isEmpty {
            return "No loop data available"
        }

        // Sample at specified intervals
        var sampled: [ExportedData.LoopState] = []
        var lastTime: Date?
        let intervalSeconds = Double(intervalMinutes * 60)

        for state in filtered {
            if let last = lastTime {
                if state.date.timeIntervalSince(last) >= intervalSeconds {
                    sampled.append(state)
                    lastTime = state.date
                }
            } else {
                sampled.append(state)
                lastTime = state.date
            }
        }

        return sampled.map { state in
            let bg = String(format: "%.0f", NSDecimalNumber(decimal: state.glucose).doubleValue)
            let iob = String(format: "%.2f", NSDecimalNumber(decimal: state.iob).doubleValue)
            let tempBasal = String(format: "%.2f", NSDecimalNumber(decimal: state.tempBasalRate).doubleValue)
            let smb = state.smbDelivered > 0 ? String(format: "%.2f", NSDecimalNumber(decimal: state.smbDelivered).doubleValue) : "-"

            return "\(timeFormatter.string(from: state.date)) | \(bg) | \(iob) | \(state.cob) | \(tempBasal) | \(smb)"
        }.joined(separator: "\n")
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
            return "No carb entries logged"
        }

        return entries.prefix(100).map { entry in
            var str = "\(dateFormatter.string(from: entry.date)) | \(String(format: "%.0f", entry.carbs))g"
            if entry.fat > 0 || entry.protein > 0 {
                str += " (F:\(String(format: "%.0f", entry.fat))g P:\(String(format: "%.0f", entry.protein))g)"
            }
            if let note = entry.note, !note.isEmpty {
                str += " \"\(note)\""
            }
            return str
        }.joined(separator: "\n")
    }

    private func formatBolusEvents(_ events: [ExportedData.BolusEvent], dateFormatter: DateFormatter) -> String {
        if events.isEmpty {
            return "No bolus events"
        }

        // Group by type for cleaner output
        let manual = events.filter { !$0.isSMB && !$0.isExternal }
        let smbs = events.filter { $0.isSMB }
        let external = events.filter { $0.isExternal }

        var output = ""

        if !manual.isEmpty {
            output += "Manual Boluses:\n"
            output += manual.prefix(50).map { event in
                "\(dateFormatter.string(from: event.date)) | \(event.amount) U"
            }.joined(separator: "\n")
        }

        if !smbs.isEmpty {
            if !output.isEmpty { output += "\n\n" }
            let totalSMB = smbs.reduce(Decimal(0)) { $0 + $1.amount }
            output += "SMBs: \(smbs.count) deliveries, \(String(format: "%.2f", NSDecimalNumber(decimal: totalSMB).doubleValue)) U total"
        }

        if !external.isEmpty {
            if !output.isEmpty { output += "\n\n" }
            output += "External/Pen Injections:\n"
            output += external.prefix(20).map { event in
                "\(dateFormatter.string(from: event.date)) | \(event.amount) U"
            }.joined(separator: "\n")
        }

        return output
    }

    enum AnalysisType {
        case quick
        case weeklyReport
        case chat
    }
}
