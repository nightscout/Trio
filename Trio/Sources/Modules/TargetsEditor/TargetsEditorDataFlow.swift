import Foundation

enum TargetsEditor {
    enum Config {}

    class Item: Identifiable, Hashable, Equatable {
        let id = UUID()
        var lowIndex = 0
        var highIndex = 0
        var timeIndex = 0

        init(lowIndex: Int, highIndex _: Int, timeIndex: Int) {
            self.lowIndex = lowIndex
            highIndex = lowIndex
            self.timeIndex = timeIndex
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.timeIndex == rhs.timeIndex && lhs.lowIndex == rhs.lowIndex && lhs.highIndex == rhs.highIndex
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(timeIndex)
            hasher.combine(lowIndex)
            hasher.combine(highIndex)
        }
    }
}

protocol TargetsEditorProvider: Provider {
    var profile: BGTargets { get }
    func saveProfile(_ profile: BGTargets)
}
