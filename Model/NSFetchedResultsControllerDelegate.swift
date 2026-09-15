import CoreData

final class FetchedResultsControllerDelegate: NSObject, NSFetchedResultsControllerDelegate {
    var onContentChange: (() -> Void)?

    func controllerDidChangeContent(_: NSFetchedResultsController<any NSFetchRequestResult>) {
        onContentChange?()
    }
}
