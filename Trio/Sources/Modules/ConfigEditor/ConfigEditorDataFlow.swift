enum ConfigEditor {
    enum Config {}
}

protocol ConfigEditorProvider: Provider {
    func save(_ value: RawJSON, as file: String)
    func load(file: String) -> RawJSON
}
