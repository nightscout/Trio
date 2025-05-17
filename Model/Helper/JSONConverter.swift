import Foundation

class JSONConverter {
    /// this is temporarily used to parse the fetched Core Data objects to JSON in order to pass it to DetermineBasal()
    func convertToJSON<T: Encodable>(_ value: T?) -> String {
        guard let value = value else { return "" }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        do {
            let jsonData = try encoder.encode(value)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            debugPrint("\(DebuggingIdentifiers.failed) could not convert object to JSON: \(error)")
        }

        return "could not convert object to JSON"
    }
}
