import Foundation
import Harmonize
import HarmonizeSemantics

enum TrioHarmonize {
    static var productionCode: On & Excluding {
        parsed
        return production
    }

    static var testCode: On & Excluding {
        parsed
        return tests
    }

    static var app: Excluding { productionCode.on("Trio/Sources") }
    static var coreDataModel: Excluding { productionCode.on("Model") }
    static var watchExtension: Excluding { productionCode.on("Trio Watch App Extension") }
    static var liveActivity: Excluding { productionCode.on("LiveActivity") }
    // Not `testCode.on("TrioTests")`: Harmonize applies its *Tests folder rule to paths relative to the `on` folder, which
    // drops the top-level test files.
    static var unitTests: HarmonizeScope { testCode.excluding("Trio Watch App Tests") }
    static var watchTests: HarmonizeScope { testCode.excluding("TrioTests") }

    static let projectRoot: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent(".harmonize.yaml").path) {
            precondition(url.path != "/", "No .harmonize.yaml above \(#filePath)")
            url.deleteLastPathComponent()
        }
        return url.standardizedFileURL
    }()

    private static let production = Harmonize.productionCode()
    private static let tests = Harmonize.testCode()

    // Swift Testing runs tests in parallel, and each scope touched first parses its files: seven tests racing to parse
    // the tree took eight times as long as one parse. Resolve the whole tree once, before any scope hands out files.
    private static let parsed: Void = {
        _ = production.sources()
        _ = tests.sources()
    }()
}

extension SwiftSourceCode {
    var relativePath: String {
        guard let path = filePath?.standardizedFileURL.path else { return "" }
        let root = TrioHarmonize.projectRoot.path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }
}
