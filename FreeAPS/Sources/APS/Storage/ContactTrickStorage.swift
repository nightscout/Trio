import CoreData
import Foundation
import SwiftUI
import Swinject

protocol ContactTrickStorage {
    func fetchContactTrickEntries() async -> [ContactTrickEntry]
    func storeContactTrickEntry(_ entry: ContactTrickEntry) async
    func updateContactTrickEntry(_ contactTrickEntry: ContactTrickEntry) async
    func deleteContactTrickEntry(_ objectID: NSManagedObjectID) async
}

final class BaseContactTrickStorage: ContactTrickStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /// Fetches all stored Contact Trick entries.
    ///
    /// The method retrieves `ContactTrickEntryStored` objects from Core Data, maps them to
    /// `ContactTrickEntry` objects, and returns the results.
    ///
    /// - Returns: An array of `ContactTrickEntry` objects.
    func fetchContactTrickEntries() async -> [ContactTrickEntry] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: ContactTrickEntryStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.all,
            key: "isDarkMode",
            ascending: false
        )

        return await backgroundContext.perform {
            guard let fetchedContactTrickEntries = results as? [ContactTrickEntryStored] else { return [] }

            return fetchedContactTrickEntries.compactMap { entry in
                ContactTrickEntry(
                    name: entry.name ?? "No name provided",
                    layout: ContactTrickLayout(rawValue: entry.layout ?? "Single") ?? .single,
                    ring: ContactTrickLargeRing(rawValue: entry.ring ?? "DontShowRing") ?? .none,
                    primary: ContactTrickValue(rawValue: entry.primary ?? "GlucoseContactValue") ?? .glucose,
                    top: ContactTrickValue(rawValue: entry.top ?? "NoneContactValue") ?? .none,
                    bottom: ContactTrickValue(rawValue: entry.bottom ?? "NoneContactValue") ?? .none,
                    contactId: entry.contactId?.string,
                    darkMode: entry.isDarkMode,
                    ringWidth: ContactTrickEntry.RingWidth(rawValue: Int(entry.ringWidth)) ?? .regular,
                    ringGap: ContactTrickEntry.RingGap(rawValue: Int(entry.ringGap)) ?? .small,
                    fontSize: ContactTrickEntry.FontSize(rawValue: Int(entry.fontSize)) ?? .regular,
                    secondaryFontSize: ContactTrickEntry.FontSize(rawValue: Int(entry.fontSizeSecondary)) ?? .small,
                    fontWeight: Font.Weight.fromString(entry.fontWeight ?? "regular"),
                    fontWidth: Font.Width.fromString(entry.fontWidth ?? "standard"),
                    managedObjectID: entry.objectID
                )
            }
        }
    }

    /// Stores a new Contact Trick entry.
    ///
    /// This method creates a new `ContactTrickEntryStored` object in the background context,
    /// populates its properties with the values from the provided `ContactTrickEntry`, and
    /// saves the context if changes exist.
    ///
    /// - Parameter contactTrickEntry: The `ContactTrickEntry` object to be stored.
    func storeContactTrickEntry(_ contactTrickEntry: ContactTrickEntry) async {
        await backgroundContext.perform {
            let newContactTrickEntry = ContactTrickEntryStored(context: self.backgroundContext)

            newContactTrickEntry.id = UUID()
            newContactTrickEntry.name = contactTrickEntry.name
            newContactTrickEntry.contactId = contactTrickEntry.contactId
            newContactTrickEntry.layout = contactTrickEntry.layout.rawValue
            newContactTrickEntry.ring = contactTrickEntry.ring.rawValue
            newContactTrickEntry.primary = contactTrickEntry.primary.rawValue
            newContactTrickEntry.top = contactTrickEntry.top.rawValue
            newContactTrickEntry.bottom = contactTrickEntry.bottom.rawValue
            newContactTrickEntry.isDarkMode = contactTrickEntry.darkMode
            newContactTrickEntry.ringWidth = Int16(contactTrickEntry.ringWidth.rawValue)
            newContactTrickEntry.ringGap = Int16(contactTrickEntry.ringGap.rawValue)
            newContactTrickEntry.fontSize = Int16(contactTrickEntry.fontSize.rawValue)
            newContactTrickEntry.fontSizeSecondary = Int16(contactTrickEntry.secondaryFontSize.rawValue)
            newContactTrickEntry.fontWidth = contactTrickEntry.fontWeight.asString
            newContactTrickEntry.fontWeight = contactTrickEntry.fontWidth.asString

            do {
                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Contact Trick Entry to Core Data with error: \(error.userInfo)"
                )
            }
        }
    }

    /// Updates an existing Contact Trick entry in Core Data.
    ///
    /// This method finds the existing `ContactTrickEntryStored` object by its `contactId` and updates
    /// its properties with the values from the provided `ContactTrickEntry`. If no matching entry exists,
    /// it does nothing.
    ///
    /// - Parameter contactTrickEntry: The `ContactTrickEntry` object with updated values.
    func updateContactTrickEntry(_ contactTrickEntry: ContactTrickEntry) async {
        await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<ContactTrickEntryStored> = ContactTrickEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "contactId == %@", contactTrickEntry.contactId ?? "")

            do {
                if let existingEntry = try self.backgroundContext.fetch(fetchRequest).first {
                    // Update the properties of the existing entry
                    existingEntry.name = contactTrickEntry.name
                    existingEntry.layout = contactTrickEntry.layout.rawValue
                    existingEntry.ring = contactTrickEntry.ring.rawValue
                    existingEntry.primary = contactTrickEntry.primary.rawValue
                    existingEntry.top = contactTrickEntry.top.rawValue
                    existingEntry.bottom = contactTrickEntry.bottom.rawValue
                    existingEntry.isDarkMode = contactTrickEntry.darkMode
                    existingEntry.ringWidth = Int16(contactTrickEntry.ringWidth.rawValue)
                    existingEntry.ringGap = Int16(contactTrickEntry.ringGap.rawValue)
                    existingEntry.fontSize = Int16(contactTrickEntry.fontSize.rawValue)
                    existingEntry.fontSizeSecondary = Int16(contactTrickEntry.secondaryFontSize.rawValue)
                    existingEntry.fontWeight = contactTrickEntry.fontWeight.asString
                    existingEntry.fontWidth = contactTrickEntry.fontWidth.asString

                    guard self.backgroundContext.hasChanges else { return }
                    try self.backgroundContext.save()
                } else {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) \(#file) \(#function) No matching Contact Trick Entry found to update."
                    )
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update Contact Trick Entry with error: \(error.userInfo)"
                )
            }
        }
    }

    /// Deletes a Contact Trick entry from Core Data.
    ///
    /// - Parameter objectID: The `NSManagedObjectID` of the object to delete.
    func deleteContactTrickEntry(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}
