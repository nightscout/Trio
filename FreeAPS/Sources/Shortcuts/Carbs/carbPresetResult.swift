import AppIntents
import Foundation

@available(iOS 16.0, *) struct carbPresetResult: AppEntity, Identifiable {
    static var defaultQuery = carbPresetResultQuery()

    var id: Int
    @Property(title: LocalizedStringResource("name", table: "ShortcutsDetail")) var name: String
    @Property(title: LocalizedStringResource("carbs", table: "ShortcutsDetail")) var carbs: Double
    @Property(title: LocalizedStringResource("fat", table: "ShortcutsDetail")) var fat: Double
    @Property(title: LocalizedStringResource("protein", table: "ShortcutsDetail")) var protein: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Presets"

    init(id: Int, name: String, carbs: Double, fat: Double, protein: Double) {
        self.id = id
        self.name = name
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
    }
}

@available(iOS 16.0, *) struct carbPresetResultQuery: EntityQuery {
    internal var intentRequest: CarbPresetIntentRequest

    init() {
        intentRequest = CarbPresetIntentRequest()
    }

    func entities(for identifiers: [carbPresetResult.ID]) throws -> [carbPresetResult] {
        try intentRequest.listPresetCarbs(identifiers)
    }

    func suggestedEntities() throws -> [carbPresetResult] {
        try intentRequest.listPresetCarbs()
    }
}
