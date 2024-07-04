import Foundation
import JavaScriptCore

private let contextLock = NSRecursiveLock()

extension String {
    var lowercasingFirst: String { prefix(1).lowercased() + dropFirst() }
    var uppercasingFirst: String { prefix(1).uppercased() + dropFirst() }
    var camelCased: String {
        guard !isEmpty else { return "" }
        let parts = components(separatedBy: .alphanumerics.inverted)
        let first = parts.first!.lowercasingFirst
        let rest = parts.dropFirst().map(\.uppercasingFirst)
        return ([first] + rest).joined()
    }

    var pascalCased: String {
        guard !isEmpty else { return "" }
        let parts = components(separatedBy: .alphanumerics.inverted)
        let first = parts.first!.uppercasingFirst
        let rest = parts.dropFirst().map(\.uppercasingFirst)
        return ([first] + rest).joined()
    }
}

final class JavaScriptWorker {
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker")
    private let virtualMachine: JSVirtualMachine
    @SyncAccess(lock: contextLock) private var commonContext: JSContext? = nil
    private var aggregatedLogs: [String] = []
    private var logFormatting: String = ""

    init() {
        virtualMachine = processQueue.sync { JSVirtualMachine()! }
    }

    private func createContext() -> JSContext {
        let context = JSContext(virtualMachine: virtualMachine)!
        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                warning(.openAPS, "JavaScript Error: \(error)")
            }
        }
        let consoleLog: @convention(block) (String) -> Void = { message in
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty {
//                debug(.openAPS, "JavaScript log: \(trimmedMessage)")
                self.aggregatedLogs.append("\(trimmedMessage)")
            }
        }
        context.setObject(
            consoleLog,
            forKeyedSubscript: "_consoleLog" as NSString
        )
        return context
    }

    // New method to flush aggregated logs
    private func aggregateLogs() {
        let combinedLogs = aggregatedLogs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        aggregatedLogs.removeAll()

        if combinedLogs.isEmpty { return }

        var logOutput = ""
        var jsonOutput = ""

        switch logFormatting {
        case "Middleware":
            jsonOutput += "{\n"
            combinedLogs.replacingOccurrences(of: ";", with: ",")
                .replacingOccurrences(of: "\\s?:\\s?,?", with: ": ", options: .regularExpression)
                .replacingOccurrences(of: "(\\w+: \\d+(?= [^,:\\s]+:))", with: "$1,", options: .regularExpression)
                .replacingOccurrences(of: "^[^\\w]*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "(\\sset)?\\sto:?\\s+", with: ": ", options: .regularExpression)
                .replacingOccurrences(of: "(\\w+) is (\\w+)\\!?", with: "$1: $2", options: .regularExpression)
                .replacingOccurrences(of: "NaN \\(\\. (.+)\\)", with: "$1, ", options: .regularExpression)
                .replacingOccurrences(of: "Setting (.+) of (.*)", with: "$1: $2 ", options: .regularExpression)
                .replacingOccurrences(of: "(Using\\s|\\sused)", with: "", options: .regularExpression)
                .replacingOccurrences(
                    of: " instead of past 24 h \\((" + "(-?\\d+(\\.\\d+)?)" + " U)\\)",
                    with: "weighted TDD average past 24h: $1",
                    options: .regularExpression
                )
                .replacingOccurrences(of: "^(.+) \\((.+)\\)$", with: "$1: $2", options: .regularExpression)
                .replacingOccurrences(of: "\\s?,\\s?$", with: "", options: .regularExpression)
                .split(separator: "\n").forEach { logLine in
                    jsonOutput += "    "
                    logLine.split(separator: ",").forEach { logItem in
                        let keyPair = logItem.split(separator: ":")
                        if keyPair.count == 2 {
                            let key = keyPair[0].trimmingCharacters(in: .whitespacesAndNewlines).pascalCased
                            let value = keyPair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            jsonOutput += "\"\(key)\": \"\(value)\", "
                        } else {
                            logOutput += "\(logItem)\n"
                        }
                    }
                    jsonOutput += "\n"
                }
            jsonOutput += "}"
            jsonOutput = jsonOutput.replacingOccurrences(of: "\\s+\\n+", with: "\n", options: .regularExpression)

        case "prepare/autosens.js":
            logOutput += combinedLogs.replacingOccurrences(
                of: "((?:[\\=\\+\\-]\\n)+)?\\d+h\\n((?:[\\=\\+\\-]\\n)+)?",
                with: "",
                options: .regularExpression
            )
        // case "prepare/autotune-prep.js"
        // case "prepare/autotune-core.js"
        default:
            debug(.openAPS, "JavaScript Format: \(logFormatting)")
            logOutput = combinedLogs
        }

        if !jsonOutput.isEmpty {
            if let jsonData = "\(jsonOutput)".data(using: .utf8) {
                do {
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    _ = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
                    debug(.openAPS, "JavaScript log: \(jsonOutput)")
                } catch {
                    logOutput = combinedLogs
                }
            }
        }

        if !logOutput.isEmpty {
            logOutput.split(separator: "\n").forEach { logLine in
                if !"\(logLine)".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debug(.openAPS, "JavaScript log: \(logLine)")
                }
            }
        }
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        logFormatting = script.name
        let result = evaluate(string: script.body)
        aggregateLogs()
        return result
    }

    private func evaluate(string: String) -> JSValue! {
        let ctx = commonContext ?? createContext()
        return ctx.evaluateScript(string)
    }

    private func json(for string: String) -> RawJSON {
        evaluate(string: "JSON.stringify(\(string), null, 4);")!.toString()!
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")
        return json(for: "\(function)(\(joined))")
    }

    func inCommonContext<Value>(execute: (JavaScriptWorker) -> Value) -> Value {
        commonContext = createContext()
        defer {
            commonContext = nil
            aggregateLogs()
        }
        return execute(self)
    }
}
