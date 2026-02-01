import Foundation

extension String {
    func capitalizingFirstLetter() -> String {
        prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = capitalizingFirstLetter()
    }

    func formattedHourMinuteFromTimeString() -> String {
        let input = DateFormatter()
        input.dateFormat = "HH:mm:ss"

        let output = DateFormatter()
        output.timeStyle = .short
        output.dateStyle = .none

        guard let date = input.date(from: self) else {
            return self
        }

        return output.string(from: date)
    }
}

extension LosslessStringConvertible {
    var string: String { .init(self) }
}

extension FloatingPoint where Self: LosslessStringConvertible {
    var decimal: Decimal? { Decimal(string: string) }
}
