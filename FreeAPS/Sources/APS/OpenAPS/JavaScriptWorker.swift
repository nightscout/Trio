import Foundation
import JavaScriptCore

private let contextLock = NSRecursiveLock()

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
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty {
                self.aggregatedLogs.append(trimmedMessage)
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
        let patternsAndReplacements: [(pattern: String, replacement: String)] = [
            (
                "Middleware reason: (.*)",
                "\"middlewareReason\": \"$1\", "
            ),
            (
                "Pumphistory is empty!",
                "\"pumpHistory\": \"empty\", "
            ),
            (
                "insulinFactor set to : (-?\\d+(\\.\\d+)?)",
                "\"insulineFactor\": \"$1\", "
            ),
            (
                "Using weighted TDD average: (-?\\d+(\\.\\d+)?) U",
                "\"weightedTDDAverage\": \"$1\", "
            ),
            (
                ", instead of past 24 h \\((-?\\d+(\\.\\d+)?) U\\)",
                "\"past24TTDAverage\": \"$1\", "
            ),
            (
                ", weight: (-?\\d+(\\.\\d+)?)",
                "\"weight\": \"$1\", "
            ),
            (
                ", Dynamic ratios log: (.*)",
                "\"dynamicRatiosLog\": \"$1\", "
            ),
            (
                "Default Half Basal Target used: (-?\\d+(\\.\\d+)?) mmol/L",
                "\"halfBasalTarget\": \"$1\", "
            ),
            (
                "Autosens ratio: (-?\\d+(\\.\\d+)?);",
                "\"autosensRatio\": \"$1\", "
            ),
            (
                "Threshold set to (-?\\d+(\\.\\d+)?)",
                "\"threshold\": \"$1\", "
            ),
            (
                "ISF unchanged: (-?\\d+(\\.\\d+)?)",
                "\"isf\": \"$1\", " + "\"prevIsf\": \"$1\", "
            ),
            (
                "ISF from (-?\\d+(\\.\\d+)?) to (-?\\d+(\\.\\d+)?)",
                "\"isf\": \"$3\", " + "\"prevIsf\": \"$1\", "
            ),
            (
                "CR:(-?\\d+(\\.\\d+)?)",
                "\"cr\": \"$1\", "
            ),
            (
                "currenttemp:(-?\\d+(\\.\\d+)?) lastTempAge:(-?\\d+(\\.\\d+)?)m, tempModulus:(-?\\d+(\\.\\d+)?)m",
                "\"currenttemp\": \"$1\", " + "\"lastTempAge\": \"$3\", " + "\"tempModulus\": \"$5\", "
            ),
            (
                "SMB (\\w+) \\((.*)\\)",
                "\"smb\": \"$1\", " + "\"smbReason\": \"$2\", "
            ),
            (
                "profile.sens:(-?\\d+(\\.\\d+)?), sens:(-?\\d+(\\.\\d+)?), CSF:(-?\\d+(\\.\\d+)?)",
                "\"profileSens\": \"$1\", " + "\"sens\": \"$3\", " + "\"csf\": \"$5\", "
            ),
            (
                "Carb Impact:(-?\\d+(\\.\\d+)?)mg/dL per 5m; CI Duration:(-?\\d+(\\.\\d+)?)hours; remaining CI \\((-?\\d+(\\.\\d+)?)h peak\\):(-?\\d+(\\.\\d+)?)mg/dL per 5m",
                "\"carbImpact\": \"$1\", " + "\"carbImpactDuration\": \"$3\", " + "\"carbImpactRemainingTime\": \"$5\", " +
                    "\"carbImpactRemaining\": \"$7\", "
            ),
            (
                "UAM Impact:(-?\\d+(\\.\\d+)?)mg/dL per 5m; UAM Duration:(-?\\d+(\\.\\d+)?)hours",
                "\"uamImpact\": \"$1\", " + "\"uamImpactDuration\": \"$3\", "
            ),
            (
                "minPredBG: (-?\\d+(\\.\\d+)?) minIOBPredBG: (-?\\d+(\\.\\d+)?) minZTGuardBG: (-?\\d+(\\.\\d+)?)",
                "\"minPredBG\": \"$1\", " + "\"minIOBPredBG\": \"$3\", " + "\"minZTGuardBG\": \"$5\", "
            ),
            (
                "avgPredBG:(-?\\d+(\\.\\d+)?) COB\\/Carbs:(-?\\d+(\\.\\d+)?)\\/(-?\\d+(\\.\\d+)?)",
                "\"avgPredBG\": \"$1\", " + "\"cob\": \"$3\", " + "\"carbs\": \"$5\", "
            ),
            (
                "BG projected to remain above (-?\\d+(\\.\\d+)?) for (-?\\d+(\\.\\d+)?)minutes",
                "\"projectedBG\": \"$1\", " + "\"projectedBGDuration\": \"$3\", "
            ),
            (
                "naive_eventualBG:,(-?\\d+(\\.\\d+)?),bgUndershoot:,(-?\\d+(\\.\\d+)?),zeroTempDuration:,(-?\\d+(\\.\\d+)?),zeroTempEffect:,(-?\\d+(\\.\\d+)?),carbsReq:,(-?\\d+(\\.\\d+)?)",
                "\"naiveEventualBG\": \"$1\", " + "\"bgUndershoot\": \"$3\", " + "\"zeroTempDuration\": \"$5\", " +
                    "\"zeroTempEffect\": \"$7\", " + "\"carbsReq\": \"$9\", "
            ),
            (
                "(.*) \\(\\.? insulinReq: (-?\\d+(\\.\\d+)?) U\\)",
                "\"insulinReqReason\": \"$1\", " + "\"insulinReq\": \"$2\", "
            ),
            (
                "(.*) \\(\\.? insulinForManualBolus: (-?\\d+(\\.\\d+)?) U\\)",
                "\"insulinForManualBolusReason\": \"$1\", " + "\"insulinForManualBolus\": \"$2\", "
            ),
            (
                "Setting neutral temp basal of (-?\\d+(\\.\\d+)?)U/hr",
                "\"basalRate\": \"$1\"/hr', "
            )
        ]
        var combinedLogs = aggregatedLogs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        aggregatedLogs.removeAll()

        if !combinedLogs.isEmpty {
            // Apply each pattern and replace matches
            for (pattern, replacement) in patternsAndReplacements {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(combinedLogs.startIndex..., in: combinedLogs)
                    combinedLogs = regex.stringByReplacingMatches(
                        in: combinedLogs,
                        options: [],
                        range: range,
                        withTemplate: replacement
                    )
                } else {
                    error(.openAPS, "Invalid regex pattern: \(pattern)")
                }
            }

            // Check if combinedLogs is a valid JSON string. If so, print it as JSON, if not, print it as a string
            if let jsonData = "{\(combinedLogs)}".data(using: .utf8) {
                do {
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    let prettyPrintedData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
                    if let prettyPrintedString = String(data: prettyPrintedData, encoding: .utf8) {
                        debug(.openAPS, "JavaScript log [JSON]: \(prettyPrintedString)")
                    }
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
