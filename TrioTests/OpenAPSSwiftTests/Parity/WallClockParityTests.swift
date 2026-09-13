import Foundation
import Testing
@testable import Trio

@Suite("Wall clock parity", .serialized) struct WallClockParityTests {
    private func referenceMinutes(_ date: Date) -> Int? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }

    private func referenceHour(_ date: Date) -> Int? {
        Calendar.current.dateComponents([.hour], from: date).hour
    }

    private func referenceMinutesWithPrecision(_ date: Date) -> Decimal? {
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second,
              let nanosecond = components.nanosecond
        else { return nil }
        let milliseconds = (Decimal(nanosecond) / 1_000_000).rounded()
        return Decimal(hour * 60 + minute) + Decimal(second) / Decimal(60) + milliseconds / Decimal(60000)
    }

    @Test("matches Calendar across DST transitions") func dstSweep() throws {
        // Europe/Berlin (pinned): spring-forward 2026-03-29, fall-back 2026-10-25
        let anchors: [TimeInterval] = [
            1_774_746_000, // 2026-03-29 02:00 UTC+1 vicinity
            1_792_890_000, // 2026-10-25 vicinity
            1_781_733_000, // an ordinary summer day
            1_768_432_800 // an ordinary winter day
        ]
        for anchor in anchors {
            var t = anchor - 26 * 3600
            while t < anchor + 26 * 3600 {
                let date = Date(timeIntervalSince1970: t)
                #expect(date.minutesSinceMidnight == referenceMinutes(date), "minutes @ \(t)")
                #expect(date.hourInLocalTime == referenceHour(date), "hour @ \(t)")
                t += 421.7 // odd stride so fractional seconds vary
            }
        }
    }

    @Test("precision variant matches Calendar") func precisionSweep() throws {
        let fractions: [Double] = [0, 0.0004, 0.0005, 0.25, 0.4999995, 0.5, 0.75, 0.999, 0.9999996]
        let bases: [TimeInterval] = [1_774_746_000, 1_792_890_000, 1_781_733_211, 1_768_432_800]
        for base in bases {
            for minuteOffset in stride(from: -900, through: 900, by: 7) {
                for fraction in fractions {
                    let t = base + Double(minuteOffset) * 60 + fraction
                    let date = Date(timeIntervalSince1970: t)
                    #expect(
                        date.minutesSinceMidnightWithPrecision == referenceMinutesWithPrecision(date),
                        "precision @ \(t)"
                    )
                }
            }
        }
    }
}
