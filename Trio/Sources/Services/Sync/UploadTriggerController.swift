import CoreData
import Foundation

/// Watches a Core Data "not yet uploaded" set and fires `onChange` whenever that set
/// changes — items appearing (new data to upload) or dropping out (rows flagged as
/// uploaded). One instance per (entity, backend pipeline) pair.
///
/// Bound to the viewContext, the controller also picks up batch-inserted rows via the
/// persistent history merge in `CoreDataStack`. `start()` must run on the context's
/// queue (main for the viewContext).
final class UploadTriggerController {
    private let controller: NSFetchedResultsController<NSFetchRequestResult>
    private let delegate = FetchedResultsControllerDelegate()

    init(
        entityName: String,
        sortKey: String,
        predicate: NSPredicate,
        fetchBatchSize: Int? = nil,
        context: NSManagedObjectContext,
        onChange: @escaping () -> Void
    ) {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: true)]
        request.predicate = predicate
        if let fetchBatchSize {
            request.fetchBatchSize = fetchBatchSize
        }
        controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        delegate.onContentChange = onChange
        controller.delegate = delegate
    }

    /// Performs the initial fetch, after which the controller starts observing changes.
    @MainActor func start() throws {
        try controller.performFetch()
    }
}
