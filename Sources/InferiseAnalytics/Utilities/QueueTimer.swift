//
//  QueueTimer.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 6/16/21.
//

import Foundation

class QueueTimer {
    enum State {
        case suspended
        case resumed
    }

    let interval: TimeInterval
    let timer: DispatchSourceTimer
    let queue: DispatchQueue
    let handler: () -> Void

    @Atomic var state: State = .suspended

    static var timers = [QueueTimer]()

    static func schedule(interval: TimeInterval, immediate: Bool = false, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        let timer = QueueTimer(interval: interval, queue: queue, handler: handler)
        Self.timers.append(timer)
    }

    init(interval: TimeInterval, immediate: Bool = false, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        self.interval = interval
        self.queue = queue
        self.handler = handler

        self.timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        if immediate {
            self.timer.schedule(deadline: .now(), repeating: self.interval)
        } else {
            self.timer.schedule(deadline: .now() + self.interval, repeating: self.interval)
        }
        self.timer.setEventHandler { [weak self] in
            self?.handler()
        }
        self.resume()
    }

    deinit {
        timer.setEventHandler {
            // do nothing ...
        }
        // if timer is suspended, we must resume if we're going to cancel.
        timer.cancel()
        resume()
    }

    func suspend() {
        if self.state == .suspended {
            return
        }
        _state.set(.suspended)
        self.timer.suspend()
    }

    func resume() {
        if self.state == .resumed {
            return
        }
        _state.set(.resumed)
        self.timer.resume()
    }
}

extension TimeInterval {
    static func milliseconds(_ value: Int) -> TimeInterval {
        TimeInterval(value) / 1000
    }

    static func seconds(_ value: Int) -> TimeInterval {
        TimeInterval(value)
    }

    static func hours(_ value: Int) -> TimeInterval {
        TimeInterval(60 * 60 * value)
    }

    static func days(_ value: Int) -> TimeInterval {
        TimeInterval((60 * 60 * value) * 24)
    }
}
