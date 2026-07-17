import Foundation
import Testing

@testable import Trio

/// Tests for the generic `UploadSerializer` behavior that isn't covered by
/// `NightscoutUploadSerializerTests`: custom pipeline types and the per-instance
/// scope of the reentrancy guard.
@Suite("Upload Serializer Generic Tests") struct UploadSerializerTests {
    private enum TestPipeline: String, CaseIterable, Sendable {
        case alpha
        case beta
    }

    /// Async counter shared across concurrent tasks.
    private actor Counter {
        private(set) var value = 0

        func increment() { value += 1 }
    }

    @Test("Serializer runs pipelines of a custom pipeline type") func customPipelineType() async {
        let runs = Counter()
        let serializer = UploadSerializer<TestPipeline> { _ in
            await runs.increment()
        }

        await serializer.run(.alpha)
        await serializer.run(.beta)
        await serializer.run(.alpha)

        #expect(await runs.value == 3)
    }

    @Test(
        "Reentrancy guard distinguishes serializer instances for equal pipeline values"
    ) func reentrancyGuardIsPerInstance() async {
        let reentrantEvents = Counter()
        let runs = Counter()

        let inner = UploadSerializer<TestPipeline>(
            uploadOperation: { _ in await runs.increment() },
            onReentrantRun: { _ in Task { await reentrantEvents.increment() } }
        )

        // The outer serializer's operation awaits the inner serializer's run for the
        // SAME pipeline value. That must not trip the reentrancy guard (which would
        // downgrade it to fire-and-forget): only a run from inside the same
        // serializer instance's own operation is reentrant.
        let outer = UploadSerializer<TestPipeline>(
            uploadOperation: { _ in
                await inner.run(.alpha)
                await runs.increment()
            },
            onReentrantRun: { _ in Task { await reentrantEvents.increment() } }
        )

        await outer.run(.alpha)

        #expect(await runs.value == 2, "Both serializers' operations must complete")
        #expect(await reentrantEvents.value == 0, "Cross-instance runs are not reentrant")
    }
}
