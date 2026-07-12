import Foundation

// Extend Profile for easy ISF replacement
extension Profile {
    func withAutosensISF(_ autosens: Autosens) -> Profile {
        guard let newisf = autosens.newisf else { return self }
        var copy = self
        copy.sens = newisf
        return copy
    }
}
