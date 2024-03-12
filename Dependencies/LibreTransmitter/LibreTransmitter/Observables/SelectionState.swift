//
//  SelectionState.swift
//  LibreTransmitter
//
//  Created by Pete Schwamb on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

// Decided to use shared instance instead of .environmentObject()
public class SelectionState: ObservableObject {
    @Published public var selectedStringIdentifier: String? = ""

    @Published public var selectedUID: Data?

    public static var shared = SelectionState()
}
