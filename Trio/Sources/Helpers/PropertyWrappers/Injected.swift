//
// Trio
// Injected.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Swinject

protocol Injectable {
    func injectServices(_ resolver: Resolver)
}

@propertyWrapper final class Injected<Resolve, Service>: Resolvable {
    var wrappedValue: Service!

    init(as _: Resolve.Type) {}

    func resolve(_ resolver: Resolver) {
        if wrappedValue == nil {
            wrappedValue = (resolver.resolve(Resolve.self) as! Service)
        }
    }
}

private protocol Resolvable {
    func resolve(_: Resolver)
}

extension Injected where Resolve == Service {
    convenience init() {
        self.init(as: Service.self)
    }
}

extension Injectable {
    func injectServices(_ resolver: Resolver) {
        Mirror(reflecting: self).allChildrenValues.forEach { ($0 as? Resolvable)?.resolve(resolver) }
    }
}

private extension Mirror {
    var allChildrenValues: [Any] {
        children.map(\.value) + (superclassMirror?.allChildrenValues ?? [])
    }
}
