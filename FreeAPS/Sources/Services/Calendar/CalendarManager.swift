import Combine
import CoreData
import EventKit
import Swinject

protocol CalendarManager {
    func requestAccessIfNeeded() async -> Bool
    func calendarIDs() -> [String]
    var currentCalendarID: String? { get set }
    func createEvent() async
}

final class BaseCalendarManager: CalendarManager, Injectable {
    private lazy var eventStore: EKEventStore = { EKEventStore() }()

    @Persisted(key: "CalendarManager.currentCalendarID") var currentCalendarID: String? = nil
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var storage: FileStorage!

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

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

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }

    private var iobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var cobFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        setupCurrentCalendar()

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        Task {
            await createEvent()
        }
        registerHandlers()
        registerSubscribers()
    }

    let backgroundContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    private func setupCurrentCalendar() {
        if currentCalendarID == nil {
            let calendars = eventStore.calendars(for: .event)
            if let defaultCalendar = calendars.first {
                currentCalendarID = defaultCalendar.title
            }
        }
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.createEvent()
            }
        }.store(in: &subscriptions)
    }

    private func registerSubscribers() {
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.createEvent()
                }
            }
            .store(in: &subscriptions)
    }

    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                #if swift(>=5.9)
                    if #available(iOS 17.0, *) {
                        EKEventStore().requestFullAccessToEvents { granted, error in
                            if let error = error {
                                print("Calendar access not granted: \(error)")
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            continuation.resume(returning: granted)
                        }
                    } else {
                        EKEventStore().requestAccess(to: .event) { granted, error in
                            if let error = error {
                                print("Calendar access not granted: \(error)")
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            continuation.resume(returning: granted)
                        }
                    }
                #else
                    EKEventStore().requestAccess(to: .event) { granted, error in
                        if let error = error {
                            print("Calendar access not granted: \(error)")
                            warning(.service, "Calendar access not granted", error: error)
                        }
                        continuation.resume(returning: granted)
                    }
                #endif
            }
        case .denied,
             .restricted:
            return false
        case .authorized:
            return true
        #if swift(>=5.9)
            case .fullAccess:
                return true
            case .writeOnly:
                if #available(iOS 17.0, *) {
                    return await withCheckedContinuation { continuation in
                        EKEventStore().requestFullAccessToEvents { granted, error in
                            if let error = error {
                                print("Calendar access not upgraded: \(error)")
                                warning(.service, "Calendar access not upgraded", error: error)
                            }
                            continuation.resume(returning: granted)
                        }
                    }
                } else {
                    return false
                }
        #endif
        @unknown default:
            warning(.service, "Unknown calendar access status")
            return false
        }
    }

    func calendarIDs() -> [String] {
        EKEventStore().calendars(for: .event).map(\.title)
    }

    private func getLastDetermination() async -> NSManagedObjectID? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["timestamp", "cob", "iob", "objectID"]
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [[String: Any]] /* , !fetchedResults.isEmpty */ else { return nil }

            return fetchedResults.first?["objectID"] as? NSManagedObjectID
        }
    }

    private func fetchGlucose() async -> [NSManagedObjectID] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "date",
            ascending: false,
            propertiesToFetch: ["objectID", "glucose"]
        )

        return await backgroundContext.perform {
            guard let fetchedResults = results as? [[String: Any]] else { return [] }

            return fetchedResults.compactMap { $0["objectID"] as? NSManagedObjectID }
        }
    }

    @MainActor func createEvent() async {
        guard settingsManager.settings.useCalendar, let calendar = currentCalendar,
              let determinationId = await getLastDetermination() else { return }

        let glucoseIds = await fetchGlucose()

        deleteAllEvents(in: calendar)

        do {
            guard let determinationObject = try viewContext.existingObject(with: determinationId) as? OrefDetermination
            else { return }

            let glucoseObjects = try glucoseIds.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }

            guard let lastGlucoseObject = glucoseObjects.first, let lastGlucoseValue = glucoseObjects.first?.glucose,
                  let secondLastReading = glucoseObjects.dropFirst().first?.glucose else { return }

            let delta = Decimal(lastGlucoseValue) - Decimal(secondLastReading)

            // create an event now
            let event = EKEvent(eventStore: eventStore)

            // Calendar settings
            let displayCOBandIOB = settingsManager.settings.displayCalendarIOBandCOB
            let displayEmojis = settingsManager.settings.displayCalendarEmojis

            // Latest Loop data
            var freshLoop: Double = 20
            var lastLoop: Date?
            if displayCOBandIOB || displayEmojis {
                lastLoop = determinationObject.timestamp
                freshLoop = -1 * (lastLoop?.timeIntervalSinceNow.minutes ?? 0)
            }

            var glucoseIcon = "🟢"
            if displayEmojis {
                glucoseIcon = Double(lastGlucoseValue) <= Double(settingsManager.settings.low) ? "🔴" : glucoseIcon
                glucoseIcon = Double(lastGlucoseValue) >= Double(settingsManager.settings.high) ? "🟠" : glucoseIcon
                glucoseIcon = freshLoop > 15 ? "🚫" : glucoseIcon
            }

            let glucoseText = glucoseFormatter
                .string(from: Double(
                    settingsManager.settings.units == .mmolL ? Int(lastGlucoseValue)
                        .asMmolL : Decimal(lastGlucoseValue)
                ) as NSNumber)!

            let directionText = lastGlucoseObject.directionEnum?.symbol ?? "↔︎"

            let deltaValue = settingsManager.settings.units == .mmolL ? Int(delta.asMmolL) : Int(delta)
            let deltaText = deltaFormatter.string(from: NSNumber(value: deltaValue)) ?? "--"

            let iobText = iobFormatter.string(from: (determinationObject.iob ?? 0) as NSNumber) ?? ""
            let cobText = cobFormatter.string(from: determinationObject.cob as NSNumber) ?? ""

            var glucoseDisplayText = displayEmojis ? glucoseIcon + " " : ""
            glucoseDisplayText += glucoseText + " " + directionText + " " + deltaText

            var iobDisplayText = ""
            var cobDisplayText = ""

            if displayCOBandIOB {
                if displayEmojis {
                    iobDisplayText += "💉"
                    cobDisplayText += "🥨"
                } else {
                    iobDisplayText += "IOB:"
                    cobDisplayText += "COB:"
                }
                iobDisplayText += " " + iobText
                cobDisplayText += " " + cobText
                event.location = iobDisplayText + " " + cobDisplayText
            }

            event.title = glucoseDisplayText
            event.notes = "Trio"
            event.startDate = Date()
            event.endDate = Date(timeIntervalSinceNow: 60 * 10)
            event.calendar = calendar

            try eventStore.save(event, span: .thisEvent)

        } catch {
            debugPrint(
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to create calendar event: \(error.localizedDescription)"
            )
        }
    }

    var currentCalendar: EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        guard calendars.isNotEmpty else { return nil }
        return calendars.first { $0.title == self.currentCalendarID }
    }

    private func deleteAllEvents(in calendar: EKCalendar) {
        let predicate = eventStore.predicateForEvents(
            withStart: Date(timeIntervalSinceNow: -24 * 3600),
            end: Date(),
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)

        for event in events {
            do {
                try eventStore.remove(event, span: .thisEvent)
            } catch {
                warning(.service, "Cannot remove calendar events", error: error)
            }
        }
    }
}

extension BloodGlucose.Direction {
    var symbol: String {
        switch self {
        case .tripleUp:
            return "↑↑↑"
        case .doubleUp:
            return "↑↑"
        case .singleUp:
            return "↑"
        case .fortyFiveUp:
            return "↗︎"
        case .flat:
            return "→"
        case .fortyFiveDown:
            return "↘︎"
        case .singleDown:
            return "↓"
        case .doubleDown:
            return "↓↓"
        case .tripleDown:
            return "↓↓↓"
        case .none:
            return "↔︎"
        case .notComputable:
            return "↔︎"
        case .rateOutOfRange:
            return "↔︎"
        }
    }
}
