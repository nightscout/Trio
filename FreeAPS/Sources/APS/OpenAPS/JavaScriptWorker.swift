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
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker", attributes: .concurrent)
    private let virtualMachine: JSVirtualMachine
    private var contextPool: [JSContext] = []
    private let contextPoolLock = NSLock()
    @SyncAccess(lock: contextLock) private var commonContext: JSContext? = nil
    private var consoleLogs: [String] = []
    private var logContext: String = ""

    init(poolSize: Int = 5) {
        virtualMachine = JSVirtualMachine()!
        // Pre-create a pool of JSContext instances
        for _ in 0 ..< poolSize {
            contextPool.append(createContext())
        }
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
        context.setObject(consoleLog, forKeyedSubscript: "_consoleLog" as NSString)
        return context
    }

    private func getContext() -> JSContext {
        contextPoolLock.lock()
        let context = contextPool.popLast() ?? createContext()
        contextPoolLock.unlock()
        return context
    }

    private func returnContext(_ context: JSContext) {
        contextPoolLock.lock()
        contextPool.append(context)
        contextPoolLock.unlock()
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
        let context = getContext()
        defer { returnContext(context) }
        return context.evaluateScript(string)
    }

    private func json(for string: String) -> RawJSON {
        evaluate(string: "JSON.stringify(\(string), null, 4);")!.toString()!
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")
        return json(for: "\(function)(\(joined))")
    }

    func inCommonContext<Value>(execute: (JavaScriptWorker) -> Value) -> Value {
        let context = getContext()
        defer {
            returnContext(context)
            outputLogs()
        }
        return execute(self)
    }

    func evaluateBatch(scripts: [Script]) {
        let context = getContext()
        defer {
            // Ensure the context is returned to the pool
            returnContext(context)
        }
        scripts.forEach { script in
            logContext = URL(fileURLWithPath: script.name).lastPathComponent
            context.evaluateScript(script.body)
            outputLogs()
        }
    }
}
