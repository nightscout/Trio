//
//  GenericThrottler.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 16/08/2021.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine

public class GenericThrottler<T, U: Hashable> {

    public var throttledPublisher: AnyPublisher<T, Never> {
        throttledSubject.eraseToAnyPublisher()
    }
    // this is the where the bluetoothsearch should send its updates
    public let incoming = PassthroughSubject<T, Never>()

    // this is what swiftui would connect to
    private let throttledSubject = PassthroughSubject<T, Never>()
    private var initiallyPublished = Set<U>()

    private var bag = Set<AnyCancellable>()
    private var timerBag = Set<AnyCancellable>()

    private var newValues: [U: T] = [:]

    private var identificator: KeyPath<T, U>

    private var interval: TimeInterval

    public func startTimer() {
        stopTimer()

        Timer.publish(every: interval, on: .main, in: .default)
        .autoconnect()
        .sink(
            receiveValue: { [weak self ] _ in
                // every 10 seconds, send the latest element as uniquely identified by bledeviceid
                // we reset the newvalues so that we wont resend the same identifical element after 10 additional seconds
                self?.newValues.forEach { el in
                    self?.throttledSubject.send(el.value)
                }
                self?.newValues = [:]
            }
        )
        .store(in: &timerBag)
    }

    public func stopTimer() {
        if !timerBag.isEmpty {
            timerBag.forEach { cancel in
                cancel.cancel()
            }
        }
    }

    private func setupDebugListener() {
        throttledSubject
        .sink { el in
            let now = Date().description
            print("\(now) \t throttledPublisher got new value: \(el) ")
        }
        .store(in: &bag)
    }

    private func setupIncoming() {
        incoming
        .sink { [weak self] el in
            guard let self else {
                return
            }
            
            let id = el.self[keyPath: self.identificator]

            let neverPublished = !self.initiallyPublished.contains(id)
            if neverPublished {
                self.initiallyPublished.insert(id)
                // every element should be published initially
                self.throttledSubject.send(el)
                return
            }

            self.newValues[id] = el

        }
        .store(in: &bag)
    }

    public init(identificator: KeyPath<T, U>, interval: TimeInterval) {
        self.identificator = identificator
        self.interval = interval

        startTimer()
        setupIncoming()

        // this cancellable would normally not be used directly, as you would consume the publisher from swiftui
        // setupDebugListener()

    }

    deinit {
        print("deiniting GenericThrottler")
    }

}
