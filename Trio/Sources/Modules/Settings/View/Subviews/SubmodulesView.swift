//
// Trio
// SubmodulesView.swift
// Created by Jonas Björkert on 2025-02-26.
// Last edited by Jonas Björkert on 2025-04-05.
// Most contributions by Jonas Björkert.
//
// Documentation available under: https://triodocs.org/

import SwiftUI

struct SubmodulesView: View {
    let buildDetails: BuildDetails

    var body: some View {
        List {
            Section(header: Text("Trio")) {
                KeyValueRow(key: buildDetails.trioBranch, value: buildDetails.trioCommitSHA)
            }
            Section(header: Text("Submodules")) {
                ForEach(buildDetails.submodules.sorted(by: { $0.key < $1.key }), id: \.key) { name, info in
                    KeyValueRow(key: name, value: info.commitSHA)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Submodules")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
