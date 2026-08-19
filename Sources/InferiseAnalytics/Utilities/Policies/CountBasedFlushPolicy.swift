//
//  CountBasedFlushPolicy.swift
//
//
//  Created by Alan Charles on 3/21/23.
//

import Foundation

public class CountBasedFlushPolicy: FlushPolicy {
    public weak var analytics: Analytics?
    var desiredCount: Int?
    @Atomic var count: Int = 0

    public init() {}

    public init(count: Int) {
        self.desiredCount = count
    }

    public func configure(analytics: Analytics) {
        self.analytics = analytics
        if let desiredCount {
            analytics.flushAt = desiredCount
        }
    }

    public func shouldFlush() -> Bool {
        guard let a = analytics else {
            return false
        }
        if a.configuration.values.flushAt > 0 && self.count >= a.configuration.values.flushAt {
            return true
        } else {
            return false
        }
    }

    public func updateState(event: RawEvent) {
        _count.mutate { value in
            value += 1
        }
    }

    public func reset() {
        _count.set(0)
    }
}
