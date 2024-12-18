import Combine
import SwiftUI
import Swinject

enum MessageType {
    case info
    case warning
    case errorPump
}

struct MessageContent {
    var content: String
    var type: MessageType = .info
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
