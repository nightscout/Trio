// Compiled by run.py with the production fetch method and test-only dependencies.
final class PluginFetchContractTests: XCTestCase {
    enum FetchError: Error { case failed }

    private func assertEvents<P: Publisher>(
        _ publisher: P, _ expected: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) where P.Output == [Int] {
        let source = FetchHarness(publisher)
        var events: [String] = []
        let finished = expectation(description: "fetch completes")
        let subscription = source.fetch(nil).sink(
            receiveCompletion: { _ in events.append("finished"); finished.fulfill() },
            receiveValue: { events.append("value:\($0)") }
        )
        wait(for: [finished], timeout: timeoutWait)
        source.processQueue.sync {
            XCTAssertEqual(events, expected, file: file, line: line)
        }
        withExtendedLifetime(subscription) {}
    }

    func testEmptyArrayEmitsOnceThenFinishes() {
        assertEvents(Just<[Int]>([]), ["value:[]", "finished"])
    }

    func testEmptyCompletionEmitsOnceThenFinishes() {
        assertEvents(Empty<[Int], Never>(), ["value:[]", "finished"])
    }

    func testNonemptyArrayIsUnchanged() {
        assertEvents(Just([1, 2]), ["value:[1, 2]", "finished"])
    }

    func testDefensiveErrorReplacementEmitsOnceThenFinishes() {
        // Production fetchIfNeeded has Failure == Never. This probes the outer
        // defensive operator, not a reachable plugin callback failure path.
        assertEvents(Fail<[Int], FetchError>(error: .failed), ["value:[]", "finished"])
    }

    func testSilentPublisherTimesOutWithOneEmptyValueAndCancels() {
        var cancellations = 0
        let publisher = Empty<[Int], Never>(completeImmediately: false)
            .handleEvents(receiveCancel: { cancellations += 1 })
        let start = Date()
        assertEvents(publisher, ["value:[]", "finished"])
        XCTAssertEqual(cancellations, 1)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), minimumTimeout)
    }

    func testFirstEmptyValueDoesNotWaitForLaterNonemptyValue() {
        assertEvents([[], [1]].publisher, ["value:[]", "finished"])
    }

    func testFirstNonemptyValueDoesNotEmitLaterValues() {
        assertEvents([[1], [2]].publisher, ["value:[1]", "finished"])
    }

    func testErrorAfterFirstValueIsNotEmittedAsAnotherEmptyValue() {
        assertEvents(
            Just([1]).setFailureType(to: FetchError.self)
                .append(Fail<[Int], FetchError>(error: .failed)),
            ["value:[1]", "finished"]
        )
    }

    func testFirstValueCancelsUpstreamWithoutRequiringUpstreamCompletion() {
        let subject = PassthroughSubject<[Int], Never>()
        var cancellations = 0
        let source = FetchHarness(subject.handleEvents(receiveCancel: { cancellations += 1 }))
        let finished = expectation(description: "first value finishes")
        var events: [String] = []
        let subscription = source.fetch(nil).sink(
            receiveCompletion: { _ in events.append("finished"); finished.fulfill() },
            receiveValue: { events.append("value:\($0)") }
        )
        subject.send([])
        subject.send([1])
        wait(for: [finished], timeout: timeoutWait)
        source.processQueue.sync {
            XCTAssertEqual(events, ["value:[]", "finished"])
            XCTAssertEqual(cancellations, 1)
        }
        withExtendedLifetime(subscription) {}
    }

    func testAsynchronousFutureEmptyCallbackIsDelivered() {
        var resolve: ((Result<[Int], Never>) -> Void)?
        let future = Future<[Int], Never> { resolve = $0 }
        let source = FetchHarness(future)
        let finished = expectation(description: "asynchronous future completes")
        var values: [[Int]] = []
        let subscription = source.fetch(nil).sink(
            receiveCompletion: { _ in finished.fulfill() },
            receiveValue: { values.append($0) }
        )
        let promise = resolve!
        source.processQueue.async { promise(.success([])) }
        wait(for: [finished], timeout: timeoutWait)
        source.processQueue.sync { XCTAssertEqual(values, [[]]) }
        withExtendedLifetime(subscription) {}
    }

    func testDownstreamCancellationDoesNotSynthesizeAnEmptyValue() {
        let source = FetchHarness(Empty<[Int], Never>(completeImmediately: false))
        let unexpected = expectation(description: "no events after cancellation")
        unexpected.isInverted = true
        let subscription = source.fetch(nil).sink(
            receiveCompletion: { _ in unexpected.fulfill() },
            receiveValue: { _ in unexpected.fulfill() }
        )
        subscription.cancel()
        // Exceeds the accelerated timeout; full-timeout mode still checks prompt cancellation.
        wait(for: [unexpected], timeout: 0.15)
    }

    func testOneElementDemandReceivesEmptyValueThenCompletion() {
        let finished = expectation(description: "one-element subscriber completes")
        let subscriber = OneElementSubscriber { finished.fulfill() }
        let source = FetchHarness(Empty<[Int], Never>())
        source.fetch(nil).subscribe(subscriber)
        wait(for: [finished], timeout: timeoutWait)
        source.processQueue.sync { XCTAssertEqual(subscriber.events, ["value:[]", "finished"]) }
    }
}

private final class OneElementSubscriber: Subscriber {
    typealias Input = [Int]
    typealias Failure = Never
    var events: [String] = []
    private let finished: () -> Void
    init(finished: @escaping () -> Void) { self.finished = finished }
    func receive(subscription: Subscription) { subscription.request(.max(1)) }
    func receive(_ input: [Int]) -> Subscribers.Demand {
        events.append("value:\(input)")
        return .none
    }
    func receive(completion: Subscribers.Completion<Never>) {
        events.append("finished")
        finished()
    }
}
