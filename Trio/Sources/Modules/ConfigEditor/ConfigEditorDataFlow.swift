// Trio
// ConfigEditorDataFlow.swift
// Created by Ivan Valkou on 2021-02-03.

enum ConfigEditor {
    enum Config {}
}

protocol ConfigEditorProvider: Provider {
    func save(_ value: RawJSON, as file: String)
    func load(file: String) -> RawJSON
}
