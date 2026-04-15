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
