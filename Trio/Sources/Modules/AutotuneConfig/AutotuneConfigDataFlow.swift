import Combine

enum AutotuneConfig {
    enum Config {}
}

protocol AutotuneConfigProvider: Provider {
    var autotune: Autotune? { get }
    func deleteAutotune()
}
