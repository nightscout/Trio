//
// Trio
// RadioButton.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

struct RadioButton: View {
    var isSelected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                Text(label) // Add label inside the button to make it tappable
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
