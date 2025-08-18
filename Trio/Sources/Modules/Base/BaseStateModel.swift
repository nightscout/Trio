import Combine
import SwiftUI
import Swinject

protocol StateModel: ObservableObject {
    var resolver: Resolver? { get set }
    var isInitial: Bool { get set }
    func subscribe()
    func showModal(for screen: Screen?)
    func hideModal()
    func view(for screen: Screen) -> AnyView
}

class BaseStateModel<Provider>: StateModel, Injectable where Provider: Trio.Provider {
    @Injected() var router: Router!
    @Injected() var settingsManager: SettingsManager!
    var isInitial: Bool = true
    private(set) var provider: Provider!

    var resolver: Resolver? {
        didSet {
            if let resolver = resolver {
                injectServices(resolver)
                provider = Provider(resolver: resolver)
                subscribe()
            }
        }
    }

    var lifetime = Lifetime()

    func subscribe() {}

    func showModal(for screen: Screen?) {
        router.mainModalScreen.send(screen)
    }

    func hideModal() {
        router.mainModalScreen.send(nil)
        router.mainSecondaryModalView.send(nil)
    }

    func view(for screen: Screen) -> AnyView {
        router.view(for: screen)
    }

    func subscribeSetting<T: Equatable, U: Publisher>(
        _ keyPath: WritableKeyPath<TrioSettings, T>,
        on settingPublisher: U, initial: (T) -> Void, map: ((T) -> (T))? = nil, didSet: ((T) -> Void)? = nil
    ) where U.Output == T, U.Failure == Never {
        initial(settingsManager.settings[keyPath: keyPath])
        settingPublisher
            .removeDuplicates()
            .map(map ?? { $0 })
            .sink { [weak self] value in
                self?.settingsManager.settings[keyPath: keyPath] = value
                didSet?(value)
            }
            .store(in: &lifetime)
    }

    func subscribePreferencesSetting<T: Equatable, U: Publisher>(
        _ keyPath: WritableKeyPath<Preferences, T>,
        on preferencesPublisher: U, initial: (T) -> Void, map: ((T) -> (T))? = nil, didSet: ((T) -> Void)? = nil
    ) where U.Output == T, U.Failure == Never {
        initial(settingsManager.preferences[keyPath: keyPath])
        preferencesPublisher
            .removeDuplicates()
            .map(map ?? { $0 })
            .sink { [weak self] value in
                self?.settingsManager.preferences[keyPath: keyPath] = value
                didSet?(value)
            }
            .store(in: &lifetime)
    }
}
