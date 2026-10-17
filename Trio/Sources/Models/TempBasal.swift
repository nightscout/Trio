import Foundation

public struct TempBasal: JSON {
    public let duration: Int
    public let rate: Decimal
    public let temp: TempType
    public let timestamp: Date

    public init(duration: Int, rate: Decimal, temp: TempType, timestamp: Date) {
        self.duration = duration
        self.rate = rate
        self.temp = temp
        self.timestamp = timestamp
    }
}
