//
// Trio
// ConfigEditorStateModel.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import SwiftUI
import Swinject

extension ConfigEditor {
    final class StateModel: BaseStateModel<Provider> {
        var file: String = ""
        @Published var configText = ""

        override func subscribe() {
            configText = provider.load(file: file)
        }

        func save() {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            provider.save(configText, as: file)
        }
    }
}
