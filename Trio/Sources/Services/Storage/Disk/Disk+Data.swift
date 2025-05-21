import Foundation

public extension Disk {
    /// Save Data to disk
    ///
    /// - Parameters:
    ///   - value: Data to store to disk
    ///   - directory: user directory to store the file in
    ///   - path: file location to store the data (i.e. "Folder/file.mp4")
    /// - Throws: Error if there were any issues writing the given data to disk
    static func save(_ value: Data, to directory: Directory, as path: String) throws {
        do {
            let url = try createURL(for: path, in: directory)
            try createSubfoldersBeforeCreatingFile(at: url)
            try value.write(to: url, options: .atomic)
        } catch {
            throw error
        }
    }

    /// Retrieve data from disk
    ///
    /// - Parameters:
    ///   - path: path where data file is stored
    ///   - directory: user directory to retrieve the file from
    ///   - type: here for Swifty generics magic, use Data.self
    /// - Returns: Data retrieved from disk
    /// - Throws: Error if there were any issues retrieving the specified file's data
    static func retrieve(_ path: String, from directory: Directory, as _: Data.Type) throws -> Data {
        do {
            let url = try getExistingFileURL(for: path, in: directory)
            let data = try Data(contentsOf: url)
            return data
        } catch {
            throw error
        }
    }
}
