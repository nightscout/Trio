import Combine
import LoopKitUI
import SwiftMessages
import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
        @Injected() var broadcaster: Broadcaster!
        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published var isSecondaryModalPresented = false
        @Published var secondaryModalView: AnyView? = nil

        private var storedMessages: [MessageContent] = []
        private let maxStoredMessages = 3
        private let maxNotificationsPerMinute = 3
        private var lastMessageTimestamp: Date?
        private var timer: AnyCancellable?
        private var timeInterval: TimeInterval = 1
        private let limitInterval: TimeInterval = 20
        private var lastNotificationTime: TimeInterval = 0
        private var sentNotifications: [TimeInterval] = []

        // Method to queue new message and check if it matches the "NOTE-*" pattern
        func queueMessageIfNeeded(_ message: MessageContent) {
            if message.type != MessageType.info {
                showAlertMessage(message)
                return
            }
            if !storedMessages.filter({ $0.content == message.content && $0.title == message.title }).isEmpty { return }

            storedMessages.append(message)
            lastMessageTimestamp = Date()

            // If we have accumulated messages, concatenate and display
            if storedMessages.count >= maxStoredMessages {
                checkAndDisplayStoredMessages()
            } else {
                startTimer()
            }
        }

        // Start or restart the timer that checks for the 1-minute interval
        private func startTimer() {
            timer = Timer.publish(every: timeInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.checkAndDisplayStoredMessages()
                }
        }

        // Method to check the stored messages and show them after 1 minute
        private func checkAndDisplayStoredMessages() {
            guard !storedMessages.isEmpty else { return }

            // Ensure rate limit is not exceeded
            let currentTime = Date().timeIntervalSince1970
            pruneOldNotifications(currentTime: currentTime)

            // Ensure we do not exceed maxNotificationsPerMinute
            if sentNotifications.count < maxNotificationsPerMinute {
                // If below the limit, send the next notification in the queue
                if !alertPermissionsChecker.notificationsDisabled {
                    let request = storedMessages.removeFirst()
                    showAlertMessage(request)
                    sentNotifications.append(currentTime)
                } else {
                    let max = storedMessages.count >= maxStoredMessages ? maxStoredMessages : storedMessages.count
                    var content = ""
                    for _ in 1 ... max {
                        let request = storedMessages.removeFirst()
                        sentNotifications.append(currentTime)
                        content = content + request.content + "\n"
                    }
                    if content != "" {
                        let messageCont = MessageContent(
                            content: content,
                            type: MessageType.other
                        )
                        showAlertMessage(messageCont)
                    }
                }
            }
        }

        // Remove notifications from the sent list that are older than `limitInterval`
        private func pruneOldNotifications(currentTime: TimeInterval) {
            // Remove any notifications older than `limitInterval`
            sentNotifications = sentNotifications.filter { currentTime - $0 < limitInterval }
        }

        private func showAlertMessage(_ message: MessageContent) {
            if message.useAPN, !alertPermissionsChecker.notificationsDisabled, message.type != MessageType.pumpConfig {
                showAPN(message)
            } else {
                showSwiftMessage(message)
            }
        }

        private func showAPN(_ message: MessageContent) {
            let messageCont = MessageContent(content: message.content, type: message.type)
            switch message.type {
            case .pumpConfig:
                if let pump = provider.deviceManager.pumpManager,
                   let bluetooth = provider.bluetoothProvider
                {
                    let view = PumpConfig.PumpSettingsView(
                        pumpManager: pump,
                        bluetoothManager: bluetooth,
                        completionDelegate: self
                    ).asAny()
                    router.mainSecondaryModalView.send(view)
                }
            default:
                DispatchQueue.main.async {
                    self.broadcaster.notify(alertMessageNotificationObserver.self, on: .main) {
                        $0.alertMessageNotification(messageCont)
                    }
                }
            }
        }

        private func showSwiftMessage(_ message: MessageContent) {
            // SwiftMessages.pauseBetweenMessages = 1.0
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
            case .info,
                 .other:
                view.backgroundColor = .secondarySystemGroupedBackground
                config.duration = .automatic
                titleContent = message.title != "" ? message.title : NSLocalizedString("Info", comment: "Info title")
            case .warning:
                view.configureTheme(.warning, iconStyle: .subtle)
                config.duration = .forever
                view.button?.setImage(Icon.warningSubtle.image, for: .normal)
                titleContent = message.title != "" ? message
                    .title : NSLocalizedString("Warning", comment: "Warning title")
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
                }
            case .errorPump:
                view.configureTheme(.error, iconStyle: .subtle)
                config.duration = .forever
                view.button?.setImage(Icon.errorSubtle.image, for: .normal)
                titleContent = message.title != "" ? message
                    .title : NSLocalizedString("Error", comment: "Error title")
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
            case .alertPermissionWarning:
                view.configureTheme(.error, iconStyle: .none)
                config.duration = .forever

                view.iconLabel = nil
                view.iconImageView = nil
                let disclosureIndicator = UIImage(systemName: "chevron.right")?.withTintColor(.white)
                view.button?.setImage(disclosureIndicator, for: .normal)
                view.button?.backgroundColor = UIColor.red
                view.button?.tintColor = UIColor.white

                titleContent = message.title != "" ? message
                    .title : NSLocalizedString("Error", comment: "Error title")
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
            case .pumpConfig:
                titleContent = ""
                if let pump = provider.deviceManager.pumpManager,
                   let bluetooth = provider.bluetoothProvider
                {
                    let view = PumpConfig.PumpSettingsView(
                        pumpManager: pump,
                        bluetoothManager: bluetooth,
                        completionDelegate: self
                    ).asAny()
                    router.mainSecondaryModalView.send(view)
                }
            }

            if message.type != .pumpConfig
            {
                view.titleLabel?.text = titleContent
                config.dimMode = .gray(interactive: true)
                // Show if not hidden
                if !view.isHidden {
                    SwiftMessages.show(config: config, view: view)
                }
            }
        }

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
                    self.queueMessageIfNeeded(message)
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
