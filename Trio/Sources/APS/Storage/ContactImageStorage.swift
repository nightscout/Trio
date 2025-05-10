import CoreData
import Foundation
import SwiftUI
import Swinject

protocol ContactImageStorage {
    func fetchContactImageEntries() async -> [ContactImageEntry]
    func storeContactImageEntry(_ entry: ContactImageEntry) async
    func updateContactImageEntry(_ contactImageEntry: ContactImageEntry) async
    func deleteContactImageEntry(_ objectID: NSManagedObjectID) async
}

final class BaseContactImageStorage: ContactImageStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    /// Fetches all stored Contact Trick entries.
    ///
    /// The method retrieves `ContactImageEntryStored` objects from Core Data, maps them to
    /// `ContactImageEntry` objects, and returns the results.
    ///
    /// - Returns: An array of `ContactImageEntry` objects.
    func fetchContactImageEntries() async -> [ContactImageEntry] {
        do {
            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: ContactImageEntryStored.self,
                onContext: backgroundContext,
                predicate: NSPredicate.all,
                key: "hasHighContrast",
                ascending: false
            )

            return try await backgroundContext.perform {
                guard let fetchedContactImageEntries = results as? [ContactImageEntryStored]
                else { throw CoreDataError.fetchError(function: #function, file: #file)
                }

                return fetchedContactImageEntries.compactMap { entry in
                    ContactImageEntry(
                        name: entry.name ?? String(localized: "No name provided"),
                        layout: ContactImageLayout(rawValue: entry.layout ?? "Default") ?? .default,
                        ring: ContactImageLargeRing(rawValue: entry.ring ?? "Hidden") ?? .none,
                        primary: ContactImageValue(rawValue: entry.primary ?? "Glucose Reading") ?? .glucose,
                        top: ContactImageValue(rawValue: entry.top ?? "None") ?? .none,
                        bottom: ContactImageValue(rawValue: entry.bottom ?? "None") ?? .none,
                        contactId: entry.contactId?.string,
                        hasHighContrast: entry.hasHighContrast,
                        ringWidth: ContactImageEntry.RingWidth(rawValue: Int(entry.ringWidth)) ?? .regular,
                        ringGap: ContactImageEntry.RingGap(rawValue: Int(entry.ringGap)) ?? .small,
                        fontSize: ContactImageEntry.FontSize(rawValue: Int(entry.fontSize)) ?? .regular,
                        secondaryFontSize: ContactImageEntry.FontSize(rawValue: Int(entry.fontSizeSecondary)) ?? .small,
                        fontWeight: Font.Weight.fromString(entry.fontWeight ?? "regular"),
                        fontWidth: Font.Width.fromString(entry.fontWidth ?? "standard"),
                        managedObjectID: entry.objectID
                    )
                }
            }
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Error fetching contact image entries: \(error)")
            return []
        }
    }

    /// Stores a new Contact Trick entry.
    ///
    /// This method creates a new `ContactImageEntryStored` object in the background context,
    /// populates its properties with the values from the provided `ContactImageEntry`, and
    /// saves the context if changes exist.
    ///
    /// - Parameter contactImageEntry: The `ContactImageEntry` object to be stored.
    func storeContactImageEntry(_ contactImageEntry: ContactImageEntry) async {
        await backgroundContext.perform {
            let newContactImageEntry = ContactImageEntryStored(context: self.backgroundContext)

            newContactImageEntry.id = UUID()
            newContactImageEntry.name = contactImageEntry.name
            newContactImageEntry.contactId = contactImageEntry.contactId
            newContactImageEntry.layout = contactImageEntry.layout.rawValue
            newContactImageEntry.ring = contactImageEntry.ring.rawValue
            newContactImageEntry.primary = contactImageEntry.primary.rawValue
            newContactImageEntry.top = contactImageEntry.top.rawValue
            newContactImageEntry.bottom = contactImageEntry.bottom.rawValue
            newContactImageEntry.hasHighContrast = contactImageEntry.hasHighContrast
            newContactImageEntry.ringWidth = Int16(contactImageEntry.ringWidth.rawValue)
            newContactImageEntry.ringGap = Int16(contactImageEntry.ringGap.rawValue)
            newContactImageEntry.fontSize = Int16(contactImageEntry.fontSize.rawValue)
            newContactImageEntry.fontSizeSecondary = Int16(contactImageEntry.secondaryFontSize.rawValue)
            newContactImageEntry.fontWidth = contactImageEntry.fontWeight.asString
            newContactImageEntry.fontWeight = contactImageEntry.fontWidth.asString

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
    /// This method finds the existing `ContactImageEntryStored` object by its `contactId` and updates
    /// its properties with the values from the provided `ContactImageEntry`. If no matching entry exists,
    /// it does nothing.
    ///
    /// - Parameter contactImageEntry: The `ContactImageEntry` object with updated values.
    func updateContactImageEntry(_ contactImageEntry: ContactImageEntry) async {
        await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<ContactImageEntryStored> = ContactImageEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "contactId == %@", contactImageEntry.contactId ?? "")

            do {
                if let existingEntry = try self.backgroundContext.fetch(fetchRequest).first {
                    // Update the properties of the existing entry
                    existingEntry.name = contactImageEntry.name
                    existingEntry.layout = contactImageEntry.layout.rawValue
                    existingEntry.ring = contactImageEntry.ring.rawValue
                    existingEntry.primary = contactImageEntry.primary.rawValue
                    existingEntry.top = contactImageEntry.top.rawValue
                    existingEntry.bottom = contactImageEntry.bottom.rawValue
                    existingEntry.hasHighContrast = contactImageEntry.hasHighContrast
                    existingEntry.ringWidth = Int16(contactImageEntry.ringWidth.rawValue)
                    existingEntry.ringGap = Int16(contactImageEntry.ringGap.rawValue)
                    existingEntry.fontSize = Int16(contactImageEntry.fontSize.rawValue)
                    existingEntry.fontSizeSecondary = Int16(contactImageEntry.secondaryFontSize.rawValue)
                    existingEntry.fontWeight = contactImageEntry.fontWeight.asString
                    existingEntry.fontWidth = contactImageEntry.fontWidth.asString

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
    func deleteContactImageEntry(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}
