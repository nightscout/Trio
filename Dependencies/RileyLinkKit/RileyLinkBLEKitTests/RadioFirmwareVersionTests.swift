//
//  RadioFirmwareVersionTests.swift
//  RileyLinkBLEKitTests
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import RileyLinkBLEKit

class RadioFirmwareVersionTests: XCTestCase {
    
    func testVersionParsing() {
        let version = RadioFirmwareVersion(versionString: "subg_rfspy 0.8")!

        XCTAssertEqual([0, 8], version.components)
    }
    
}
