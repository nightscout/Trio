import Foundation
import Testing
@testable import Trio

@Suite("SimpleLogReporter Tests", .serialized) struct SimpleLogReporterTests {
    let reporter = SimpleLogReporter()

    @Test("Log method does not crash with file operation exceptions") func testLogMethodRobustness() {
        // Given - normal logging operation
        let category = "TestCategory"
        let message = "Test message"
        let file = #file
        let function = #function
        let line = #line

        // When - logging should not throw exceptions
        #expect(throws: Never.self) {
            reporter.log(category, message, file: file, function: function, line: UInt(line))
        }
    }

    @Test("Log method creates log directory when missing") func testLogDirectoryCreation() {
        // Given - ensure log directory exists after logging
        let category = "TestCategory"
        let message = "Test message"

        // When
        reporter.log(category, message, file: #file, function: #function, line: UInt(#line))

        // Then - log directory should exist
        let logDirExists = FileManager.default.fileExists(atPath: SimpleLogReporter.logDir)
        #expect(logDirExists == true)
    }

    @Test("Log method creates log file when missing") func testLogFileCreation() {
        // Given - ensure log file exists after logging
        let category = "TestCategory"
        let message = "Test message"

        // When
        reporter.log(category, message, file: #file, function: #function, line: UInt(#line))

        // Then - log file should exist
        let logFileExists = FileManager.default.fileExists(atPath: SimpleLogReporter.logFile)
        #expect(logFileExists == true)
    }

    @Test("Multiple log calls do not crash") func testMultipleLogCalls() {
        // Given - multiple log calls
        let category = "TestCategory"
        let messages = ["Message 1", "Message 2", "Message 3"]

        // When - multiple logs should not crash
        #expect(throws: Never.self) {
            for message in messages {
                reporter.log(category, message, file: #file, function: #function, line: UInt(#line))
            }
        }
    }
}
