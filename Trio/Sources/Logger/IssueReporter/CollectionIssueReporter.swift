import Foundation
import Swinject

protocol GroupedIssueReporter: IssueReporter {
    func add(reporters: [IssueReporter])
    func remove(reporter: IssueReporter)
}

final class CollectionIssueReporter: GroupedIssueReporter {
    private let reportersLock = NSRecursiveLock(label: "CollectionIssueReporter.reportersLock")
    private var reporters: [IssueReporter] = []

    func setup() {
        reportersLock.perform {
            reporters.forEach { $0.setup() }
        }
    }

    func setUserIdentifier(_ identifier: String?) {
        reportersLock.perform {
            reporters.forEach { $0.setUserIdentifier(identifier) }
        }
    }

    func reportNonFatalIssue(withName name: String, attributes: [String: String]) {
        reportersLock.perform {
            reporters.forEach { $0.reportNonFatalIssue(withName: name, attributes: attributes) }
        }
    }

    func reportNonFatalIssue(withError error: NSError) {
        reportersLock.perform {
            reporters.forEach { $0.reportNonFatalIssue(withError: error) }
        }
    }

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt) {
        reportersLock.perform {
            reporters.forEach { $0.log(category, message, file: file, function: function, line: line) }
        }
    }

    func add(reporters: [IssueReporter]) {
        reportersLock.perform {
            self.reporters.append(contentsOf: reporters)
        }
    }

    func remove(reporter: IssueReporter) {
        reportersLock.perform {
            reporters.removeAll { $0 === reporter }
        }
    }
}
