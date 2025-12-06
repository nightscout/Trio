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
        let consoleLog: @convention(block) (String) -> Void = { [weak context] message in
            guard let context = context else { return }
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty {
                let fileName = context.objectForKeyedSubscript("scriptName").toString() ?? "Unknown"
                let threadSafeLog = "\(trimmedMessage)"
                self.processQueue.async(flags: .barrier) {
                    self.outputLogs(for: fileName, message: threadSafeLog)
                }
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

    private func outputLogs(for fileName: String, message: String) {
        let logs = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if logs.isEmpty { return }

        if fileName == "autosens.js" {
            let sanitizedLogs = logs.split(separator: "\n").map { logLine in
                logLine.replacingOccurrences(
                    of: "^[-+=x!]|u\\(|\\)|\\d{1,2}h$",
                    with: "",
                    options: .regularExpression
                )
            }.joined(separator: "\n")

            sanitizedLogs.split(separator: "\n").forEach { logLine in
                if !logLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debug(.openAPS, "\(fileName): \(logLine)")
                }
            }
        } else {
            logs.split(separator: "\n").forEach { logLine in
                if !logLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debug(.openAPS, "\(fileName): \(logLine)")
                }
            }
        }
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        let context = getContext()
        defer { returnContext(context) }
        let fileName = URL(fileURLWithPath: script.name).lastPathComponent
        context.setObject(fileName, forKeyedSubscript: "scriptName" as NSString)
        let result = context.evaluateScript(script.body)
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
        }
        return execute(self)
    }

    func evaluateBatch(scripts: [Script]) {
        let context = getContext()
        defer {
            returnContext(context)
        }
        scripts.forEach { script in
            let fileName = URL(fileURLWithPath: script.name).lastPathComponent
            context.setObject(fileName, forKeyedSubscript: "scriptName" as NSString)
            context.evaluateScript(script.body)
        }
    }
}
