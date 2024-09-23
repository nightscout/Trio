enum ColorSchemeOption: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case systemDefault
    case light
    case dark

    var displayName: String {
        switch self {
        case .systemDefault: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
