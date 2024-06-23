import Foundation
import JavaScriptCore

private let contextLock = NSRecursiveLock()

extension String {
    func replacingRegex(
        matching pattern: String,
        findingOptions: NSRegularExpression.Options = .caseInsensitive,
        replacingOptions: NSRegularExpression.MatchingOptions = [],
        with template: String
    ) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern, options: findingOptions)
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, options: replacingOptions, range: range, withTemplate: template)
    }
}

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
    private var aggregatedLogs: [String] = [] // Step 1: Property to store log messages

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

            var parsedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            parsedMessage = try! parsedMessage.replacingRegex(matching: ";", with: ", ")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "\\s?:\\s?,?", with: ": ")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "(\\w+: \\d+(?= [^,:\\s]+:))", with: "$1,")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "^[^\\w]*", with: "")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "(\\sset)?\\sto:?\\s+", with: ": ")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "(\\w+) is (\\w+)\\!?", with: "$1: $2")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "NaN \\(\\. (.+)\\)", with: "$1, ")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "Setting (.+) of (.*)", with: "$1: $2 ")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "(Using\\s|\\sused)", with: "")
            parsedMessage = try! parsedMessage.replacingRegex(
                matching: " instead of past 24 h \\((" + "(-?\\d+(\\.\\d+)?)" + " U)\\)",
                with: "weighted TDD average past 24h: $1"
            )
            parsedMessage = try! parsedMessage.replacingRegex(matching: "^(.+) \\((.+)\\)$", with: "$1: $2")
            parsedMessage = try! parsedMessage.replacingRegex(matching: "\\s?,\\s?$", with: "")

            // Step 2: Split parsedMessage by ',' and, then split by ':' to get the key-value pair
            // Step 3: Convert the key to a camelCased string
            parsedMessage.split(separator: ",").forEach { property in
                let keyPair = property.split(separator: ":")
                if keyPair.count != 2 {
                    self.aggregatedLogs.append("\"unknown\": \"\(property)\"")
                    return
                }
                let key = keyPair[0].trimmingCharacters(in: .whitespacesAndNewlines).pascalCased
                let value = keyPair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let keyPairResult = "\"\(key)\": \"\(value)\""
                self.aggregatedLogs.append("\(keyPairResult)")
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

        if !combinedLogs.isEmpty {
            // Check if combinedLogs is a valid JSON string. If so, print it as JSON, if not, print it as a string
            if let jsonData = "{\(combinedLogs)}".data(using: .utf8) {
                do {
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    _ = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
                    debug(.openAPS, "JavaScript log [JSON]: \n{\n\(combinedLogs)\n}")
                } catch {
                    debug(.openAPS, "JavaScript log: \(combinedLogs)")
                }
            } else {
                debug(.openAPS, "JavaScript log: \(combinedLogs)")
            }
        }
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
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
