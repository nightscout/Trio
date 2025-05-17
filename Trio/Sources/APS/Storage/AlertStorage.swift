import Combine
import Foundation
import SwiftDate
import Swinject

protocol AlertObserver {
    func AlertDidUpdate(_ alerts: [AlertEntry])
}

protocol AlertHistoryStorage {
    func storeAlert(_ alerts: AlertEntry)
    func syncDate() -> Date
    func recentNotAck() -> [AlertEntry]
    func deleteAlert(identifier: String)
    func ackAlert(_ alert: Date, _ error: String?)
    func forceNotification()
    var alertNotAck: PassthroughSubject<Bool, Never> { get }
}

final class BaseAlertHistoryStorage: AlertHistoryStorage, Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseAlertsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    let alertNotAck = PassthroughSubject<Bool, Never>()

    init(resolver: Resolver) {
        injectServices(resolver)
        alertNotAck.send(recentNotAck().isNotEmpty)
    }

    func storeAlert(_ alert: AlertEntry) {
        processQueue.sync {
            let file = OpenAPS.Monitor.alertHistory
            var uniqEvents: [AlertEntry] = []
            self.storage.transaction { storage in
                storage.append(alert, to: file, uniqBy: \.issuedDate)
                uniqEvents = storage.retrieve(file, as: [AlertEntry].self)?
                    .filter { $0.issuedDate.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.issuedDate > $1.issuedDate } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
            alertNotAck.send(self.recentNotAck().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(uniqEvents)
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recentNotAck() -> [AlertEntry] {
        storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self)?
            .filter { $0.issuedDate.addingTimeInterval(1.days.timeInterval) > Date() && $0.acknowledgedDate == nil }
            .sorted { $0.issuedDate > $1.issuedDate } ?? []
    }

    func ackAlert(_ alert: Date, _ error: String?) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.issuedDate == alert }) else {
                return
            }

            if let error {
                allValues[entryIndex].errorMessage = error
            } else {
                allValues[entryIndex].acknowledgedDate = Date()
            }
            storage.save(allValues, as: OpenAPS.Monitor.alertHistory)
            alertNotAck.send(self.recentNotAck().isNotEmpty)
        }
    }

    func deleteAlert(identifier: String) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.alertIdentifier == identifier }) else {
                return
            }
            allValues.remove(at: entryIndex)
            storage.save(allValues, as: OpenAPS.Monitor.alertHistory)
            alertNotAck.send(self.recentNotAck().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(allValues)
            }
        }
    }

    func forceNotification() {
        processQueue.sync {
            let uniqEvents = storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self)?
                .filter { $0.issuedDate.addingTimeInterval(1.days.timeInterval) > Date() }
                .sorted { $0.issuedDate > $1.issuedDate } ?? []
            alertNotAck.send(self.recentNotAck().isNotEmpty)
            broadcaster.notify(AlertObserver.self, on: processQueue) {
                $0.AlertDidUpdate(uniqEvents)
            }
        }
    }
}
