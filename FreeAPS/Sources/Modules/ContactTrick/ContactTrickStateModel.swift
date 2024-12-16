import ConnectIQ
import CoreData
import SwiftUI

extension ContactTrick {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var contactTrickStorage: ContactTrickStorage!
        @ObservationIgnored @Injected() var contactTrickManager: ContactTrickManager!
        var contactTrickEntries = [ContactTrickEntry]()
        var units: GlucoseUnits = .mmolL

        var previewState: ContactTrickState {
            ContactTrickState(
                glucose: self.units == .mmolL ? "6,8" : "127",
                trend: "↗︎",
                delta: units == .mmolL ? "+0,3" : "+7",
                lastLoopDate: .now,
                iob: 6.1,
                iobText: "6,1",
                cob: 27.0,
                cobText: "27",
                eventualBG: units == .mmolL ? "8,9" : "163",
                maxIOB: 12.0,
                maxCOB: 120.0
            )
        }

        /// Subscribes to updates and initializes data fetching.
        override func subscribe() {
            units = settingsManager.settings.units
            Task {
                /// Initial fetch to fill the ContactTrickEntry array
                await fetchContactTrickEntriesAndUpdateUI()
            }
        }

        /// Fetches all ContactTrickEntries from Core Data.
        func fetchContactTrickEntriesAndUpdateUI() async {
            let entries = await contactTrickStorage.fetchContactTrickEntries()
            await MainActor.run {
                self.contactTrickEntries = entries
            }
        }

        /// Creates a new contact in Apple Contacts and saves it to Core Data.
        /// - Parameters:
        ///   - entry: The ContactTrickEntry to be saved.
        ///   - name: The name of the contact.
        func createAndSaveContactTrick(entry: ContactTrickEntry, name: String) async {
            // 1. Check for contact access permissions.
            let hasAccess = await contactTrickManager.requestAccess()
            guard hasAccess else {
                debugPrint("\(DebuggingIdentifiers.failed) No access to contacts.")
                return
            }

            // 2. Create the contact and retrieve its `identifier`.
            guard let contactId = await contactTrickManager.createContact(name: name) else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to create contact.")
                return
            }

            // 3. Update the entry with the `contactId`.
            var updatedEntry = entry
            updatedEntry.contactId = contactId

            // 4. Save the contact to Core Data.
            await addContactTrickEntry(updatedEntry)

            // 5. Update ContactTrickState and set the image for the newly created contact
            await contactTrickManager.updateContactTrickState()
            await contactTrickManager.setImageForContact(contactId: contactId)
        }

        /// Adds a ContactTrickEntry to Core Data.
        /// - Parameter entry: The ContactTrickEntry to be saved.
        func addContactTrickEntry(_ entry: ContactTrickEntry) async {
            await contactTrickStorage.storeContactTrickEntry(entry)
            await fetchContactTrickEntriesAndUpdateUI()
        }

        /// Deletes a contact from Apple Contacts and Core Data.
        /// - Parameter entry: The ContactTrickEntry representing the contact to be deleted.
        func deleteContact(entry: ContactTrickEntry) async {
            guard let contactId = entry.contactId else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact does not have a valid ID.")
                return
            }

            // 1. Attempt to delete the contact from Apple Contacts.
            let contactDeleted = await contactTrickManager.deleteContact(withIdentifier: contactId)
            if contactDeleted {
                debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully deleted from Apple Contacts: \(contactId)")
            } else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to delete contact from Apple Contacts. Check if it exists.")
            }

            // 2. Delete the entry from Core Data.
            if let objectID = entry.managedObjectID {
                await deleteContactTrick(objectID: objectID)
            }
        }

        /// Deletes a Core Data entry.
        /// - Parameter objectID: The Managed Object ID of the entry to be deleted.
        func deleteContactTrick(objectID: NSManagedObjectID) async {
            await contactTrickStorage.deleteContactTrickEntry(objectID)
            await fetchContactTrickEntriesAndUpdateUI()
        }

        /// Updates a contact in Apple Contacts and Core Data.
        /// - Parameters:
        ///   - entry: The ContactTrickEntry to be updated.
        func updateContact(with entry: ContactTrickEntry) async {
            guard let contactId = entry.contactId else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact does not have a valid ID.")
                return
            }

            // 1. Update the entry in Core Data.
            await updateContactTrick(entry)

            // 2. Update the contact in Apple Contacts.
            
            /// Update name
            let contactUpdated = await contactTrickManager
                .updateContact(withIdentifier: contactId, newName: entry.name) // TODO: - Probably not needed anymore
            
            guard contactUpdated else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to update contact.")
                return
            }
            
            /// Update state and image
            await contactTrickManager.updateContactTrickState()
            await contactTrickManager.setImageForContact(contactId: contactId)
        }

        /// Updates a Core Data entry.
        /// - Parameter entry: The updated ContactTrickEntry.
        func updateContactTrick(_ entry: ContactTrickEntry) async {
            await contactTrickStorage.updateContactTrickEntry(entry)
            await fetchContactTrickEntriesAndUpdateUI()
        }
    }
}
