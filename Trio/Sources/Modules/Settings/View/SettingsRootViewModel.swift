//
// Trio
// SettingsRootViewModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jonas Björkert.
//
// Documentation available under: https://triodocs.org/

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
