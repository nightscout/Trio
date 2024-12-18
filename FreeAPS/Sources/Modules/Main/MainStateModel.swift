import LoopKitUI
import SwiftMessages
import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider> {
        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published var isSecondaryModalPresented = false
        @Published var secondaryModalView: AnyView? = nil

        override func subscribe() {
            router.mainModalScreen
                .map { $0?.modal(resolver: self.resolver!) }
                .removeDuplicates { $0?.id == $1?.id }
                .receive(on: DispatchQueue.main)
                .sink { modal in
                    self.modal = modal
                    self.isModalPresented = modal != nil
                }
                .store(in: &lifetime)

            $isModalPresented
                .filter { !$0 }
                .sink { _ in
                    self.router.mainModalScreen.send(nil)
                }
                .store(in: &lifetime)

            router.alertMessage
                .receive(on: DispatchQueue.main)
                .sink { message in
                    var config = SwiftMessages.defaultConfig
                    let view = MessageView.viewFromNib(layout: .cardView)

                    let titleContent: String

                    view.configureContent(
                        title: "title",
                        body: NSLocalizedString(message.content, comment: "Info message"),
                        iconImage: nil,
                        iconText: nil,
                        buttonImage: nil,
                        buttonTitle: nil,
                        buttonTapHandler: nil
                    )

                    switch message.type {
                    case .info:
                        view.backgroundColor = .secondarySystemGroupedBackground
                        config.duration = .automatic

                        titleContent = NSLocalizedString("Info", comment: "Info title")
                    case .warning:
                        view.configureTheme(.warning, iconStyle: .subtle)
                        config.duration = .forever
                        view.button?.setImage(Icon.warningSubtle.image, for: .normal)
                        titleContent = NSLocalizedString("Warning", comment: "Warning title")
                        view.buttonTapHandler = { _ in
                            SwiftMessages.hide()
                        }
                    case .errorPump:
                        view.configureTheme(.error, iconStyle: .subtle)
                        config.duration = .forever
                        view.button?.setImage(Icon.errorSubtle.image, for: .normal)
                        titleContent = NSLocalizedString("Error", comment: "Error title")
                        view.buttonTapHandler = { _ in
                            SwiftMessages.hide()
                            // display the pump configuration immediatly
                            if let pump = self.provider.deviceManager.pumpManager,
                               let bluetooth = self.provider.bluetoothProvider
                            {
                                let view = PumpConfig.PumpSettingsView(
                                    pumpManager: pump,
                                    bluetoothManager: bluetooth,
                                    completionDelegate: self
                                ).asAny()
                                self.router.mainSecondaryModalView.send(view)
                            }
                        }
                    }

                    view.titleLabel?.text = titleContent
                    config.dimMode = .gray(interactive: true)

                    SwiftMessages.show(config: config, view: view)
                }
                .store(in: &lifetime)

            router.mainSecondaryModalView
                .receive(on: DispatchQueue.main)
                .sink { view in
                    self.secondaryModalView = view
                    self.isSecondaryModalPresented = view != nil
                }
                .store(in: &lifetime)

            $isSecondaryModalPresented
                .removeDuplicates()
                .filter { !$0 }
                .sink { _ in
                    self.router.mainSecondaryModalView.send(nil)
                }
                .store(in: &lifetime)
        }
    }
}

@available(iOS 16.0, *)
extension Main.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        // close the window
        router.mainSecondaryModalView.send(nil)
    }
}
