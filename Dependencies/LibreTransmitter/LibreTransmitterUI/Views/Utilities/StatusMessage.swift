//
//  StatusMessage.swift
//  LibreTransmitterUI
//
//  Created by LoopKit Authors on 23/05/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct StatusMessage: Identifiable {
    var id: String { title }
    let title: String
    let message: String
}
