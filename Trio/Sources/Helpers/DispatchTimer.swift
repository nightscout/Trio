//
// Trio
// DispatchTimer.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Combine
import Foundation

class DispatchTimer {
    let timeInterval: TimeInterval
    let queue: DispatchQueue

    private let subject = PassthroughSubject<Date, Never>()

    init(
        timeInterval: TimeInterval,
        queue: DispatchQueue = DispatchQueue.markedQueue(label: "DispatchTimer.queue", qos: .userInteractive)
    ) {
        self.timeInterval = timeInterval
        self.queue = queue
    }

    private lazy var timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeInterval, repeating: timeInterval)
        timer.setEventHandler(handler: { [weak self] in
            self?.fire()
        })
        return timer
    }()

    func fire() {
        subject.send(Date())
        eventHandler?()
    }

    var eventHandler: (() -> Void)?

    private enum State {
        case suspended
        case resumed
    }

    private var state: State = .suspended

    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }

    var publisher: AnyPublisher<Date, Never> {
        subject.eraseToAnyPublisher()
    }

    deinit {
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here
         https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
        subject.send(completion: .finished)
    }
}
