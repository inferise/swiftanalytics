//
//  TestUtilities.swift
//  InferiseAnalytics-Tests
//
//  Created by Brandon Sneed on 1/6/21.
//

import Foundation
import XCTest
@testable import InferiseAnalytics

extension UUID {
    public func asUInt8Array() -> [UInt8] {
        let (u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15, u16) = self.uuid
        return [u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15, u16]
    }

    public func asData() -> Data {
        Data(self.asUInt8Array())
    }
}

// MARK: - Helper Classes

struct MyTraits: Codable {
    let email: String?
}

class GooberPlugin: EventPlugin {
    let type: PluginType
    weak var analytics: Analytics?

    init() {
        self.type = .enrichment
    }

    func identify(event: IdentifyEvent) -> IdentifyEvent? {
        var newEvent = IdentifyEvent(existing: event)
        newEvent.userId = "goober"
        return newEvent
    }
}

class ZiggyPlugin: EventPlugin {
    let type: PluginType
    weak var analytics: Analytics?
    var receivedInitialUpdate: Int = 0

    var completion: (() -> Void)?

    required init() {
        self.type = .enrichment
    }

    func update(settings: Settings, type: UpdateType) {
        if type == .initial {
            self.receivedInitialUpdate += 1
        }
    }

    func identify(event: IdentifyEvent) -> IdentifyEvent? {
        var newEvent = IdentifyEvent(existing: event)
        newEvent.userId = "ziggy"
        return newEvent
        // return nil
    }

    func shutdown() {
        self.completion?()
    }
}

class MyDestination: DestinationPlugin {
    var timeline: Timeline
    let type: PluginType
    let key: String
    weak var analytics: Analytics?
    let trackCompletion: (() -> Bool)?

    let disabled: Bool
    var receivedInitialUpdate: Int = 0

    init(disabled: Bool = false, trackCompletion: (() -> Bool)? = nil) {
        self.key = "MyDestination"
        self.type = .destination
        self.timeline = Timeline()
        self.trackCompletion = trackCompletion
        self.disabled = disabled
    }

    func update(settings: Settings, type: UpdateType) {
        if type == .initial {
            self.receivedInitialUpdate += 1
        }
        if self.disabled == false {
            // add ourselves to the settings
            self.analytics?.manuallyEnableDestination(plugin: self)
        }
    }

    func track(event: TrackEvent) -> TrackEvent? {
        var returnEvent: TrackEvent? = event
        if let completion = trackCompletion {
            if !completion() {
                returnEvent = nil
            }
        }
        return returnEvent
    }
}

class OutputReaderPlugin: Plugin {
    let type: PluginType
    weak var analytics: Analytics?

    var events = [RawEvent]()
    var lastEvent: RawEvent?

    init() {
        self.type = .after
    }

    func execute<T: RawEvent>(event: T?) -> T? {
        self.lastEvent = event
        if let t = lastEvent as? TrackEvent {
            self.events.append(t)
            print("EVENT: \(t.event)")
        }
        return event
    }
}

func uniqueWriteKey(_ name: String = #function) -> String {
    "test-\(name)-\(UUID().uuidString)"
}

func waitUntilStarted(analytics: Analytics?) {
    guard let analytics else { return }
    // wait until the startup queue has emptied it's events.
    if let startupQueue = analytics.find(pluginType: StartupQueue.self) {
        while startupQueue.running != true {
            RunLoop.main.run(until: Date.distantPast)
        }
    }
}

struct TimedOutError: Error, Equatable {}

public func waitForTaskCompletion<R>(
    withTimeoutInSeconds timeout: UInt64,
    _ task: @escaping () async throws -> R
) async throws -> R {
    try await withThrowingTaskGroup(of: R.self) { group in
        await withUnsafeContinuation { continuation in
            group.addTask {
                continuation.resume()
                return try await task()
            }
        }
        group.addTask {
            await Task.yield()
            try await Task.sleep(nanoseconds: timeout * 1_000_000_000)
            throw TimedOutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

extension XCTestCase {
    func checkIfLeaked(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            if instance != nil {
                print("Instance \(String(describing: instance)) is not nil")
            }
            XCTAssertNil(instance, "Instance should have been deallocated. Potential memory leak!", file: file, line: line)
        }
    }

    func waitUntilFinished(analytics: Analytics?, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak analytics] in
            let instance = try await waitForTaskCompletion(withTimeoutInSeconds: 30) {
                while analytics != nil {
                    DispatchQueue.main.sync {
                        RunLoop.current.run(until: .distantPast)
                    }
                }
                return analytics
            }
            XCTAssertNil(instance, "Analytics should have been deallocated. It's likely a memory leak!", file: file, line: line)
        }
    }
}

