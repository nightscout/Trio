import ConnectIQ
import SwiftUI

extension ContactTrick {
    @Observable final class StateModel: BaseStateModel<Provider> {
        private(set) var syncInProgress = false
        private(set) var items: [Item] = []
        private(set) var changed: Bool = false

        @ObservationIgnored @Injected() var contactTrickManager: ContactTrickManager!

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            items = contactTrickManager.currentContacts.enumerated().map { index, contact in
                Item(
                    index: index,
                    entry: contact
                )
            }
            changed = false
        }

        func add() {
            let newItem = Item(
                index: items.count,
                entry: ContactTrickEntry()
            )

            items.append(newItem)
            changed = true
        }

        func update(_ atIndex: Int, _ value: ContactTrickEntry) {
            items[atIndex].entry = value
            changed = true
        }

        func remove(atOffsets: IndexSet) {
            items.remove(atOffsets: atOffsets)
            changed = true
        }

        func save() {
            syncInProgress = true
            let contacts = items.map { item -> ContactTrickEntry in
                item.entry
            }
//            provider.saveContacts(contacts)
//                .receive(on: DispatchQueue.main)
//                .sink { _ in
//                    self.syncInProgress = false
//                    self.changed = false
//                } receiveValue: { contacts in
//                    contacts.enumerated().forEach { index, item in
//                        self.items[index].entry = item
//                    }
//                }
//                .store(in: &lifetime)
        }
    }
}
