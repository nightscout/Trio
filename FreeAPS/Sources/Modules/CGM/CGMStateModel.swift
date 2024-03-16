import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var cgmManager: FetchGlucoseManager!
        @Injected() var calendarManager: CalendarManager!

        @Published var setupCGM: Bool = false
        @Published var cgm: CGMType = .nightscout
        // @Published var transmitterID = ""
        @Published var uploadGlucose = true
        @Published var smoothGlucose = false
        @Published var createCalendarEvents = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil
        @Published var cgmTransmitterDeviceAddress: String? = nil

        override func subscribe() {
            cgm = settingsManager.settings.cgm
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()
            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

            subscribeSetting(\.useCalendar, on: $createCalendarEvents) { createCalendarEvents = $0 }
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    guard let self = self else { return }
                    guard self.cgmManager.cgmGlucoseSourceType != nil else {
                        self.settingsManager.settings.cgm = .nightscout
                        return
                    }
                    self.settingsManager.settings.cgm = value
                }
                .store(in: &lifetime)

            $createCalendarEvents
                .removeDuplicates()
                .flatMap { [weak self] ok -> AnyPublisher<Bool, Never> in
                    guard ok, let self = self else { return Just(false).eraseToAnyPublisher() }
                    return self.calendarManager.requestAccessIfNeeded()
                }
                .map { [weak self] ok -> [String] in
                    guard ok, let self = self else { return [] }
                    return self.calendarManager.calendarIDs()
                }
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.calendarIDs, on: self)
                .store(in: &lifetime)

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id.isNotEmpty else {
                        self?.calendarManager.currentCalendarID = nil
                        return
                    }
                    self?.calendarManager.currentCalendarID = id
                }
                .store(in: &lifetime)
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupCGM = false
        // if CGM was deleted
        if cgmManager.cgmGlucoseSourceType == nil {
            cgm = .nightscout
        }
        // refresh the upload options
        uploadGlucose = settingsManager.settings.uploadGlucose
        cgmManager.updateGlucoseSource()
    }
}

extension CGM.StateModel: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
        // Possibility add the dexcom number !
        if let dexcomG6Manager: G6CGMManager = manager as? G6CGMManager {
            UserDefaults.standard.dexcomTransmitterID = dexcomG6Manager.transmitter.ID

        } else if let dexcomG5Manager: G5CGMManager = manager as? G5CGMManager {
            UserDefaults.standard.dexcomTransmitterID = dexcomG5Manager.transmitter.ID
        }
        cgmManager.updateGlucoseSource()
    }

    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
        // nothing to do ?
    }
}
