//
// Trio
// TestError.swift
// Created by Marvin Polscheit on 2025-02-13.
// Last edited by Marvin Polscheit on 2025-02-19.
// Most contributions by Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Foundation

// Custom error type for test failures
struct TestError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
