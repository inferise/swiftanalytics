//
//  StartupQueue.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 6/4/21.
//

import Foundation
import Sovran

public class StartupQueue: Plugin, Subscriber {
    static let maxSize = 1000

    @Atomic public var running: Bool = false

    public let type: PluginType = .before

    public weak var analytics: Analytics? {
        didSet {
            self.analytics?.store.subscribe(self) { [weak self] (state: System) in
                self?.runningUpdate(state: state)
            }
        }
    }

    let syncQueue = DispatchQueue(label: "startupQueue.inferise.com")
    var queuedEvents = [RawEvent]()

    required init() {}

    public func execute<T: RawEvent>(event: T?) -> T? {
        if self.running == false, let e = event {
            // timeline hasn't started, so queue it up.
            self.syncQueue.sync {
                if self.queuedEvents.count >= Self.maxSize {
                    // if we've exceeded the max queue size start dropping events
                    self.queuedEvents.removeFirst()
                }
                self.queuedEvents.append(e)
            }
            return nil
        }
        // the timeline has started, so let the event pass.
        return event
    }
}

extension StartupQueue {
    func runningUpdate(state: System) {
        _running.set(state.running)
        if state.running {
            self.replayEvents()
        }
    }

    func replayEvents() {
        // replay the queued events to the instance of Analytics we're working with.
        self.syncQueue.sync {
            for event in self.queuedEvents {
                self.analytics?.process(event: event)
            }
            self.queuedEvents.removeAll()
        }
    }
}
