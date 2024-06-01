import Combine
import CoreData
import EventKit
import Swinject

protocol CalendarManager {
    func requestAccessIfNeeded() -> AnyPublisher<Bool, Never>
    func calendarIDs() -> [String]
    var currentCalendarID: String? { get set }
    func createEvent(for glucose: GlucoseStored, delta: Int)
}

final class BaseCalendarManager: CalendarManager, Injectable {
    private lazy var eventStore: EKEventStore = { EKEventStore() }()

    @Persisted(key: "CalendarManager.currentCalendarID") var currentCalendarID: String? = nil
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
        broadcaster.register(GlucoseObserver.self, observer: self)
        setupGlucose()
    }

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    func requestAccessIfNeeded() -> AnyPublisher<Bool, Never> {
        Future { promise in
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .notDetermined:
                #if swift(>=5.9)
                    if #available(iOS 17.0, *) {
                        EKEventStore().requestFullAccessToEvents(completion: { (granted: Bool, error: Error?) -> Void in
                            if let error = error {
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            promise(.success(granted))
                        })
                    } else {
                        EKEventStore().requestAccess(to: .event) { granted, error in
                            if let error = error {
                                warning(.service, "Calendar access not granted", error: error)
                            }
                            promise(.success(granted))
                        }
                    }
                #else
                    EKEventStore().requestAccess(to: .event) { granted, error in
                        if let error = error {
                            warning(.service, "Calendar access not granted", error: error)
                        }
                        promise(.success(granted))
                    }
                #endif
            case .denied,
                 .restricted:
                promise(.success(false))
            case .authorized:
                promise(.success(true))

            #if swift(>=5.9)
                case .fullAccess:
                    promise(.success(true))
                case .writeOnly:
                    if #available(iOS 17.0, *) {
                        EKEventStore().requestFullAccessToEvents(completion: { (granted: Bool, error: Error?) -> Void in
                            if let error = error {
                                print("Calendar access not upgraded")
                                warning(.service, "Calendar access not upgraded", error: error)
                            }
                            promise(.success(granted))
                        })
                    }
            #endif

            @unknown default:
                warning(.service, "Unknown calendar access status")
                promise(.success(false))
            }
        }.eraseToAnyPublisher()
    }

    func calendarIDs() -> [String] {
        EKEventStore().calendars(for: .event).map(\.title)
    }

    private func getLastDetermination() -> [OrefDetermination] {
        CoreDataStack.shared.fetchEntities(
            ofType: OrefDetermination.self,
            onContext: coredataContext,
            predicate: NSPredicate.predicateFor30MinAgo,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1,
            propertiesToFetch: ["timestamp", "cob", "iob"]
        )
    }

    func createEvent(for glucose: GlucoseStored, delta: Int) {
        guard settingsManager.settings.useCalendar else { return }

        guard let calendar = currentCalendar else { return }

        deleteAllEvents(in: calendar)

        let glucoseValue = glucose.glucose

        // create an event now
        let event = EKEvent(eventStore: eventStore)

        // Calendar settings
        let displeyCOBandIOB = settingsManager.settings.displayCalendarIOBandCOB
        let displayEmojis = settingsManager.settings.displayCalendarEmojis

        // Latest Loop data
        var freshLoop: Double = 20
        var lastLoop: Date?
        if displeyCOBandIOB || displayEmojis {
            lastLoop = getLastDetermination().first?.timestamp
            freshLoop = -1 * (lastLoop?.timeIntervalSinceNow.minutes ?? 0)
        }

        var glucoseIcon = "🟢"
        if displayEmojis {
            glucoseIcon = Double(glucoseValue) <= Double(settingsManager.settings.low) ? "🔴" : glucoseIcon
            glucoseIcon = Double(glucoseValue) >= Double(settingsManager.settings.high) ? "🟠" : glucoseIcon
            glucoseIcon = freshLoop > 15 ? "🚫" : glucoseIcon
        }

        let glucoseText = glucoseFormatter
            .string(from: Double(
                settingsManager.settings.units == .mmolL ? Int(glucoseValue)
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!

        let directionText = glucose.direction ?? "↔︎"

        let deltaValue = settingsManager.settings.units == .mmolL ? Int(delta.asMmolL) : delta
        let deltaText = deltaFormatter.string(from: NSNumber(value: deltaValue)) ?? "--"

        let iobText = iobFormatter.string(from: (getLastDetermination().first?.iob ?? 0) as NSNumber) ?? ""
        let cobText = cobFormatter.string(from: (getLastDetermination().first?.cob ?? 0) as NSNumber) ?? ""

        var glucoseDisplayText = displayEmojis ? glucoseIcon + " " : ""
        glucoseDisplayText += glucoseText + " " + directionText + " " + deltaText

        var iobDisplayText = ""
        var cobDisplayText = ""

        if displeyCOBandIOB {
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
        event.notes = "iAPS"
        event.startDate = Date()
        event.endDate = Date(timeIntervalSinceNow: 60 * 10)
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            warning(.service, "Cannot create calendar event", error: error)
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

    private func setupGlucose() {
        coredataContext.performAndWait {
            let results = CoreDataStack.shared.fetchEntities(
                ofType: GlucoseStored.self,
                onContext: coredataContext,
                predicate: NSPredicate.predicateFor30MinAgo,
                key: "date",
                ascending: false
            )

            guard results.count >= 2 else { return }

            if let lastGlucose = results.first,
               let secondLastReading = results.dropFirst().first?.glucose
            {
                let glucoseDelta = lastGlucose.glucose - secondLastReading
                self.createEvent(for: lastGlucose, delta: Int(glucoseDelta))
            } else {
                debugPrint("Failed to unwrap necessary glucose readings")
            }
        }
    }
}

extension BaseCalendarManager: GlucoseObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
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
