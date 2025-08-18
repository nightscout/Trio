import Foundation
import Swinject

final class SecurityAssembly: Assembly {
    func assemble(container: Container) {
        container.register(UnlockManager.self) { _ in BaseUnlockManager() }
    }
}
