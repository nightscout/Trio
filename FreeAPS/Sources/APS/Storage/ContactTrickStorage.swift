import CoreData
import Foundation
import SwiftUI
import Swinject

protocol ContactTrickStorage {
    func fetchContactTrickEntries() async -> [ContactTrickEntry]
    func storeContactTrickEntry(_ entry: ContactTrickEntry) async
    func deleteContactTrickEntry(_ objectID: NSManagedObjectID) async
}

final class BaseContactTrickStorage: ContactTrickStorage, Injectable {
    @Injected() private var settingsManager: SettingsManager!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func fetchContactTrickEntries() async -> [ContactTrickEntry] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: ContactTrickEntryStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.all,
            key: "contactId",
            ascending: false
        )

        guard let fetchedContactTrickEntries = results as? [ContactTrickEntryStored] else { return [] }

        return fetchedContactTrickEntries.map { entry in
            ContactTrickEntry(
                layout: ContactTrickLayout.init(rawValue: entry.layout ?? "Single") ?? .single,
                ring1: ContactTrickLargeRing.init(rawValue: entry.ring1 ?? "DontShowRing") ?? .none,
                primary: ContactTrickValue.init(rawValue: entry.primary ?? "GlucoseContactValue") ?? .glucose,
                top: ContactTrickValue.init(rawValue: entry.top ?? "NoneContactValue") ?? .none,
                bottom: ContactTrickValue.init(rawValue: entry.top ?? "NoneContactValue") ?? .none,
                contactId: entry.contactId?.string,
                darkMode: entry.isDarkMode,
                ringWidth: ContactTrickEntry.RingWidth.init(rawValue: Int(entry.ringWidth)) ?? .regular,
                ringGap: ContactTrickEntry.RingGap.init(rawValue: Int(entry.ringWidth)) ?? .small,
                fontSize: ContactTrickEntry.FontSize.init(rawValue: Int(entry.fontSize)) ?? .regular,
                secondaryFontSize: ContactTrickEntry.FontSize.init(rawValue: Int(entry.fontSize)) ?? .small,
                fontWeight: Font.Weight.fromString(entry.fontWeight ?? "regular"),
                fontWidth: Font.Width.fromString(entry.fontWidth ?? "standard")
            )
        }
    }

    func storeContactTrickEntry(_ contactTrickEntry: ContactTrickEntry) async {
        await backgroundContext.perform {
            let newContactTrickEntry = ContactTrickEntryStored(context: self.backgroundContext)

            newContactTrickEntry.id = UUID()
            newContactTrickEntry.contactId = contactTrickEntry.contactId
            newContactTrickEntry.layout = contactTrickEntry.layout.rawValue
            newContactTrickEntry.ring1 = contactTrickEntry.ring1.rawValue
            newContactTrickEntry.primary = contactTrickEntry.primary.rawValue
            newContactTrickEntry.top = contactTrickEntry.top.rawValue
            newContactTrickEntry.bottom = contactTrickEntry.bottom.rawValue
            newContactTrickEntry.contactId = contactTrickEntry.ring1.rawValue
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
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Contract Trick Entry to Core Data with error: \(error.userInfo)"
                )
            }
        }
    }

    func deleteContactTrickEntry(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}
