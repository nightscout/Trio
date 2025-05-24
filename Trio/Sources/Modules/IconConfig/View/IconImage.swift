//
// Trio
// IconImage.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Jon B Mårtensson and Mike Plante.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

struct IconImage: View {
    var icon: Icon_

    var body: some View {
        Label {
            Text(icon.rawValue)
        } icon: {
            Image(icon.rawValue)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(minHeight: 57, maxHeight: 1024)
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding()
        }
        .labelStyle(.iconOnly)
    }
}

struct IconImage_Previews: PreviewProvider {
    static var previews: some View {
        IconImage(icon: Icon_.primary)
            .previewInterfaceOrientation(.portrait)
    }
}
