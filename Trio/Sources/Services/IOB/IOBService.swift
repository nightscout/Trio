import Combine
import CoreData
import Foundation
import Swinject

protocol IOBService {
    var iobPublisher: AnyPublisher<Decimal?, Never> { get }
    var currentIOB: Decimal? { get }
    func updateIOB()
}

/// The single source of truth for current IoB data
///
/// The main idea behind this class is that we want one single place to lookup IoB values that is separate
/// from determinations. Behind the scenes it uses determinations or IoB results stored in the file system
/// but these are implementation details that we can change with time.
///
// TODO: Calculate IoB using APSManager after enough time has elapsed from the last file or determination data
final class BaseIOBService: IOBService, Injectable {
    @Injected() private var fileStorage: FileStorage!
    @Injected() private var determinationStorage: DeterminationStorage!
    @Injected() private var apsManager: APSManager!

    private let iobSubject = CurrentValueSubject<Decimal?, Never>(nil)
    var iobPublisher: AnyPublisher<Decimal?, Never> {
        iobSubject.eraseToAnyPublisher()
    }

    // Query the current IOB syncrhonously
    var currentIOB: Decimal? {
        lookupIOB()
    }

    private var subscriptions = Set<AnyCancellable>()
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private let queue = DispatchQueue(label: "BaseIOBService.queue", qos: .background)
    private let context = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()
        subscribe()
    }

    private func subscribe() {
        // Trigger update when a new determination is available
        coreDataPublisher?.filteredByEntityName("OrefDetermination").sink { [weak self] _ in
            self?.updateIOB()
        }.store(in: &subscriptions)

        // Trigger update when the iob file is updated
        apsManager.iobFileDidUpdate
            .sink { [weak self] _ in
                self?.updateIOB()
            }
            .store(in: &subscriptions)
    }

    // Fetches the IoB and timestamp from the most recent determination
    private func fetchLatestDeterminationIOB() -> (iob: Decimal?, date: Date?) {
        var iob: Decimal?
        var date: Date?
        context.performAndWait {
            let request = OrefDetermination.fetchRequest() as NSFetchRequest<OrefDetermination>
            request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: false)]
            request.fetchLimit = 1
            if let determination = try? context.fetch(request).first {
                iob = determination.iob as? Decimal
                date = determination.deliverAt
            }
        }
        return (iob, date)
    }

    // Lookup IOB data from the file system and determinations core data, use the most
    // recent value
    func lookupIOB() -> Decimal? {
        let iobFromFile = fileStorage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        let iobFromFileValue = iobFromFile?.first?.iob
        let iobFromFileDate = iobFromFile?.first?.time

        let (iobFromDetermination, iobFromDeterminationDate) = fetchLatestDeterminationIOB()

        var mostRecentIOB: Decimal?

        if let iobFromFileValue = iobFromFileValue, let iobFromFileDate = iobFromFileDate {
            if let iobFromDetermination = iobFromDetermination, let iobFromDeterminationDate = iobFromDeterminationDate {
                if iobFromFileDate > iobFromDeterminationDate {
                    mostRecentIOB = iobFromFileValue
                } else {
                    mostRecentIOB = iobFromDetermination
                }
            } else {
                mostRecentIOB = iobFromFileValue
            }
        } else {
            mostRecentIOB = iobFromDetermination
        }

        return mostRecentIOB
    }

    func updateIOB() {
        Task {
            let mostRecentIOB = lookupIOB()
            if iobSubject.value != mostRecentIOB {
                iobSubject.send(mostRecentIOB)
            }
        }
    }
}
