//
// Trio
// AppearanceManager.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Marvin Polscheit on 2025-05-24.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import UIKit

protocol AppearanceManager {
    func setupGlobalAppearance()
}

final class BaseAppearanceManager: AppearanceManager {
    func setupGlobalAppearance() {
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().backgroundColor = .clear
        UITableViewHeaderFooterView.appearance().tintColor = .clear
    }
}
