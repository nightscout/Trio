//
// Trio
// UnlockManager.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou and Marvin Polscheit.
//
// Documentation available under: https://triodocs.org/

import Combine
import LocalAuthentication

protocol UnlockManager {
    func unlock() async throws -> Bool
}

final class BaseUnlockManager: UnlockManager {
    @MainActor func unlock() async throws -> Bool {
        let context = LAContext()
        let reason = "We need to make sure you are the owner of the device."

        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return true
        } catch {
            throw error
        }
    }
}
