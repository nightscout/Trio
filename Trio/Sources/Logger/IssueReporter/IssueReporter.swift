import Foundation

protocol IssueReporter: AnyObject {
    /// Call this method in `applicationDidFinishLaunching()`.
    func setup()

    func setUserIdentifier(_: String?)

    func reportNonFatalIssue(withName: String, attributes: [String: String])

    func reportNonFatalIssue(withError: NSError)

    /// `date` is when the line was logged; reporters run later on the logger queue.
    func log(_ category: String, _ message: String, date: Date, file: String, function: String, line: UInt)

    /// Writes out anything the reporter has buffered and returns once it is persisted.
    func flush()
}

extension IssueReporter {
    /// Reporters that write through have nothing to flush.
    func flush() {}
}
