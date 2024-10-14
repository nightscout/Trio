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
    var subtype: MessageSubtype = .misc
    var title: String = ""
    var useAPN: Bool = true
    var trigger: UNNotificationTrigger? = nil
    var action: NotificationAction = .none
}

protocol Router {
    var mainModalScreen: CurrentValueSubject<Screen?, Never> { get }
    var mainSecondaryModalView: CurrentValueSubject<AnyView?, Never> { get }
    var alertMessage: PassthroughSubject<MessageContent, Never> { get }
    func view(for screen: Screen) -> AnyView
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
}
