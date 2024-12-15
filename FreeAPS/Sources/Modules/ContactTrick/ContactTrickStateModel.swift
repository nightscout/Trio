import ConnectIQ
import CoreData
import SwiftUI

extension ContactTrick {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var contactTrickStorage: ContactTrickStorage!
        var contactTrickEntries = [ContactTrickEntry]()
        private let contactManager = ContactManager()

        var units: GlucoseUnits = .mmolL

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
            let hasAccess = await contactManager.requestAccess()
            guard hasAccess else {
                print("No access to contacts.")
                return
            }

            // 2. Create the contact and retrieve its `identifier`.
            guard let contactId = await contactManager.createContact(name: name) else {
                print("Failed to create contact.")
                return
            }

            // 3. Update the entry with the `contactId`.
            var updatedEntry = entry
            updatedEntry.contactId = contactId

            // 4. Save the contact to Core Data.
            await addContactTrickEntry(updatedEntry)
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
                print("Contact does not have a valid ID.")
                return
            }

            // 1. Attempt to delete the contact from Apple Contacts.
            let contactDeleted = await contactManager.deleteContact(withIdentifier: contactId)
            if contactDeleted {
                print("Contact successfully deleted from Apple Contacts: \(contactId)")
            } else {
                print("Failed to delete contact from Apple Contacts. Check if it exists.")
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
        ///   - newName: The new name to assign to the contact.
        func updateContact(entry: ContactTrickEntry, newName: String) async {
            guard let contactId = entry.contactId else {
                print("Contact does not have a valid ID.")
                return
            }

            // 1. Update the contact in Apple Contacts.
            let contactUpdated = await contactManager.updateContact(withIdentifier: contactId, newName: newName)
            guard contactUpdated else {
                print("Failed to update contact in Apple Contacts.")
                return
            }

            // 2. Update the entry in Core Data.
            var updatedEntry = entry
            updatedEntry.name = newName // Update additional fields if needed.
            await updateContactTrick(updatedEntry)
        }

        /// Updates a Core Data entry.
        /// - Parameter entry: The updated ContactTrickEntry.
        func updateContactTrick(_ entry: ContactTrickEntry) async {
            await contactTrickStorage.updateContactTrickEntry(entry)
            await fetchContactTrickEntriesAndUpdateUI()
        }
    }
}
