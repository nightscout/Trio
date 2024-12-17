import Combine
import Contacts
import CoreData
import Swinject

protocol ContactTrickManager {
    func requestAccess() async -> Bool
    func createContact(name: String) async -> String?
    func deleteContact(withIdentifier identifier: String) async -> Bool
    func updateContact(withIdentifier identifier: String, newName: String) async -> Bool
    @MainActor func updateContactTrickState() async
    func setImageForContact(contactId: String) async
    func validateContactExists(withIdentifier identifier: String) async -> Bool
}

final class BaseContactTrickManager: NSObject, ContactTrickManager, Injectable {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var contactTrickStorage: ContactTrickStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var fileStorage: FileStorage!

    private let contactStore = CNContactStore()

    // Make it read-only from outside the class
    private(set) var state = ContactTrickState()

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    private var units: GlucoseUnits = .mgdL

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = settingsManager.settings.units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        return formatter
    }

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        units = settingsManager.settings.units
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.updateContactTrickState()
                    await self.updateContactImages()
                }
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    // MARK: - Core Data observation

    private func registerHandlers() {
        /*
         TODO: - Do we really need to update in both cases, i.e. when OrefDetermination entity AND GlucoseStored entity have received updates ?
         The main use case is showing glucose values and both updates happen ~ at the same time and if a new glucose value arrives the latest Determination gets fetched with that as well. Moreover, we don't need to update on Determination updates at all if the user hasn't chosen to display anything Determination related
         */
//
//        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
//            guard let self = self else { return }
//            Task {
//                await self.updateContactTrickState()
//                await self.updateContactImages()
//            }
//        }.store(in: &subscriptions)

        // Only needed for manual glucose entries
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.updateContactTrickState()
                await self.updateContactImages()
            }
        }.store(in: &subscriptions)
    }

    // MARK: - Core Data Fetches

    private func fetchlastDetermination() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: NSPredicate.enactedDetermination,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [OrefDetermination] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 3 /// We only need 1-3 values, depending on whether the user wants to show delta or not
        )

        return await backgroundContext.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                return []
            }

            return glucoseResults.map(\.objectID)
        }
    }

    private func getCurrentGlucoseTarget() async -> Decimal? {
        let now = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone.current

        let bgTargets = await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

        for (index, entry) in entries.enumerated() {
            guard let entryTime = dateFormatter.date(from: entry.start) else {
                print("Invalid entry start time: \(entry.start)")
                continue
            }

            let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
            let entryStartTime = calendar.date(
                bySettingHour: entryComponents.hour!,
                minute: entryComponents.minute!,
                second: entryComponents.second!,
                of: now
            )!

            let entryEndTime: Date
            if index < entries.count - 1,
               let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
            {
                let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                entryEndTime = calendar.date(
                    bySettingHour: nextEntryComponents.hour!,
                    minute: nextEntryComponents.minute!,
                    second: nextEntryComponents.second!,
                    of: now
                )!
            } else {
                entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
            }

            if now >= entryStartTime, now < entryEndTime {
                return entry.value
            }
        }

        return nil
    }

    // MARK: - Configure ContactTrickState in order to update ContactTrickImage

    /// Updates the `ContactTrickState` with the latest data from Core Data.
    /// This function fetches glucose values and determination entries, processes the data,
    /// and updates the `state` object, which represents the current contact trick state.
    /// - Important: This function must be called on the main actor to ensure thread safety. Otherwise, we would need to ensure thread safety by either using an actor or a perform closure
    @MainActor func updateContactTrickState() async {
        // Get NSManagedObjectIDs on backgroundContext
        let glucoseValuesIds = await fetchGlucose()
        let determinationIds = await fetchlastDetermination()

        // Get NSManagedObjects on MainActor
        let glucoseObjects: [GlucoseStored] = await CoreDataStack.shared
            .getNSManagedObject(with: glucoseValuesIds, context: viewContext)
        let determinationObjects: [OrefDetermination] = await CoreDataStack.shared
            .getNSManagedObject(with: determinationIds, context: viewContext)
        let lastDetermination = determinationObjects.last

        if let firstGlucoseValue = glucoseObjects.first {
            let value = settingsManager.settings.units == .mgdL
                ? Decimal(firstGlucoseValue.glucose)
                : Decimal(firstGlucoseValue.glucose).asMmolL

            state.glucose = Formatter.glucoseFormatter(for: units).string(from: value as NSNumber)
            state.trend = firstGlucoseValue.directionEnum?.symbol

            let delta = glucoseObjects.count >= 2
                ? Decimal(firstGlucoseValue.glucose) - Decimal(glucoseObjects.dropFirst().first?.glucose ?? 0)
                : 0
            let deltaConverted = settingsManager.settings.units == .mgdL ? delta : delta.asMmolL
            state.delta = deltaFormatter.string(from: deltaConverted as NSNumber)
        }

        state.lastLoopDate = lastDetermination?.timestamp

        state.iob = lastDetermination?.iob as? Decimal
        if let cobValue = lastDetermination?.cob {
            state.cob = Decimal(cobValue)
        } else {
            state.cob = 0
        }

        if let eventualBG = settingsManager.settings.units == .mgdL ? lastDetermination?
            .eventualBG : lastDetermination?
            .eventualBG?.decimalValue.asMmolL as NSDecimalNumber?
        {
            let eventualBGAsString = Formatter.decimalFormatterWithOneFractionDigit.string(from: eventualBG)
            state.eventualBG = eventualBGAsString.map { "⇢ " + $0 }
        }

        // TODO: workaround for now: set low value to 55, to have dynamic color shades between 55 and user-set low (approx. 70); same for high glucose
        let hardCodedLow = Decimal(55)
        let hardCodedHigh = Decimal(220)
        let isDynamicColorScheme = settingsManager.settings.glucoseColorScheme == .dynamicColor

        state.highGlucoseColorValue = isDynamicColorScheme ? hardCodedHigh : settingsManager.settings.highGlucose
        state.lowGlucoseColorValue = isDynamicColorScheme ? hardCodedLow : settingsManager.settings.lowGlucose
        state
            .targetGlucose = await getCurrentGlucoseTarget() ??
            (settingsManager.settings.units == .mgdL ? Decimal(100) : 100.asMmolL)
        state.glucoseColorScheme = settingsManager.settings.glucoseColorScheme
    }

    // MARK: - Interactions with CNContactStore API

    /// Checks if the app has access to the user's contacts.
    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Sets the image for a specific contact in Apple Contacts.
    /// This function fetches the associated `ContactTrickEntry` for the provided contact ID, generates an image
    /// based on the current `ContactTrickState`, and updates the contact in the user's Apple Contacts.
    /// - Parameter contactId: The unique identifier of the contact in Apple Contacts.
    /// - Important: This function should be called when a new contact is created and needs its initial image set.
    func setImageForContact(contactId: String) async {
        guard let contactEntry = await contactTrickStorage.fetchContactTrickEntries().first(where: { $0.contactId == contactId })
        else {
            debugPrint("\(DebuggingIdentifiers.failed) No matching ContactTrickEntry found for contact ID: \(contactId)")
            return
        }

        // Create image based on current state
        let newImage = await ContactPicture.getImage(contact: contactEntry, state: state)

        do {
            let predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])
            let contacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactImageDataKey as CNKeyDescriptor
                ]
            )

            guard let contact = contacts.first else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact with ID \(contactId) not found.")
                return
            }

            let mutableContact = contact.mutableCopy() as! CNMutableContact
            mutableContact.imageData = newImage.pngData()

            let saveRequest = CNSaveRequest()
            saveRequest.update(mutableContact)

            try contactStore.execute(saveRequest)

            debugPrint("\(DebuggingIdentifiers.succeeded) Image successfully set for contact ID: \(contactId)")
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Failed to set image for contact ID \(contactId): \(error)")
        }
    }

    /// Updates the images of all contacts stored in Core Data.
    /// This function iterates through all stored `ContactTrickEntry` objects, generates a new contact image
    /// based on the current `ContactTrickState`, and updates the image in the user's Apple Contacts.
    /// - Important: This function should be called whenever the `ContactTrickState` changes.
    func updateContactImages() async {
        // Iterate through all stored ContactTrickEntry objects
        for contactEntry in await contactTrickStorage.fetchContactTrickEntries() {
            // Ensure the contact has a valid contact ID
            guard let contactId = contactEntry.contactId else { continue }

            // Generate a new image for the contact based on the updated state
            let newImage = await ContactPicture.getImage(contact: contactEntry, state: state)

            do {
                // Fetch the existing contact from CNContactStore using its identifier
                let predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])
                let contacts = try contactStore.unifiedContacts(
                    matching: predicate,
                    keysToFetch: [
                        CNContactIdentifierKey as CNKeyDescriptor, // To identify the contact
                        CNContactImageDataKey as CNKeyDescriptor // To fetch current image data
                    ]
                )

                // Ensure the contact exists in the CNContactStore
                guard let contact = contacts.first else {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) Contact with ID \(contactId) and name \(contactEntry.name) not found."
                    )
                    continue
                }

                // Create a mutable copy of the contact to update its image
                let mutableContact = contact.mutableCopy() as! CNMutableContact
                mutableContact.imageData = newImage.pngData() // Set the new image data

                // Prepare a save request to update the contact
                let saveRequest = CNSaveRequest()
                saveRequest.update(mutableContact)

                // Execute the save request to persist the changes
                try contactStore.execute(saveRequest)

                debugPrint("\(DebuggingIdentifiers.succeeded) Updated contact image for \(contactId)")
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) Failed to update contact image for \(contactId): \(error)")
            }
        }
    }

    /// Creates a new contact in the Apple contact list or updates an existing one with the same name.
    /// - Parameter name: The name of the contact.
    /// - Returns: The `identifier` of the created/updated contact, or `nil` if an error occurs.
    func createContact(name: String) async -> String? {
        do {
            // First check if a contact with this name already exists
            let predicate = CNContact.predicateForContacts(matchingName: name)
            let existingContacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor
                ]
            )

            // If contact exists, return its identifier
            if let existingContact = existingContacts.first {
                debugPrint("Found existing contact with name: \(name)")
                return existingContact.identifier
            }

            // If no existing contact, create a new one
            let contact = CNMutableContact()
            contact.givenName = name

            let saveRequest = CNSaveRequest()
            saveRequest.add(contact, toContainerWithIdentifier: nil)

            try contactStore.execute(saveRequest)

            // Re-fetch to get the identifier
            let newContacts = try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            )

            guard let createdContact = newContacts.first else {
                debugPrint("\(DebuggingIdentifiers.failed) Contact creation failed: No contact found after save.")
                return nil
            }

            return createdContact.identifier
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error creating/finding contact: \(error)")
            return nil
        }
    }

    /// Validates if a contact still exists in iOS Contacts.
    func validateContactExists(withIdentifier identifier: String) async -> Bool {
        let store = CNContactStore()
        let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
        let keys = [CNContactIdentifierKey] as [CNKeyDescriptor]

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            return !contacts.isEmpty
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error validating contact: \(error)")
            return false
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
                debugPrint("\(DebuggingIdentifiers.failed) Contact with ID \(identifier) not found.")
                return false
            }

            // Contact found -> Delete it.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            let deleteRequest = CNSaveRequest()
            deleteRequest.delete(mutableContact)

            try contactStore.execute(deleteRequest)
            debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully deleted: \(identifier)")
            return true
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error deleting contact: \(error)")
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
                debugPrint("\(DebuggingIdentifiers.failed) Contact with ID \(identifier) not found.")
                return false
            }

            // Update the contact.
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            mutableContact.givenName = newName

            let updateRequest = CNSaveRequest()
            updateRequest.update(mutableContact)

            try contactStore.execute(updateRequest)
            debugPrint("\(DebuggingIdentifiers.succeeded) Contact successfully updated: \(identifier)")
            return true
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) Error updating contact: \(error)")
            return false
        }
    }
}
