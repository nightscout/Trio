extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0 ..< len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i ..< j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }

    func uint16(at index: Int) -> UInt16 {
        var value: UInt16 = 0
        (self as NSData).getBytes(&value, range: NSRange(location: index, length: MemoryLayout<UInt16>.size))
        return UInt16(littleEndian: value)
    }

    mutating func addDate(at index: Int, date: Date, utc: Bool = true) {
        var date = date
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        if !utc {
            let delta = TimeInterval(
                TimeZone.current.secondsFromGMT(for: date) - TimeZone(identifier: "UTC")!
                    .secondsFromGMT(for: date)
            )
            date = date.addingTimeInterval(delta)
        }

        self[index] = UInt8((calendar.component(.year, from: date) - 2000) & 0xFF)
        self[index + 1] = UInt8(calendar.component(.month, from: date) & 0xFF)
        self[index + 2] = UInt8(calendar.component(.day, from: date) & 0xFF)
        self[index + 3] = UInt8(calendar.component(.hour, from: date) & 0xFF)
        self[index + 4] = UInt8(calendar.component(.minute, from: date) & 0xFF)
        self[index + 5] = UInt8(calendar.component(.second, from: date) & 0xFF)
    }

    func date(at index: Int, _ usingUtc: Bool) -> Date {
        let year = 2000 + Int(self[index])
        let month = Int(self[index + 1])
        let day = Int(self[index + 2])
        let hour = Int(self[index + 3])
        let min = Int(self[index + 4])
        let sec = Int(self[index + 5])

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = min
        components.second = sec

        var calendar = Calendar.current
        if usingUtc {
            calendar.timeZone = TimeZone(identifier: "UTC")!
        } else {
            calendar.timeZone = TimeZone.current
        }

        return calendar.date(from: components)!
    }
}
