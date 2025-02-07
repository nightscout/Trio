import Foundation

extension DispatchQueue {
//    static let reloadQueue = DispatchQueue.markedQueue(label: "reloadQueue", qos: .ui)
}

extension DispatchQueue {
    static var isMain: Bool {
        Thread.isMainThread && OperationQueue.main === OperationQueue.current
    }

    static func safeMainSync<T>(_ block: () throws -> T) rethrows -> T {
        if isMain {
            return try block()
        } else {
            return try DispatchQueue.main.sync {
                try autoreleasepool(invoking: block)
            }
        }
    }

    static func safeMainAsync(_ block: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.default], block: block)
    }
}

extension DispatchQueue {
    private enum QueueSpecific {
        static let key = DispatchSpecificKey<String>()
        static let value = AssociationKey<String?>("DispatchQueue.Specific.value")
    }

    private(set) var specificValue: String? {
        get { associations.value(forKey: QueueSpecific.value) }
        set { associations.setValue(newValue, forKey: QueueSpecific.value) }
    }

    static func markedQueue(
        label: String = "MarkedQueue",
        qos: DispatchQoS = .default,
        attributes: DispatchQueue.Attributes = [],
        target: DispatchQueue? = nil
    ) -> DispatchQueue {
        let queueLabel = "\(label).\(UUID())"
        let queue = DispatchQueue(
            label: queueLabel,
            qos: qos,
            attributes: attributes,
            autoreleaseFrequency: .workItem,
            target: target
        )
        let specificValue = target?.label ?? queueLabel
        queue.specificValue = specificValue
        queue.setSpecific(key: QueueSpecific.key, value: specificValue)
        return queue
    }

    static var currentLabel: String? { DispatchQueue.getSpecific(key: QueueSpecific.key) }

    var isCurrentQueue: Bool {
        if let staticSpecific = DispatchQueue.currentLabel,
           let instanceSpecific = specificValue,
           staticSpecific == instanceSpecific
        {
            return true
        }
        return false
    }

    func safeSync<T>(execute block: () throws -> T) rethrows -> T {
        try autoreleasepool {
            if self === DispatchQueue.main {
                return try DispatchQueue.safeMainSync(block)
            } else if isCurrentQueue {
                return try block()
            } else {
                return try sync {
                    try autoreleasepool(invoking: block)
                }
            }
        }
    }
}
