import Algorithms
import Combine
import Contacts
import CoreData
import Foundation
import Swinject

protocol ContactTrickManager {
    func updateContacts(contacts: [ContactTrickEntry]) async -> Bool
    var currentContacts: [ContactTrickEntry] { get }
}

final class BaseContactTrickManager: NSObject, ContactTrickManager, Injectable {
    private var state = ContactTrickState()
    private let iOSContactStore = CNContactStore()

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var apsManager: APSManager!
    @Injected() private var contactTrickStorage: ContactTrickStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var eventualFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = settingsManager.settings.units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        formatter.negativePrefix = "-"
        return formatter
    }

    private var targetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    let context = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    private var lifetime = Lifetime()

    init(resolver: Resolver) {
        super.init()
        injectServices(resolver)
        registerHandlers()
        registerSubscribers()

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        Task {
            contacts = await contactTrickStorage.fetchContactTrickEntries()
        }

        knownIds = contacts.compactMap(\.contactId)

        Task {
            await configureContactTrickState()
        }

        broadcaster.register(SettingsObserver.self, observer: self)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.configureContactTrickState()
                }
            }
            .store(in: &subscriptions)
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("OrefDetermination").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.configureContactTrickState()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("CarbEntryStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.configureContactTrickState()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.configureContactTrickState()
            }
        }.store(in: &subscriptions)
    }

    private var knownIds: [String] = []
    private var contacts: [ContactTrickEntry] = []

    var currentContacts: [ContactTrickEntry] {
        contacts
    }

    private func fetchlastDetermination() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.enactedDetermination,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return await context.perform {
            guard let fetchedResults = results as? [OrefDetermination] else { return [] }

            return fetchedResults.map(\.objectID)
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor120MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 24,
            batchSize: 12
        )

        return await context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                return []
            }

            return glucoseResults.map(\.objectID)
        }
    }

    @MainActor private func configureContactTrickState() async {
        let glucoseValuesIds = await fetchGlucose()
        async let getLatestDeterminationIds = fetchlastDetermination()
        guard let lastDeterminationId = await getLatestDeterminationIds.first else {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to get last Determination")
            return
        }

        do {
            let glucoseValues: [GlucoseStored] = await CoreDataStack.shared
                .getNSManagedObject(with: glucoseValuesIds, context: viewContext)
            let lastDetermination = try viewContext.existingObject(with: lastDeterminationId) as? OrefDetermination

            await MainActor.run { [weak self] in
                guard let self = self else { return }

                if let firstGlucoseValue = glucoseValues.first {
                    let value = self.settingsManager.settings.units == .mgdL
                        ? Decimal(firstGlucoseValue.glucose)
                        : Decimal(firstGlucoseValue.glucose).asMmolL

                    self.state.glucose = self.glucoseFormatter.string(from: value as NSNumber)
                    self.state.trend = firstGlucoseValue.directionEnum?.symbol

                    let delta = glucoseValues.count >= 2
                        ? Decimal(firstGlucoseValue.glucose) - Decimal(glucoseValues.dropFirst().first?.glucose ?? 0)
                        : 0
                    let deltaConverted = self.settingsManager.settings.units == .mgdL ? delta : delta.asMmolL
                    self.state.delta = self.deltaFormatter.string(from: deltaConverted as NSNumber)
                }

                self.state.lastLoopDate = lastDetermination?.timestamp

                self.state.iob = lastDetermination?.iob as? Decimal
                if let cobValue = lastDetermination?.cob {
                    self.state.cob = Decimal(cobValue)
                } else {
                    self.state.cob = 0
                }

                if let eventualBG = self.settingsManager.settings.units == .mgdL ? lastDetermination?
                    .eventualBG : lastDetermination?
                    .eventualBG?.decimalValue.asMmolL as NSDecimalNumber?
                {
                    let eventualBGAsString = self.eventualFormatter.string(from: eventualBG)
                    self.state.eventualBG = eventualBGAsString.map { "⇢ " + $0 }
                }

//                guard (try? JSONEncoder().encode(state)) != nil else {
//                    warning(.service, "Cannot encode watch state")
//                    return
//                }

                if contacts.isNotEmpty, CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                    let newContacts = contacts.enumerated()
                        .map { index, entry in self.renderContact(entry, index + 1, self.state) }
                    
                    // TODO: existiert die zurück gegebene contact ID in CD
                    // wenn ja, eintrag ignorieren
                    // wemnn nein, eintrag neu einlegen
                
                    
                    if newContacts != contacts {
                        // when we create new contacts we store the IDs, in that case we need to write into the settings storage
                        for contactToStore in newContacts {
                            Task {
                                await self.contactTrickStorage.storeContactTrickEntry(contactToStore)
                            }
                        } }
                    contacts = newContacts
                }
            }

        } catch let error as NSError {
            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to configure state with error: \(error)")
        }
    }

    func updateContacts(contacts: [ContactTrickEntry]) async -> Bool {
        self.contacts = contacts
        let newIds = contacts.compactMap(\.contactId)
        let knownSet = Set(knownIds)
        let newSet = Set(newIds)
        let removedIds = knownSet.subtracting(newSet)

        return await context.perform {
            do {
                let fetchRequest: NSFetchRequest<ContactTrickEntryStored> = ContactTrickEntryStored.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "contactId IN %@", removedIds)
                let objectIDsToDelete = try self.viewContext.fetch(fetchRequest).compactMap(\.objectID)

                for objectID in objectIDsToDelete {
                    Task {
                        await self.contactTrickStorage.deleteContactTrickEntry(objectID)
                    }
                }

                Task {
                    await self.configureContactTrickState()
                }
                self.knownIds = self.contacts.compactMap(\.contactId)
                return true
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to delete Contact Trick Entry: \(error.userInfo)"
                )
                return false
            }
        }
    }

    private let keysToFetch = [
        CNContactImageDataKey,
        CNContactGivenNameKey,
        CNContactOrganizationNameKey
    ] as [CNKeyDescriptor]

    private func renderContact(_ _entry: ContactTrickEntry, _ index: Int, _ state: ContactTrickState) -> ContactTrickEntry {
        var entry = _entry
        let mutableContact: CNMutableContact
        let saveRequest = CNSaveRequest()

        if let contactId = entry.contactId {
            do {
                let contact = try iOSContactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

                mutableContact = contact.mutableCopy() as! CNMutableContact
                updateContactFields(entry: entry, index: index, state: state, mutableContact: mutableContact)
                saveRequest.update(mutableContact)
            } catch let error as NSError {
                if error.code == 200 { // 200: Updated Record Does Not Exist
                    print("in handleEnabledContact, failed to fetch the contact, code 200, contact does not exist")
                    mutableContact = createNewContact(
                        entry: entry,
                        index: index,
                        state: state,
                        saveRequest: saveRequest
                    )
                } else {
                    print("in handleEnabledContact, failed to fetch the contact - \(getContactsErrorDetails(error))")
                    return entry
                }
            } catch {
                print("in handleEnabledContact, failed to fetch the contact: \(error.localizedDescription)")
                return entry
            }
        } else {
            print("no contact \(index) - creating")
            mutableContact = createNewContact(
                entry: entry,
                index: index,
                state: state,
                saveRequest: saveRequest
            )
        }

        executeSaveRequest(saveRequest)

        entry.contactId = mutableContact.identifier

        return entry
    }

    private func createNewContact(
        entry: ContactTrickEntry,
        index: Int,
        state: ContactTrickState,
        saveRequest: CNSaveRequest
    ) -> CNMutableContact {
        let mutableContact = CNMutableContact()
        updateContactFields(
            entry: entry, index: index, state: state, mutableContact: mutableContact
        )
        print("creating a new contact, \(mutableContact.identifier)")
        saveRequest.add(mutableContact, toContainerWithIdentifier: nil)
        return mutableContact
    }

    private func updateContactFields(
        entry: ContactTrickEntry,
        index: Int,
        state: ContactTrickState,
        mutableContact: CNMutableContact
    ) {
        mutableContact.givenName = "Trio \(index)"
        mutableContact
            .organizationName =
            "Created and managed by Trio - \(Date().formatted(date: .abbreviated, time: .shortened))"

        mutableContact.imageData = ContactPicture.getImage(
            contact: entry,
            state: state
        ).pngData()
    }

    private func deleteContact(_ contactId: String) -> Bool {
        do {
            print("deleting contact \(contactId)")
            let keysToFetch = [CNContactIdentifierKey as CNKeyDescriptor] // we don't really need any, so just ID
            let contact = try iOSContactStore.unifiedContact(withIdentifier: contactId, keysToFetch: keysToFetch)

            guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
                print("in deleteContact, failed to get a mutable copy of the contact")
                return false
            }

            let saveRequest = CNSaveRequest()
            saveRequest.delete(mutableContact)
            try iOSContactStore.execute(saveRequest)
            return true
        } catch let error as NSError {
            if error.code == 200 { // Updated Record Does Not Exist
                return true
            } else {
                print("in deleteContact, failed to update the contact - \(getContactsErrorDetails(error))")
                return false
            }
        } catch {
            print("in deleteContact, failed to update the contact: \(error.localizedDescription)")
            return false
        }
    }

    private func executeSaveRequest(_ saveRequest: CNSaveRequest) {
        do {
            try iOSContactStore.execute(saveRequest)
        } catch let error as NSError {
            print("in updateContact, failed to update the contact - \(getContactsErrorDetails(error))")
        } catch {
            print("in updateContact, failed to update the contact: \(error.localizedDescription)")
        }
    }

    private func getContactsErrorDetails(_ error: NSError) -> String {
        var details: String?
        if error.domain == CNErrorDomain {
            switch error.code {
            case CNError.authorizationDenied.rawValue:
                details = "Authorization denied"
            case CNError.communicationError.rawValue:
                details = "Communication error"
            case CNError.insertedRecordAlreadyExists.rawValue:
                details = "Record already exists"
            case CNError.dataAccessError.rawValue:
                details = "Data access error"
            default:
                details = "Code \(error.code)"
            }
        }
        return "\(details ?? "no details"): \(error.localizedDescription)"
    }

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settingsManager.settings.units

        var low = target.targetBottom
        var high = target.targetTop
        if units == .mmolL {
            low = low?.asMmolL
            high = high?.asMmolL
        }

        let description =
            "\(targetFormatter.string(from: (low ?? 0) as NSNumber)!) - \(targetFormatter.string(from: (high ?? 0) as NSNumber)!)" +
            " for \(targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }
}

extension BaseContactTrickManager:
    SettingsObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
        Task {
            await configureContactTrickState()
        }
    }
}
