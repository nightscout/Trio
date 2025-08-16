import Foundation
import Swinject

/// This class adds a simple wrapper around a Swinject resolver to ensure that only one thread can
/// access it at any given time.
struct LockedResolver: Resolver {
    let resolver: Resolver
    let lock: NSRecursiveLock

    func resolve<Service, Arg1>(_ serviceType: Service.Type, argument: Arg1) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, argument: argument)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1>(_ serviceType: Service.Type, name: String?, argument: Arg1) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, argument: argument)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2>(_ serviceType: Service.Type, arguments arg1: Arg1, _ arg2: Arg2) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4, arg5)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7,
        _ arg8: Arg8
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7,
        _ arg8: Arg8
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7,
        _ arg8: Arg8,
        _ arg9: Arg9
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        lock.unlock()
        return service
    }

    func resolve<Service, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7, Arg8, Arg9>(
        _ serviceType: Service.Type,
        name: String?,
        arguments arg1: Arg1,
        _ arg2: Arg2,
        _ arg3: Arg3,
        _ arg4: Arg4,
        _ arg5: Arg5,
        _ arg6: Arg6,
        _ arg7: Arg7,
        _ arg8: Arg8,
        _ arg9: Arg9
    ) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name, arguments: arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        lock.unlock()
        return service
    }

    func resolve<Service>(_ serviceType: Service.Type) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType)
        lock.unlock()
        return service
    }

    func resolve<Service>(_ serviceType: Service.Type, name: String?) -> Service? {
        lock.lock()
        let service = resolver.resolve(serviceType, name: name)
        lock.unlock()
        return service
    }
}
