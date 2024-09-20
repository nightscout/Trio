class ColorSchemeManager: ObservableObject {
    @AppStorage("colorScheme") var selectedColorScheme: ColorSchemeOption = .system
    @Environment(\.colorScheme) var environmentColorScheme: ColorScheme?
    
    var effectiveColorScheme: ColorScheme? {
        switch selectedColorScheme {
        case .system:
            return environmentColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
