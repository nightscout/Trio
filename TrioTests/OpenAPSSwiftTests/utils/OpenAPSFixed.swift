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

    func mealJavascript(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON
    ) async -> OrefFunctionResult {
        let testBundle = Bundle(for: OpenAPSFixed.self)
        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                jsWorker.inCommonContext { worker in
                    worker.evaluateBatch(scripts: [
                        Script(name: "prepare/log.js"),
                        Script.fromTestingBundle(name: "meal.js", bundle: testBundle),
                        Script(name: "prepare/meal.js")
                    ])
                    let result = worker.call(function: "generate", with: [
                        pumphistory,
                        profile,
                        clock,
                        glucose,
                        basalProfile,
                        carbs
                    ])
                    continuation.resume(returning: result)
                }
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func autosenseJavascript(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON,
        clock: JSON
    ) async -> OrefFunctionResult {
        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                let testBundle = Bundle(for: OpenAPSFixed.self)
                jsWorker.inCommonContext { worker in
                    worker.evaluateBatch(scripts: [
                        Script(name: "prepare/log.js"),
                        Script.fromTestingBundle(name: "autosens.js", bundle: testBundle),
                        Script.fromTestingBundle(name: "autosens-prepare.js", bundle: testBundle)
                    ])
                    let result = worker.call(function: "generate", with: [
                        glucose,
                        pumpHistory,
                        basalprofile,
                        profile,
                        carbs,
                        temptargets,
                        clock
                    ])
                    continuation.resume(returning: result)
                }
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
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
            testPrintAllJSFiles(testBundle: bundle)
            body = "Resource not found"
        }
        return Script(name: name, body: body)
    }

    static func testPrintAllJSFiles(testBundle: Bundle) {
        // Get all .js files in the bundle
        if let jsURLs = testBundle.urls(forResourcesWithExtension: "js", subdirectory: nil) {
            print("JavaScript files in test bundle:")
            for jsURL in jsURLs {
                print("- \(jsURL.lastPathComponent)")
                print("  Full path: \(jsURL.path)")
            }
            print("Total JS files found: \(jsURLs.count)")
        } else {
            print("No JavaScript files found in test bundle")
        }
    }
}
