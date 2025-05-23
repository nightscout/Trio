// Trio
// ConfigEditorStateModel.swift
// Created by Ivan Valkou on 2021-11-07.

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
