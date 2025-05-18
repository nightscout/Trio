import Combine

protocol OptionalType {
    associatedtype Wrapped

    var optional: Wrapped? { get }
}

extension Optional: OptionalType {
    public var optional: Wrapped? { self }
}

extension Publisher where Output: OptionalType {
    func ignoreNil() -> AnyPublisher<Output.Wrapped, Failure> {
        flatMap { output -> AnyPublisher<Output.Wrapped, Failure> in
            guard let output = output.optional else {
                return Empty<Output.Wrapped, Failure>(completeImmediately: false).eraseToAnyPublisher()
            }
            return Just(output).setFailureType(to: Failure.self).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

extension Publisher {
    func combineWithPrevious() -> AnyPublisher<(Output, Output), Failure> {
        zip(dropFirst()).eraseToAnyPublisher()
    }
}

extension Publisher {
    func cancellable() -> some Cancellable {
        sink { _ in } receiveValue: { _ in }
    }
}

extension Publisher where Failure == Never {
    func cancellable() -> some Cancellable {
        sink { _ in }
    }
}

typealias Lifetime = Set<AnyCancellable>

extension Publisher where Failure == Never {
    func weakAssign<T: AnyObject>(
        to keyPath: ReferenceWritableKeyPath<T, Output>,
        on object: T
    ) -> AnyCancellable {
        sink { [weak object] value in
            object?[keyPath: keyPath] = value
        }
    }
}
