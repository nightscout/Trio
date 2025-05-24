//
// Trio
// ProgressBar.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

struct ProgressBar: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .circular)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.3)
                    .foregroundColor(.secondary)

                Capsule(style: .circular)
                    .frame(
                        width: min(CGFloat(self.value) * geometry.size.width, geometry.size.width),
                        height: geometry.size.height
                    )
                    .foregroundColor(.accentColor)
                    .animation(.linear, value: value)
            }
        }
        .frame(height: 20)
    }
}
