//
// Trio
// Script.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-04.
// Most contributions by Deniz Cengiz and Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation

struct Script {
    let name: String
    let body: String

    init(name: String) {
        self.name = name
        if let url = Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            do {
                body = try String(contentsOf: url)
            } catch {
                print("Error loading script: \(error.localizedDescription)")
                body = "Error loading script"
            }
        } else {
            print("Resource not found: javascript/\(name)")
            body = "Resource not found"
        }
    }

    init(name: String, body: String) {
        self.name = name
        self.body = body
    }
}
