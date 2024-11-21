import Combine
import Foundation

enum ContactTrick {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var index: Int = 0
        var entry: ContactTrickEntry

        init(index: Int, entry: ContactTrickEntry) {
            self.index = index
            self.entry = entry
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.index == rhs.index
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(index)
        }
    }
}

protocol ContactTrickProvider: Provider {
    var contacts: [ContactTrickEntry] { get }
    func saveContacts(_ contacts: [ContactTrickEntry]) -> AnyPublisher<[ContactTrickEntry], Error>
}
