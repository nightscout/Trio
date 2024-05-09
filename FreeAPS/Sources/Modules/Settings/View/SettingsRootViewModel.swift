//
//  SettingsRootViewModel.swift
//  FreeAPS
//
//  Created by Jonas Björkert on 2024-05-09.
//

import Foundation
import SwiftUI
import Swinject

class SettingsRootViewModel: ObservableObject {
    @Published var headerText: String = ""

    init() {
        let buildDetails = BuildDetails.default
        let versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
        let buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"
        let branch = buildDetails.branchAndSha

        let headerBase = "Trio v\(versionNumber) (\(buildNumber))\nBranch: \(branch)"

        if let expirationDate = buildDetails.calculateExpirationDate() {
            let formattedDate = DateFormatter.localizedString(from: expirationDate, dateStyle: .medium, timeStyle: .none)
            headerText = "\(headerBase)\n\(buildDetails.expirationHeaderString): \(formattedDate)"
        } else {
            headerText = headerBase
        }
    }
}
