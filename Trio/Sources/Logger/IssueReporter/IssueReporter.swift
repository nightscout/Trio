import Foundation

protocol IssueReporter: AnyObject {
    /// Call this method in `applicationDidFinishLaunching()`.
    func setup()

    func setUserIdentifier(_: String?)

    func reportNonFatalIssue(withName: String, attributes: [String: String])

    func reportNonFatalIssue(withError: NSError)

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt)
}
