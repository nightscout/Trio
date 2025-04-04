import Combine
import Foundation
import JavaScriptCore

@testable import Trio

/// This class provides us with an implementation of trio-oref with a number of iob bugs that are fixed.
/// We can use this during testing to confirm that for an input that generated an error that a corrected
/// Javascript implementation would have produced the same results
final class OpenAPSFixed {
    private let jsWorker = JavaScriptWorker()

    func sortPumpHistory(pumpHistory: JSON) throws -> JSON {
        let pumpHistorySwift = try JSONBridge.pumpHistory(from: pumpHistory)
        return try JSONBridge.to(pumpHistorySwift.sorted(by: { $0.timestamp > $1.timestamp }))
    }

    func iobHistory(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON, zeroTempDuration: JSON) async throws -> JSON {
        let testBundle = Bundle(for: OpenAPSFixed.self)
        let pumphistory: JSON = try! sortPumpHistory(pumpHistory: pumphistory)
        let result = try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: "prepare/log.js"),
                    Script.fromTestingBundle(name: "iob-history.js", bundle: testBundle),
                    Script.fromTestingBundle(name: "iob-history-prepare.js", bundle: testBundle)
                ])

                let result = worker.call(function: "generate", with: [
                    pumphistory,
                    profile,
                    clock,
                    autosens,
                    zeroTempDuration
                ])
                continuation.resume(returning: result)
            }
        }
        return result
    }

    func iobJavascript(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) async -> OrefFunctionResult {
        do {
            let testBundle = Bundle(for: OpenAPSFixed.self)
            let pumphistory: JSON = try! sortPumpHistory(pumpHistory: pumphistory)
            let result = try await withCheckedThrowingContinuation { continuation in
                jsWorker.inCommonContext { worker in
                    worker.evaluateBatch(scripts: [
                        Script(name: "prepare/log.js"),
                        Script.fromTestingBundle(name: "iob.js", bundle: testBundle),
                        Script(name: "prepare/iob.js")
                    ])
                    let result = worker.call(function: "generate", with: [
                        pumphistory,
                        profile,
                        clock,
                        autosens
                    ])
                    continuation.resume(returning: result)
                }
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}

extension Script {
    static func fromTestingBundle(name: String, bundle: Bundle) -> Script {
        let body: String
        if let url = bundle.url(forResource: "\(name)", withExtension: "") {
            do {
                body = try String(contentsOf: url)
            } catch {
                print("Error loading script: \(error.localizedDescription)")
                body = "Error loading script"
            }
        } else {
            print("Resource not found: javascript/\(name)")
            body = "Resource not found"
        }
        return Script(name: name, body: body)
    }
}
