import os.log
import os.signpost

protocol RangeSignpost {
    func end(_ format: @autoclosure () -> StaticString, _ arguments: @autoclosure () -> [String])
    func end(_ format: @autoclosure () -> StaticString)
}

enum Signpost {
    static func point(
        _ category: Logger.Category,
        name: StaticString,
        format: StaticString? = nil,
        arguments: @autoclosure () -> [String] = []
    ) {
        guard Config.withSignPosts else { return }
        if #available(iOS 12.0, *) {
            let log = category.logger.log
            let signpostID = OSSignpostID(log: log)
            set(.event, log: log, name: name, signpostID: signpostID, format, arguments())
        }
    }

    static func perform<T>(
        _: Logger.Category,
        name: StaticString,
        block: () throws -> T
    ) rethrows -> T {
        let signpost = Signpost.range(.businessLogic, name: name)
        defer { signpost.end(name) }
        return try block()
    }

    static func range(
        _ category: Logger.Category,
        name: StaticString
    ) -> RangeSignpost {
        guard Config.withSignPosts else { return EmptySignpost() }
        if #available(iOS 12.0, *) {
            return BaseRangeSignpost(category, name)
        }
        return EmptySignpost()
    }

    static func range(
        _ category: Logger.Category,
        name: StaticString,
        format: StaticString,
        arguments: @autoclosure () -> [String] = []
    ) -> RangeSignpost {
        guard Config.withSignPosts else { return EmptySignpost() }
        if #available(iOS 12.0, *) {
            return BaseRangeSignpost(category, name, format, arguments())
        }
        return EmptySignpost()
    }

    @available(iOS 12.0, *) fileprivate static func set(
        _ type: OSSignpostType,
        log: OSLog,
        name: StaticString,
        signpostID: OSSignpostID,
        _ format: StaticString? = nil,
        _ arguments: [String] = []
    ) {
        if let format = format {
            switch arguments.count {
            case 0: os_signpost(type, log: log, name: name, signpostID: signpostID, format)
            case 1: os_signpost(type, log: log, name: name, signpostID: signpostID, format, arguments[0])
            case 2: os_signpost(type, log: log, name: name, signpostID: signpostID, format, arguments[0], arguments[1])
            case 3: os_signpost(
                    type,
                    log: log,
                    name: name,
                    signpostID: signpostID,
                    format,
                    arguments[0],
                    arguments[1],
                    arguments[2]
                )
            case 4: os_signpost(
                    type,
                    log: log,
                    name: name,
                    signpostID: signpostID,
                    format,
                    arguments[0],
                    arguments[1],
                    arguments[2],
                    arguments[3]
                )
            case 5: os_signpost(
                    type,
                    log: log,
                    name: name,
                    signpostID: signpostID,
                    format,
                    arguments[0],
                    arguments[1],
                    arguments[2],
                    arguments[3],
                    arguments[4]
                )
            default: error(.service, "Signpost.set is not implemented for size.", description: "\(arguments.count)")
            }
        } else {
            os_signpost(type, log: log, name: name, signpostID: signpostID)
        }
    }
}

struct EmptySignpost: RangeSignpost {
    func end(_: @autoclosure () -> StaticString, _: @autoclosure () -> [String]) {}
    func end(_: @autoclosure () -> StaticString) {}
}

@available(iOS 12.0, *) final class BaseRangeSignpost: RangeSignpost {
    private let log: OSLog
    private let signpostID: OSSignpostID
    private let name: StaticString
    private var endFormat: StaticString?
    private var endArguments: [String] = []

    init(_ category: Logger.Category, _ name: StaticString) {
        log = category.logger.log
        signpostID = OSSignpostID(log: log)
        self.name = name
        Signpost.set(.begin, log: log, name: name, signpostID: signpostID)
    }

    init(_ category: Logger.Category, _ name: StaticString, _ format: StaticString, _ arguments: [String]) {
        log = category.logger.log
        signpostID = OSSignpostID(log: log)
        self.name = name
        Signpost.set(.begin, log: log, name: name, signpostID: signpostID, format, arguments)
    }

    deinit {
        Signpost.set(.end, log: log, name: name, signpostID: signpostID, endFormat, endArguments)
    }

    func end(_ format: @autoclosure () -> StaticString, _ arguments: @autoclosure () -> [String]) {
        endFormat = format()
        endArguments = arguments()
    }

    func end(_ format: @autoclosure () -> StaticString) {
        end(format(), [])
    }
}
