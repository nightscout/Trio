import Foundation

struct WeakObject<T: AnyObject>: Equatable, Hashable {
    private let identifier: ObjectIdentifier
    weak var object: T?
    init(_ object: T) {
        self.object = object
        identifier = ObjectIdentifier(object)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    static func == (lhs: WeakObject<T>, rhs: WeakObject<T>) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

struct WeakObjectSet<T: AnyObject>: Sequence {
    var objects: Set<WeakObject<T>>

    init() {
        objects = Set<WeakObject<T>>([])
    }

    init(_ object: T) {
        objects = Set<WeakObject<T>>([WeakObject(object)])
    }

    init(_ objects: [T]) {
        self.objects = Set<WeakObject<T>>(objects.map { WeakObject($0) })
    }

    var allObjects: [T] {
        objects.compactMap(\.object)
    }

    func contains(_ object: T) -> Bool {
        objects.contains(WeakObject(object))
    }

    mutating func add(_ object: T) {
        // prevent ObjectIdentifier be reused
        if contains(object) {
            remove(object)
        }
        objects.insert(WeakObject(object))
    }

    mutating func add(_ objects: [T]) {
        objects.forEach { self.add($0) }
    }

    mutating func remove(_ object: T) {
        objects.remove(WeakObject<T>(object))
    }

    mutating func remove(_ objects: [T]) {
        objects.forEach { self.remove($0) }
    }

    func makeIterator() -> AnyIterator<T> {
        let objects = allObjects
        var index = 0
        return AnyIterator {
            defer { index += 1 }
            return index < objects.count ? objects[index] : nil
        }
    }
}
