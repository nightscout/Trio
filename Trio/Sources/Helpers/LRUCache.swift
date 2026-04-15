import Foundation

private class List<Key>: CustomDebugStringConvertible {
    var debugDescription: String { "\(value)" }

    var value: Key
    var prev: List?
    var next: List?

    init(_ val: Key) {
        value = val
    }
}

final class LRUCache<Key, Value> where Key: Hashable {
    private var cache: [Key: Value] = [:]
    private var listBegin: List<Key>?
    private var listEnd: List<Key>?
    private var listCache: [Key: List<Key>] = [:]
    private let lock = NSRecursiveLock()
    private let capacity: Int

    init(capacity: Int) {
        cache.reserveCapacity(capacity)
        listCache.reserveCapacity(capacity)
        self.capacity = capacity
    }

    var isEmpty: Bool {
        lock.perform {
            cache.isEmpty
        }
    }

    var isFull: Bool {
        lock.perform {
            cache.count == capacity
        }
    }

    var count: Int {
        lock.perform {
            cache.count
        }
    }

    var allValues: [Value] {
        lock.perform {
            Array(cache.values)
        }
    }

    func removeAll() {
        listCache.keys.forEach(remove(_:))
    }

    subscript(key: Key) -> Value? {
        get {
            lock.perform {
                guard let value = cache[key] else { return nil }
                self[key] = value
                return value
            }
        }
        set {
            lock.perform {
                remove(key)
                if let value = newValue {
                    insert(key, value)
                }
            }
        }
    }

    private func remove(_ key: Key) {
        autoreleasepool {
            guard let node = listCache[key] else { return }
            listCache[key] = nil
            cache[key] = nil
            let p = node.prev
            let n = node.next

            p?.next = n
            n?.prev = p
            if node.value == listBegin!.value {
                listBegin = n
            }
            if node.value == listEnd!.value {
                listEnd = listEnd!.prev
            }
        }
    }

    private func insert(_ key: Key, _ value: Value) {
        if cache.count == capacity {
            remove(listBegin!.value)
        }
        let le = listEnd
        listEnd = List(key)
        le?.next = listEnd
        listEnd!.prev = le
        listBegin = listBegin ?? listEnd
        listCache[key] = listEnd
        cache[key] = value
    }
}
