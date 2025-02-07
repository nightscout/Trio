import Combine
import Foundation
import LoopKit
import SwiftUI
import Swinject

public class AlertPermissionsChecker: ObservableObject, Injectable {
    private lazy var cancellables = Set<AnyCancellable>()
    private var listeningToNotificationCenter = false

    @Published var notificationsDisabled: Bool = false

    init(resolver: Resolver) {
        injectServices(resolver)

        Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)

        Foundation.NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.check()
            }
            .store(in: &cancellables)
    }

    func checkNow() {
        check {
            // Note: we do this, instead of calling notificationCenterSettingsChanged directly, so that we only
            // get called when it _changes_.
            self.listenToNotificationCenter()
        }
    }

    private func check(then completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsDisabled = settings.alertSetting == .disabled
                completion?()
            }
        }
    }
}

extension AlertPermissionsChecker {
    private func listenToNotificationCenter() {
        if !listeningToNotificationCenter {
            $notificationsDisabled
                .receive(on: RunLoop.main)
                .removeDuplicates()
                .sink(receiveValue: notificationCenterSettingsChanged)
                .store(in: &cancellables)
            listeningToNotificationCenter = true
        }
    }

    private func notificationCenterSettingsChanged(_: Bool) {
        // TODO: Add processing for other actions in delegate AlertManager, InAppAlertScheduler, etc., from Loop
        debug(.default, "notificationCenterSettingsChanged")
    }
}
