import Combine
import LoopKitUI
import SwiftMessages
import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var apsManager: APSManager!
        @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
        @Injected() var broadcaster: Broadcaster!
        @Published var modal: Modal?
        @Published var secondaryModal: SecondaryModalWrapper?

        @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast
        private var timers: [TimeInterval: Timer] = [:]

        private func showTriggeredView(
            message: MessageContent,
            interval _: TimeInterval,
            config: SwiftMessages.Config,
            view: MessageView
        ) {
            view.customConfigureTheme(
                colorSchemePreference: colorSchemePreference
            )
            setupAction(message: message, view: view)

            SwiftMessages.show(config: config, view: view)
        }

        // Add or replace timer for a specific TimeInterval
        private func addOrReplaceTriggerTimer(message: MessageContent, config: SwiftMessages.Config, view: MessageView) {
            let trigger = message.trigger as! UNTimeIntervalNotificationTrigger
            guard trigger.timeInterval > 0 else { return }
            let interval = trigger.timeInterval

            SwiftMessages.hide(id: view.id)

            // If a timer already exists for this interval, invalidate it
            if let existingTimer = timers[interval] {
                existingTimer.invalidate()
            }

            // Create a new timer with the provided interval
            let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.showTriggeredView(message: message, interval: interval, config: config, view: view)
                self?.timers[interval] = nil
            }

            timers[interval] = newTimer
        }

        // Cancel all timers (optional cleanup method)
        private func cancelAllTimers() {
            timers.values.forEach { $0.invalidate() }
            timers.removeAll()
        }

        private func setupPumpConfig() {
            // display the pump configuration immediatly
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

        private func setupButton(message _: MessageContent, view: MessageView) {
            view.button?.setImage(UIImage(), for: .normal)
            view.iconLabel = nil
            let buttonImage = UIImage(systemName: "chevron.right")?.withTintColor(.white)
            view.button?.setImage(buttonImage, for: .normal)
            view.button?.backgroundColor = view.backgroundView.backgroundColor
            view.button?.tintColor = view.iconImageView?.tintColor
        }

        private func setupAction(message: MessageContent, view: MessageView) {
            switch message.action {
            case .snooze:
                setupButton(message: message, view: view)
                view.buttonTapHandler = { _ in
                    // Popup Snooze view when user taps on Glucose Notification
                    SwiftMessages.hide()
                    self.router.mainModalScreen.send(.snooze)
                }
            case .pumpConfig:
                setupButton(message: message, view: view)
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
                    self.setupPumpConfig()
                }
            default: // break
                view.button?.setImage(UIImage(), for: .normal)
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
                }
            }
        }

        private func isApnPumpConfigAction(_ message: MessageContent) -> Bool {
            if message.type != .error, message.action == .pumpConfig {
                setupPumpConfig()
                return true
            }
            return false
        }

        private func showAlertMessage(_ message: MessageContent) {
            if message.useAPN, !alertPermissionsChecker.notificationsDisabled
            {
                showAPN(message)
            } else {
                showSwiftMessage(message)
            }
        }

        private func showAPN(_ message: MessageContent) {
            DispatchQueue.main.async {
                self.broadcaster.notify(alertMessageNotificationObserver.self, on: .main) {
                    $0.alertMessageNotification(message)
                }
            }
        }

        // Read the color scheme preference from UserDefaults; defaults to system default setting
        @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

        private func showSwiftMessage(_ message: MessageContent) {
            if snoozeUntilDate > Date(), message.action == .snooze {
                return
            }

            var config = SwiftMessages.defaultConfig
            let view = MessageView.viewFromNib(layout: .cardView)

            view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            config.prefersStatusBarHidden = true

            // Set id so that multiple notifications are not queued while waiting for user response; only the latest will be shown
            if message.subtype == .glucose || message.subtype == .carb {
                view.id = message.type.rawValue + message.subtype.rawValue
            }

            let titleContent: String

            let iconName = UIApplication.shared.alternateIconName ?? "trioBlack"
            let iconImage = UIImage(named: iconName) ?? UIImage()

            view.configureContent(
                title: "title",
                body: message.content,
                iconImage: nil,
                iconText: nil,
                buttonImage: nil,
                buttonTitle: nil,
                buttonTapHandler: nil
            )

            view.configureIcon(withSize: CGSize(width: 40, height: 40), contentMode: .scaleAspectFit)
            view.iconImageView!.image = iconImage
            view.iconImageView?.layer.cornerRadius = 10

            view.customConfigureTheme(
                colorSchemePreference: colorSchemePreference
            )

            view.iconImageView?.image = iconImage

            switch message.type {
            case .info,
                 .other:
                config.duration = .seconds(seconds: 5)
                titleContent = message.title != "" ? message.title : String(localized: "Info", comment: "Info title")
            case .warning:
                config.duration = .forever
                titleContent = message.title != "" ? message
                    .title : String(localized: "Warning", comment: "Warning title")
            case .error:
                config.duration = .forever
                titleContent = message.title != "" ? message
                    .title : String(localized: "Error", comment: "Error title")
            }

            view.titleLabel?.text = titleContent
            config.dimMode = .gray(interactive: true)

            setupAction(message: message, view: view)
            if message.trigger != nil {
                addOrReplaceTriggerTimer(message: message, config: config, view: view)
            }

            guard message.type == .error || message.action != .pumpConfig, message.trigger == nil, !view.isHidden else { return }

            SwiftMessages.show(config: config, view: view)
        }

        /*
          Reclassification is needed for Medtronic pumps for 'Pump error:' RileyLink related messages.
          For details, see https://discord.com/channels/1020905149037813862/1338245444186279946/1343469793013141525.
          These messages are repeatedly displayed causing users to simply ignore them.
          Reclassification of these Info type messages is based on APSManager.APSError enum values.
          We reclassify APSError.pumpError and APSError.invalidPumpState as MessageType.info and MessageSubtype.pump.
          This allows the user to disable these messages using using the 'Trio Notification' -> 'Always Notify Pump' setting.
          MessageType.error messagges are always displayed to the user and the user cannot disable them.
          Other APSManager.APSError remain as MessageType.info which allows users to disable them
          using the 'Trio Notification' -> 'Always Notify Algorithm' setting.
         */

        func reclassifyInfoNotification(_ message: inout MessageContent) {
            if message.title == "" {
                switch message.type {
                case .info:
                    if message.content.range(of: "error", options: .caseInsensitive) != nil || message.content
                        .range(of: String(localized: "Error"), options: .caseInsensitive) != nil
                    {
                        message.title = String(localized: "Error", comment: "Error title")
                    } else {
                        message.title = String(localized: "Info", comment: "Info title")
                    }
                    if APSError.pumpWarningMatches(message: message.content) {
                        message.subtype = .pump
                        let lastLoopMinutes = Int((Date().timeIntervalSince(apsManager.lastLoopDate) - 30) / 60) + 1
                        if lastLoopMinutes > 10 {
                            message.type = .error
                        }
                    } else if APSError.pumpErrorMatches(message: message.content) {
                        message.subtype = .pump
                        message.type = .error
                    }
                case .warning:
                    message.title = String(localized: "Warning", comment: "Warning title")
                case .error:
                    message.title = String(localized: "Error", comment: "Error title")
                case .other:
                    message.title = String(localized: "Info", comment: "Info title")
                }
            }
        }

        override func subscribe() {
            router.mainModalScreen
                .map { $0?.modal(resolver: self.resolver!) }
                .removeDuplicates { $0?.id == $1?.id }
                .receive(on: DispatchQueue.main)
                .assign(to: &$modal)

            $modal
                .removeDuplicates { $0?.id == $1?.id }
                .filter { $0 == nil }
                .sink { _ in
                    self.router.mainModalScreen.send(nil)
                }
                .store(in: &lifetime)

            router.alertMessage
                .receive(on: DispatchQueue.main)
                .sink { message in
                    guard !self.isApnPumpConfigAction(message) else { return }
                    var reclassifyMessage = message
                    self.reclassifyInfoNotification(&reclassifyMessage)
                    guard self.router.allowNotify(reclassifyMessage, self.settingsManager.settings) else { return }
                    self.showAlertMessage(reclassifyMessage)
                }
                .store(in: &lifetime)

            router.mainSecondaryModalView
                .receive(on: DispatchQueue.main)
                .sink { view in
                    self.secondaryModal = view.map { SecondaryModalWrapper(view: $0) }
                }
                .store(in: &lifetime)

            $secondaryModal
                .removeDuplicates { $0?.id == $1?.id }
                .filter { $0 == nil }
                .sink { _ in
                    self.router.mainSecondaryModalView.send(nil)
                }
                .store(in: &lifetime)
        }
    }
}

