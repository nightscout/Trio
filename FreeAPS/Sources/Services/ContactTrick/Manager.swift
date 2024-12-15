import Contacts

final class ContactManager {
    private let contactStore = CNContactStore()

    /// Checks if the app has access to the user's contacts.
    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Creates a new contact in the Apple contact list.
    /// - Parameter name: The name of the contact.
    /// - Returns: The generated `identifier` of the contact, or `nil` if an error occurs.
    func createContact(name: String) async -> String? {
        do {
            let contact = CNMutableContact()
            contact.givenName = name

            let saveRequest = CNSaveRequest()
            saveRequest.add(contact, toContainerWithIdentifier: nil)

            try contactStore.execute(saveRequest)

            // Re-fetch the contact to retrieve its `identifier`.
            let predicate = CNContact.predicateForContacts(matchingName: name)
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            )

            return contacts.first?.identifier // Return the `identifier`.
        } catch {
            print("Error creating contact: \(error)")
            return nil
        }
    }

    /// Deletes a contact from the Apple contact list using its `identifier`.
    /// - Parameter identifier: The unique identifier of the contact.
    /// - Returns: `true` if the contact was successfully deleted, `false` otherwise.
    func deleteContact(withIdentifier identifier: String) async -> Bool {
        do {
            // Attempt to find the contact using its identifier.
            let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            )

            guard let contact = contacts.first else {
                print("Contact with ID \(identifier) not found.")
                return false
            }

            // Contact found -> Delete it.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            let deleteRequest = CNSaveRequest()
            deleteRequest.delete(mutableContact)

            try contactStore.execute(deleteRequest)
            print("Contact successfully deleted: \(identifier)")
            return true
        } catch {
            print("Error deleting contact: \(error)")
            return false
        }
    }

    /// Updates an existing contact in the Apple contact list.
    /// - Parameters:
    ///   - identifier: The unique identifier of the contact.
    ///   - newName: The new name to assign to the contact.
    /// - Returns: `true` if the contact was successfully updated, `false` otherwise.
    func updateContact(withIdentifier identifier: String, newName: String) async -> Bool {
        do {
            // Search for the contact using its `identifier`.
            let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor
                ]
            )

            guard let contact = contacts.first else {
                print("Contact with ID \(identifier) not found.")
                return false
            }

            // Update the contact.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            mutableContact.givenName = newName // Example: Update the given name.

            let updateRequest = CNSaveRequest()
            updateRequest.update(mutableContact)

            try contactStore.execute(updateRequest)
            print("Contact successfully updated: \(identifier)")
            return true
        } catch {
            print("Error updating contact: \(error)")
            return false
        }
    }
}
