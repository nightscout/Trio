import Foundation

extension NumberFormatter {
    func string(from number: Double) -> String? {
        string(from: NSNumber(value: number))
    }
}