extension MessageView {
    func currentColorScheme() -> ColorScheme {
        let userInterfaceStyle = UITraitCollection.current.userInterfaceStyle
        return userInterfaceStyle == .dark ? .dark : .light
    }

    func customConfigureTheme(colorSchemePreference: ColorSchemeOption) {
        let defaultSystemColorScheme = currentColorScheme()
        var backgroundColor = UIColor.systemBackground
        var foregroundColor = UIColor.white
        let ApnBackground = UIColor(named: "ApnBackground") ?? UIColor.lightGray
        let iOSlightTrioDark = UIColor(named: "ApnBackgroundLightDark") ?? UIColor.lightGray

        switch colorSchemePreference {
        case .systemDefault:
            backgroundColor = ApnBackground
            foregroundColor = UIColor.label
        case .dark:
            backgroundColor = defaultSystemColorScheme == .light ? iOSlightTrioDark : ApnBackground
            foregroundColor = defaultSystemColorScheme == .light ? UIColor.black : UIColor.white
        case .light:
            backgroundColor = defaultSystemColorScheme == .light ? ApnBackground : UIColor.gray
            foregroundColor = defaultSystemColorScheme == .light ? UIColor.black : UIColor.white
        }

        iconImageView?.tintColor = foregroundColor
        backgroundView.backgroundColor = backgroundColor
        titleLabel?.textColor = foregroundColor
        bodyLabel?.textColor = foregroundColor
        iconImageView?.isHidden = iconImageView?.image == nil

        backgroundView.layer.cornerRadius = 25

        let adjustedFont = UIFont.systemFont(ofSize: 13.0, weight: .bold)
        let preferredTitleFont = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: adjustedFont)
        let preferredBodyFont = UIFont.preferredFontforStyle(forTextStyle: .footnote)
        // Set the title and body font to the dynamic type sizes
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.font = preferredTitleFont
        bodyLabel?.adjustsFontForContentSizeCategory = true
        bodyLabel?.font = preferredBodyFont
        // Set custom colors for title and body text
        titleLabel?.textColor = foregroundColor
        bodyLabel?.textColor = foregroundColor
    }
}

@available(iOS 16.0, *)
extension Main.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        // close the window
        router.mainSecondaryModalView.send(nil)
    }
}

// Extension to convert SwiftUI TextStyle to UIFont
extension UIFont {
    static func preferredFontforStyle(forTextStyle: UIFont.TextStyle) -> UIFont {
        let uiFontMetrics = UIFontMetrics.default
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: forTextStyle)
        return uiFontMetrics.scaledFont(for: UIFont(descriptor: descriptor, size: 0))
    }
}
