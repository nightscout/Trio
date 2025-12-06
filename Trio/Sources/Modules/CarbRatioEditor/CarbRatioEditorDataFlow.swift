import Foundation

enum CarbRatioEditor {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var rateIndex = 0
        var timeIndex = 0

        init(rateIndex: Int, timeIndex: Int) {
            self.rateIndex = rateIndex
            self.timeIndex = timeIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.timeIndex == rhs.timeIndex && lhs.rateIndex == rhs.rateIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(timeIndex)
            hasher.combine(rateIndex)
        }
    }
}

protocol CarbRatioEditorProvider: Provider {
    var profile: CarbRatios { get }
    func saveProfile(_ profile: CarbRatios)
}
