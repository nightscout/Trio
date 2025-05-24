//
// Trio
// Router.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-05-24.
// Most contributions by kskandis and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Combine
import SwiftUI
import Swinject

enum MessageType: String {
    case info
    case warning
    case error
    case other
}

enum MessageSubtype: String {
    case pump
    case cgm
    case carb
    case glucose
    case algorithm
    case misc
}

struct MessageContent {
    var content: String
    var type: MessageType = .info
    var subtype: MessageSubtype = .algorithm
    var title: String = ""
    var useAPN: Bool = true
    var trigger: UNNotificationTrigger?
    var action: NotificationAction = .none
}

protocol Router {
    var mainModalScreen: CurrentValueSubject<Screen?, Never> { get }
    var mainSecondaryModalView: CurrentValueSubject<AnyView?, Never> { get }
    var alertMessage: PassthroughSubject<MessageContent, Never> { get }
    func view(for screen: Screen) -> AnyView
    func allowNotify(_ message: MessageContent, _ settings: TrioSettings) -> Bool
}

final class BaseRouter: Router {
    let mainModalScreen = CurrentValueSubject<Screen?, Never>(nil)
    let mainSecondaryModalView = CurrentValueSubject<AnyView?, Never>(nil)
    let alertMessage = PassthroughSubject<MessageContent, Never>()
    private let resolver: Resolver

    init(resolver: Resolver) {
        self.resolver = resolver
    }

    func view(for screen: Screen) -> AnyView {
        screen.view(resolver: resolver).asAny()
    }

    func allowNotify(_ message: MessageContent, _ settings: TrioSettings) -> Bool {
        if message.type == .error { return true }
        switch message.subtype {
        case .pump:
            guard settings.notificationsPump else { return false }
        case .cgm:
            guard settings.notificationsCgm else { return false }
        case .carb:
            guard settings.notificationsCarb else { return false }
        case .glucose:
            guard (
                message.type == .warning &&
                    settings.glucoseNotificationsOption == GlucoseNotificationsOption.onlyAlarmLimits
            ) ||
                settings.glucoseNotificationsOption == GlucoseNotificationsOption.alwaysEveryCGM else { return false }
        case .algorithm:
            guard settings.notificationsAlgorithm else { return false }
        case .misc:
            return true
        }
        return true
    }
}
