import Combine
import Foundation

/// Manages a queue of commands (bolus/carb requests) from the Pebble watch.
/// Each command requires explicit confirmation on the iPhone before execution.
final class PebbleCommandManager: ObservableObject {
    @Published var pendingCommands: [PebbleCommand] = []

    var executeBolus: ((Double) -> Void)?
    var executeCarbs: ((Double, Double) -> Void)?

    var maxBolus: Decimal = 10.0
    var maxCarbs: Decimal = 250.0

    private let lock = NSLock()
    private let expiryInterval: TimeInterval = 300

    func queueBolus(units: Double) -> PebbleCommand? {
        guard Decimal(units) <= maxBolus, units > 0 else { return nil }

        let command = PebbleCommand(
            id: UUID().uuidString,
            type: .bolus,
            bolusUnits: units,
            carbGrams: nil,
            absorptionHours: nil,
            createdAt: Date()
        )

        appendCommand(command)
        return command
    }

    func queueCarbEntry(grams: Double, absorptionHours: Double) -> PebbleCommand? {
        guard Decimal(grams) <= maxCarbs, grams > 0 else { return nil }

        let command = PebbleCommand(
            id: UUID().uuidString,
            type: .carbEntry,
            bolusUnits: nil,
            carbGrams: grams,
            absorptionHours: absorptionHours,
            createdAt: Date()
        )

        appendCommand(command)
        return command
    }

    func confirmCommand(_ commandId: String) {
        lock.lock()
        guard let index = pendingCommands.firstIndex(where: { $0.id == commandId }) else {
            lock.unlock()
            return
        }
        let command = pendingCommands.remove(at: index)
        lock.unlock()

        guard !command.isExpired(expiryInterval) else {
            debug(.service, "Pebble: command \(commandId) expired, skipping execution")
            return
        }

        switch command.type {
        case .bolus:
            if let units = command.bolusUnits {
                debug(.service, "Pebble: executing confirmed bolus of \(String(format: "%.2f", units))U")
                executeBolus?(units)
            }
        case .carbEntry:
            if let grams = command.carbGrams, let hours = command.absorptionHours {
                debug(.service, "Pebble: executing confirmed carb entry of \(String(format: "%.0f", grams))g")
                executeCarbs?(grams, hours)
            }
        }
    }

    func rejectCommand(_ commandId: String) {
        lock.lock()
        pendingCommands.removeAll { $0.id == commandId }
        lock.unlock()
        debug(.service, "Pebble: rejected command \(commandId)")
    }

    func pendingCommandsJSON() -> String {
        purgeExpired()
        lock.lock()
        let commands = pendingCommands
        lock.unlock()

        let items = commands.map { cmd -> String in
            let typeStr = cmd.type == .bolus ? "bolus" : "carbEntry"
            let bolusStr = cmd.bolusUnits.map { String(format: "%.2f", $0) } ?? "null"
            let carbStr = cmd.carbGrams.map { String(format: "%.0f", $0) } ?? "null"
            return "{\"id\":\"\(cmd.id)\",\"type\":\"\(typeStr)\",\"bolusUnits\":\(bolusStr),\"carbGrams\":\(carbStr),\"createdAt\":\"\(ISO8601DateFormatter().string(from: cmd.createdAt))\"}"
        }

        return "[\(items.joined(separator: ","))]"
    }

    private func appendCommand(_ command: PebbleCommand) {
        lock.lock()
        pendingCommands.append(command)
        lock.unlock()
        purgeExpired()
    }

    private func purgeExpired() {
        lock.lock()
        pendingCommands.removeAll { $0.isExpired(expiryInterval) }
        lock.unlock()
    }
}

struct PebbleCommand: Identifiable {
    let id: String
    let type: PebbleCommandType
    let bolusUnits: Double?
    let carbGrams: Double?
    let absorptionHours: Double?
    let createdAt: Date

    func isExpired(_ interval: TimeInterval) -> Bool {
        Date().timeIntervalSince(createdAt) > interval
    }
}

enum PebbleCommandType {
    case bolus
    case carbEntry
}
