import ConnectIQ
import CoreData
import SwiftUI

extension ContactImage {
    @Observable final class StateModel: BaseStateModel<Provider>, ContactImageManagerDelegate {
        @ObservationIgnored @Injected() var contactImageStorage: ContactImageStorage!
        @ObservationIgnored @Injected() var contactImageManager: ContactImageManager!

        var contactImageEntries = [ContactImageEntry]()
        var units: GlucoseUnits = .mmolL
        // Help Sheet
        var isHelpSheetPresented: Bool = false
        var helpSheetDetent = PresentationDetent.large

        // Current state for live preview
        var state = ContactImageState()

        /// Subscribes to updates and initializes data fetching.
        override func subscribe() {
            units = settingsManager.settings.units
            contactImageManager.delegate = self

            Task {
                /// Initial fetch to fill the ContactImageEntry array
                await fetchContactImageEntriesAndUpdateUI()

                // Initial state update is needed for preview
                await contactImageManager.updateContactImageState()
            }
        }

        func contactImageManagerDidUpdateState(_ state: ContactImageState) {
            Task { @MainActor in
                self.state = state
            }
        }

        /// Fetches all ContactImageEntries and validates them against iOS Contacts.
        func fetchContactImageEntriesAndUpdateUI() async {
            // 1. Get all entries from Core Data
            let cdEntries = await contactImageStorage.fetchContactImageEntries()

            // 2. Validate entries against iOS Contacts
            let validatedEntries = await validateEntries(cdEntries)

            // 3. Update UI with validated entries
            await MainActor.run {
                self.contactImageEntries = validatedEntries
            }
        }

        /// Validates entries against iOS Contacts and removes invalid ones
        private func validateEntries(_ entries: [ContactImageEntry]) async -> [ContactImageEntry] {
            var validated: [ContactImageEntry] = []

            for entry in entries {
                if let contactId = entry.contactId {
                    // Check if contact still exists in iOS Contacts
                    let exists = await contactImageManager.validateContactExists(withIdentifier: contactId)

                    if exists {
                        validated.append(entry)
                    } else {
                        // Contact was deleted in iOS, remove from Core Data
                        if let objectID = entry.managedObjectID {
                            await contactImageStorage.deleteContactImageEntry(objectID)
                            debugPrint("Removed orphaned contact entry: \(entry.name)")
                        }
                    }
                }
            }

            return validated
        }

        /// Creates a new contact in Apple Contacts and saves it to Core Data.
        /// - Parameters:
        ///   - entry: The ContactImageEntry to be saved.
        ///   - name: The name of the contact.
        func createAndSaveContactImage(entry: ContactImageEntry, name: String) async {
            // 1. Check for contact access permissions.
            let hasAccess = await contactImageManager.requestAccess()
            guard hasAccess else {
                debugPrint("\(DebuggingIdentifiers.failed) No access to contacts.")
                return
            }

            // 2. Create the contact and retrieve its `identifier`.
            guard let contactId = await contactImageManager.createContact(name: name) else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to create contact.")
                return
            }

            // 3. Update the entry with the `contactId`.
            var updatedEntry = entry
            updatedEntry.contactId = contactId
            updatedEntry.name = name

            // 4. Save the contact to Core Data.
            await addContactImageEntry(updatedEntry)

            // 5. Update ContactImageState and set the image for the newly created contact
            await contactImageManager.updateContactImageState()
            await contactImageManager.setImageForContact(contactId: contactId)
        }

        /// Adds a ContactImageEntry to Core Data.
        /// - Parameter entry: The ContactImageEntry to be saved.
        func addContactImageEntry(_ entry: ContactImageEntry) async {
            await contactImageStorage.storeContactImageEntry(entry)
            await fetchContactImageEntriesAndUpdateUI()
        }

        /// Deletes a contact from Apple Contacts and Core Data.
        /// - Parameter entry: The ContactImageEntry representing the contact to be deleted.
        func deleteContact(entry: ContactImageEntry) async {
            guard let contactId = entry.contactId else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact does not have a valid ID.")
                return
            }

            // 1. Attempt to delete the contact from Apple Contacts.
            let contactDeleted = await contactImageManager.deleteContact(withIdentifier: contactId)
            if contactDeleted {
                debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully deleted from Apple Contacts: \(contactId)")
            } else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to delete contact from Apple Contacts. Check if it exists.")
            }

            // 2. Delete the entry from Core Data.
            if let objectID = entry.managedObjectID {
                await deleteContactImage(objectID: objectID)
            }
        }

        /// Deletes a Core Data entry.
        /// - Parameter objectID: The Managed Object ID of the entry to be deleted.
        func deleteContactImage(objectID: NSManagedObjectID) async {
            await contactImageStorage.deleteContactImageEntry(objectID)
            await fetchContactImageEntriesAndUpdateUI()
        }

        /// Updates a contact in Apple Contacts and Core Data.
        /// - Parameters:
        ///   - entry: The ContactImageEntry to be updated.
        func updateContact(with entry: ContactImageEntry) async {
            guard let contactId = entry.contactId else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact does not have a valid ID.")
                return
            }

            // 1. Update the entry in Core Data.
            await updateContactImage(entry)

            // 2. Update the contact in Apple Contacts.

            /// Update name
            let contactUpdated = await contactImageManager
                .updateContact(withIdentifier: contactId, newName: entry.name) // TODO: - Probably not needed anymore

            guard contactUpdated else {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to update contact.")
                return
            }

            /// Update state and image
            await contactImageManager.updateContactImageState()
            await contactImageManager.setImageForContact(contactId: contactId)
        }

        /// Updates a Core Data entry.
        /// - Parameter entry: The updated ContactImageEntry.
        func updateContactImage(_ entry: ContactImageEntry) async {
            await contactImageStorage.updateContactImageEntry(entry)
            await fetchContactImageEntriesAndUpdateUI()
        }
    }
}
