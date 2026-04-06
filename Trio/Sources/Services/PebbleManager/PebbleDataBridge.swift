import Foundation

/// Translates Trio's dev-branch WatchState into JSON endpoint responses
/// for the Pebble local HTTP API.
final class PebbleDataBridge {
    private let lock = NSLock()

    private var currentGlucose: String?
    private var currentGlucoseColor: String?
    private var trend: String?
    private var delta: String?
    private var iob: String?
    private var cob: String?
    private var lastLoopTime: String?
    private var glucoseValues: [(date: Date, glucose: Double, color: String)] = []
    private var maxBolus: Decimal = 10.0
    private var maxCarbs: Decimal = 250.0
    private var units: String = "mgdL"
    private var stateDate: Date?

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func updateFromWatchState(_ state: WatchState) {
        lock.lock()
        defer { lock.unlock() }

        currentGlucose = state.currentGlucose
        currentGlucoseColor = state.currentGlucoseColorString
        trend = state.trend
        delta = state.delta
        iob = state.iob
        cob = state.cob
        lastLoopTime = state.lastLoopTime
        maxBolus = state.maxBolus
        maxCarbs = state.maxCarbs
        units = state.units.rawValue
        stateDate = state.date

        glucoseValues = state.glucoseValues.map { gv in
            (date: gv.date, glucose: gv.glucose, color: gv.color)
        }
    }

    // MARK: - JSON Endpoints

    func cgmJSON() -> String {
        lock.lock()
        defer { lock.unlock() }

        let glucoseStr = jsonQuoted(currentGlucose)
        let trendStr = jsonQuoted(trend)
        let deltaStr = jsonQuoted(delta)
        let dateStr = stateDate.map { "\"\(isoFormatter.string(from: $0))\"" } ?? "null"
        let stale = isGlucoseStale()

        return "{\"glucose\":\(glucoseStr),\"trend\":\(trendStr),\"delta\":\(deltaStr),\"date\":\(dateStr),\"isStale\":\(stale),\"units\":\"\(units)\"}"
    }

    func loopJSON() -> String {
        lock.lock()
        defer { lock.unlock() }

        let iobStr = jsonQuoted(iob)
        let cobStr = jsonQuoted(cob)
        let lastLoopStr = jsonQuoted(lastLoopTime)
        let historyStr = formatGlucoseHistory()

        return "{\"iob\":\(iobStr),\"cob\":\(cobStr),\"lastLoopTime\":\(lastLoopStr),\"glucoseHistory\":\(historyStr)}"
    }

    func pumpJSON() -> String {
        return "{\"reservoir\":null,\"battery\":null}"
    }

    func allDataJSON() -> String {
        let timestamp = isoFormatter.string(from: Date())
        return "{\"timestamp\":\"\(timestamp)\",\"cgm\":\(cgmJSON()),\"loop\":\(loopJSON()),\"pump\":\(pumpJSON()),\"maxBolus\":\(maxBolus),\"maxCarbs\":\(maxCarbs)}"
    }

    // MARK: - Helpers

    private func isGlucoseStale() -> Bool {
        guard let date = stateDate else { return true }
        return Date().timeIntervalSince(date) > 15 * 60
    }

    private func formatGlucoseHistory() -> String {
        guard !glucoseValues.isEmpty else { return "[]" }
        let items = glucoseValues.map { "\(Int($0.glucose))" }
        return "[\(items.joined(separator: ","))]"
    }

    private func jsonQuoted(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }
}
