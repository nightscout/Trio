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
    private var consoleLogs: [String] = []
    private var logContext: String = ""

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
                self.consoleLogs.append("\(trimmedMessage)")
            }
        }
        context.setObject(
            consoleLog,
            forKeyedSubscript: "_consoleLog" as NSString
        )
        return context
    }

    // New method to flush aggregated logs
    private func outputLogs() {
        var outputLogs = consoleLogs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        consoleLogs.removeAll()

        if outputLogs.isEmpty { return }

        if logContext == "autosens.js" {
            outputLogs = outputLogs.split(separator: "\n").map { logLine in
                logLine.replacingOccurrences(
                    of: "^[-+=x!]|u\\(|\\)|\\d{1,2}h$",
                    with: "",
                    options: .regularExpression
                )
            }.joined(separator: "\n")
        }

        if !outputLogs.isEmpty {
            outputLogs.split(separator: "\n").forEach { logLine in
                if !"\(logLine)".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debug(.openAPS, "\(logContext): \(logLine)")
                }
            }
        }
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        logContext = URL(fileURLWithPath: script.name).lastPathComponent
        let result = evaluate(string: script.body)
        outputLogs()
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
            outputLogs()
        }
        return execute(self)
    }
}
