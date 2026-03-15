struct ExportSetting: Codable {
    let category: String
    let subcategory: String
    let name: String
    let value: String
    let unit: String

    init(category: String, subcategory: String = "", name: String, value: String, unit: String = "") {
        self.category = category
        self.subcategory = subcategory
        self.name = name
        self.value = value
        self.unit = unit
    }
}

struct ExportSettingPayload: Codable {
    let exportFormat: String
    let exportDate: String
    let settings: [ExportSetting]
}
