//
// Trio
// ConfigEditorProvider.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Ivan.
//
// Documentation available under: https://triodocs.org/

import Foundation

extension ConfigEditor {
    final class Provider: BaseProvider, ConfigEditorProvider {
        func load(file: String) -> RawJSON {
            storage.retrieveRaw(file) ?? OpenAPS.defaults(for: file)
        }

        func urlFor(file: String) -> URL? {
            storage.urlFor(file: file)
        }

        func save(_ value: RawJSON, as file: String) {
            if file.hasSuffix(".js") {
                storage.save(value, as: file)
                return
            }

            guard let data = value.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
                warning(.service, "Invalid JSON")
                return
            }
            storage.save(value, as: file)
        }
    }
}