#if !os(Linux) && !os(Windows)

    class RestrictedHTTPSession: HTTPSession {
        let sesh: URLSession
        static var fileUploads: Int = 0
        static var dataUploads: Int = 0
        static var dataTasks: Int = 0
        static var invalidated: Int = 0

        init(blocking: Bool = true, failing: Bool = false) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.allowsCellularAccess = true
            configuration.timeoutIntervalForResource = 30
            configuration.timeoutIntervalForRequest = 60
            configuration.httpMaximumConnectionsPerHost = 2
            configuration.httpAdditionalHeaders = ["Content-Type": "application/json; charset=utf-8",
                                                   "Authorization": "Basic test",
                                                   "User-Agent": "analytics-ios/\(Analytics.version())"]

            var protos = [URLProtocol.Type]()
            if blocking {
                protos.append(BlockNetworkCalls.self)
            }
            if failing {
                protos.append(FailedNetworkCalls.self)
            }
            configuration.protocolClasses = protos

            self.sesh = URLSession(configuration: configuration)
        }

        static func reset() {
            self.fileUploads = 0
            self.dataUploads = 0
            self.dataTasks = 0
            self.invalidated = 0
        }

        func uploadTask(with request: URLRequest, fromFile file: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void) -> URLSessionUploadTask {
            defer { Self.fileUploads += 1 }
            return self.sesh.uploadTask(with: request, fromFile: file, completionHandler: completionHandler)
        }

        func uploadTask(with request: URLRequest, from bodyData: Data?, completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void) -> URLSessionUploadTask {
            defer { Self.dataUploads += 1 }
            return self.sesh.uploadTask(with: request, from: bodyData, completionHandler: completionHandler)
        }

        func dataTask(with request: URLRequest, completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void) -> URLSessionDataTask {
            defer { Self.dataTasks += 1 }
            return self.sesh.dataTask(with: request, completionHandler: completionHandler)
        }

        func finishTasksAndInvalidate() {
            defer { Self.invalidated += 1 }
            self.sesh.finishTasksAndInvalidate()
        }
    }

    class BlockNetworkCalls: URLProtocol {
        var initialURL: URL?
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override var cachedResponse: CachedURLResponse? {
            nil
        }

        override func startLoading() {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: URL(string: "http://api.inferise.test")!, statusCode: 200, httpVersion: nil, headerFields: ["blocked": "true"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    class FailedNetworkCalls: URLProtocol {
        var initialURL: URL?
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override var cachedResponse: CachedURLResponse? {
            nil
        }

        override func startLoading() {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: URL(string: "http://api.inferise.test")!, statusCode: 400, httpVersion: nil, headerFields: ["blocked": "true"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

#endif

// MARK: - Hermetic networking

extension Configuration {
    /// Routes this instance's egress through a session that answers every request
    /// with a 200 and never touches the network.
    ///
    /// Several tests assert that a flush drained storage, which only holds if the
    /// upload succeeded. They used to get that from the upstream vendor's live endpoint
    /// answering 200 — a real dependency on a third-party host in a unit test.
    /// Now that the default host is our own (and may not be deployed yet), make
    /// the success explicit instead of incidental.
    @discardableResult
    func blockNetworkEgress() -> Configuration {
        #if !os(Linux) && !os(Windows)
            return httpSession(RestrictedHTTPSession())
        #else
            return self
        #endif
    }

    /// Like `blockNetworkEgress()`, but answers every request with a 400 so tests
    /// can exercise the server-rejection path without depending on a live host
    /// returning an error for a bogus write key.
    @discardableResult
    func failNetworkEgress() -> Configuration {
        #if !os(Linux) && !os(Windows)
            return httpSession(RestrictedHTTPSession(blocking: false, failing: true))
        #else
            return self
        #endif
    }
}
