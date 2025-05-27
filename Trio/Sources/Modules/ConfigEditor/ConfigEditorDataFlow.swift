//
// Trio
// ConfigEditorDataFlow.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

enum ConfigEditor {
    enum Config {}
}

protocol ConfigEditorProvider: Provider {
    func save(_ value: RawJSON, as file: String)
    func load(file: String) -> RawJSON
}
