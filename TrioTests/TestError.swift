// Trio
// TestError.swift
// Created by Deniz Cengiz on 2025-04-21.

import Foundation

// Custom error type for test failures
struct TestError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
