//
// Trio
// NotificationCenter.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Combine
import Foundation

protocol NotificationCenter {
    func addObserver(_ observer: Any, selector aSelector: Selector, name aName: NSNotification.Name?, object anObject: Any?)
    func post(_ notification: Notification)
    func post(name aName: NSNotification.Name, object anObject: Any?)
    func post(name aName: NSNotification.Name, object anObject: Any?, userInfo aUserInfo: [AnyHashable: Any]?)
    func removeObserver(_ observer: Any)
    func removeObserver(_ observer: Any, name aName: NSNotification.Name?, object anObject: Any?)

    @discardableResult func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping (Notification) -> Void
    ) -> NSObjectProtocol

    func publisher(for name: Notification.Name, object: AnyObject?) -> Foundation.NotificationCenter.Publisher
    func publisher(for name: Notification.Name) -> Foundation.NotificationCenter.Publisher
}

extension Foundation.NotificationCenter: NotificationCenter {
    func publisher(for name: Notification.Name) -> Foundation.NotificationCenter.Publisher {
        publisher(for: name, object: nil)
    }
}
