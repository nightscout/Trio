//
// Trio
// IssueReporter.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

protocol IssueReporter: AnyObject {
    /// Call this method in `applicationDidFinishLaunching()`.
    func setup()

    func setUserIdentifier(_: String?)

    func reportNonFatalIssue(withName: String, attributes: [String: String])

    func reportNonFatalIssue(withError: NSError)

    func log(_ category: String, _ message: String, file: String, function: String, line: UInt)
}
