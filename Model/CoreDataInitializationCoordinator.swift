/// This actor provides us with logic to handle cases when a caller
/// tries to initialize a coreDataStack that is already initialized.
actor CoreDataInitializationCoordinator {
    private var isInitialized = false
    private var initializationTask: Task<Void, Error>?

    /// Ensures that initialization only happens once and manages multiple concurrent initialization requests.
    /// This actor provides synchronization for the CoreDataStack initialization process.
    ///
    /// - Parameters:
    ///   - initialization: A closure that performs the actual initialization work.
    /// - Throws: Any error that might occur during initialization.
    /// - Returns: Void once initialization is complete.
    func ensureInitialized(perform initialization: @escaping () async throws -> Void) async throws {
        // If already initialized, return immediately
        if isInitialized {
            return
        }

        // If initialization is in progress, await the existing task
        if let existingTask = initializationTask {
            try await existingTask.value
            return
        }

        // Start a new initialization task
        let newTask = Task {
            do {
                try await initialization()
                isInitialized = true
            } catch {
                // Clear task reference on failure
                initializationTask = nil
                throw error
            }
            // Clear task reference on success
            initializationTask = nil
        }

        initializationTask = newTask
        try await newTask.value
    }
}
