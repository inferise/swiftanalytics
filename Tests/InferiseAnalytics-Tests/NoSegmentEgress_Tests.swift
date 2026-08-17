//
//  NoSegmentEgress_Tests.swift
//  InferiseAnalytics-Tests
//
//  Enforces the core privacy invariant of the Inferise fork: this SDK must never
//  open a connection to a Segment host. That property is currently true because
//  of the default host constants, but nothing stops a rebase onto upstream from
//  silently reintroducing them — these tests are what make it stay true.
//
//  Coverage note: with Telemetry removed, `Configuration.httpSession` is the
//  single chokepoint for every outbound request the SDK makes (both the batch
//  upload and the settings fetch go through `HTTPClient`, which builds its
//  session from that closure). If a future change adds a second egress path that
//  bypasses it, these tests will not see it — so keep new network code on
//  HTTPClient.
//

#if !os(Linux) && !os(Windows)

    import XCTest
    @testable import InferiseAnalytics

    /// Hosts that must never appear in an outbound request.
    private let forbiddenHostFragments = ["segment.io", "segment.com"]

    /// An `HTTPSession` that records the URL of every request handed to it and never
    /// lets one reach the network (`BlockNetworkCalls` answers everything with a 200).
    private class HostRecordingHTTPSession: HTTPSession {
        /// Shared across instances because `HTTPClient` is rebuilt on settings update,
        /// and we want the union of every request made during a test.
        @Atomic static var requestedURLs: [URL] = []

        static func reset() {
            _requestedURLs.set([])
        }

        static var forbiddenURLs: [URL] {
            requestedURLs.filter { url in
                guard let host = url.host else { return false }
                return forbiddenHostFragments.contains { host.contains($0) }
            }
        }

        private let sesh: URLSession

        init() {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [BlockNetworkCalls.self]
            self.sesh = URLSession(configuration: configuration)
        }

        private func record(_ request: URLRequest) {
            guard let url = request.url else { return }
            Self._requestedURLs.mutate { $0.append(url) }
        }

        func uploadTask(
            with request: URLRequest, fromFile file: URL,
            completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
        ) -> URLSessionUploadTask {
            self.record(request)
            return self.sesh.uploadTask(with: request, fromFile: file, completionHandler: completionHandler)
        }

        func uploadTask(
            with request: URLRequest, from bodyData: Data?,
            completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
        ) -> URLSessionUploadTask {
            self.record(request)
            return self.sesh.uploadTask(with: request, from: bodyData, completionHandler: completionHandler)
        }

        func dataTask(
            with request: URLRequest,
            completionHandler: @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
        ) -> URLSessionDataTask {
            self.record(request)
            return self.sesh.dataTask(with: request, completionHandler: completionHandler)
        }

        func finishTasksAndInvalidate() {
            self.sesh.finishTasksAndInvalidate()
        }
    }

    class NoSegmentEgress_Tests: XCTestCase {
        /// `checkSettings()` short-circuits its network call when `isUnitTesting` is
        /// true (Settings.swift), which would hide the settings leg from these tests.
        /// Each test flips it off so the real fetch runs against the recording session.
        private var savedIsUnitTesting: Bool = true

        override func setUpWithError() throws {
            HostRecordingHTTPSession.reset()
            self.savedIsUnitTesting = isUnitTesting
            isUnitTesting = false
        }

        override func tearDownWithError() throws {
            isUnitTesting = self.savedIsUnitTesting
        }

        // MARK: - Static defaults

        func testDefaultHostsAreNotSegment() {
            for host in [HTTPClient.getDefaultAPIHost(), HTTPClient.getDefaultCDNHost()] {
                for fragment in forbiddenHostFragments {
                    XCTAssertFalse(
                        host.contains(fragment),
                        "Default host '\(host)' points at Segment. See HTTPClient.defaultAPIHost/defaultCDNHost."
                    )
                }
            }
        }

        /// The seeded default settings must name our integration key, otherwise
        /// `isDestinationEnabled` drops every event until the settings fetch lands.
        func testDefaultSettingsUseInferiseIntegrationKey() {
            let settings = Settings(writeKey: "defaultSettingsKey")
            XCTAssertTrue(
                settings.hasIntegrationSettings(key: InferiseDestination.Constants.integrationName.rawValue)
            )
            XCTAssertFalse(settings.hasIntegrationSettings(key: "Segment.io"))
        }

        /// Upgrade path: a build from before the integration-key rename left a cached
        /// settings blob keyed "Segment.io" in UserDefaults. `System.defaultState`
        /// prefers cached settings over `configuration.defaultSettings`, so if that
        /// stale blob were still readable the destination would be disabled and every
        /// event silently dropped. The settings cache key is namespaced to prevent it.
        func testStaleSegmentEraSettingsCacheIsNotHonored() throws {
            let writeKey = uniqueWriteKey("staleSettingsCache")

            // Simulate the Segment-era cache: same suite, the OLD settings key.
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "com.inferise.storage.\(writeKey)"))
            var legacy = Settings(writeKey: writeKey)
            legacy.integrations = try JSON(["Segment.io": true])
            // Must match how Storage persists it (PropertyListEncoder), or the decode
            // fails and this test passes for the wrong reason.
            try defaults.set(PropertyListEncoder().encode(legacy), forKey: "segment.settings")

            let analytics = Analytics(
                configuration: Configuration(writeKey: writeKey)
                    .flushInterval(9999)
                    .flushAt(9999)
                    .httpSession(HostRecordingHTTPSession())
            )
            waitUntilStarted(analytics: analytics)

            let settings = try XCTUnwrap(analytics.settings())
            XCTAssertTrue(
                settings.hasIntegrationSettings(key: InferiseDestination.Constants.integrationName.rawValue),
                "Stale Segment-era settings cache was honored; the destination would drop every event."
            )

            defaults.removeObject(forKey: "segment.settings")
            analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        }

        // MARK: - Full lifecycle

        func testNoSegmentHostRequestedDuringLifecycle_disk() throws {
            try self.runLifecycle(writeKey: uniqueWriteKey("noEgressDisk"), storageMode: .disk)
        }

        func testNoSegmentHostRequestedDuringLifecycle_memory() throws {
            try self.runLifecycle(writeKey: uniqueWriteKey("noEgressMemory"), storageMode: .memory(1000))
        }

        /// Drives init → settings fetch → events → flush and asserts nothing addressed
        /// a Segment host along the way.
        private func runLifecycle(writeKey: String, storageMode: StorageMode) throws {
            let analytics = Analytics(
                configuration: Configuration(writeKey: writeKey)
                    .flushInterval(9999)
                    .flushAt(9999)
                    .storageMode(storageMode)
                    .httpSession(HostRecordingHTTPSession())
            )

            waitUntilStarted(analytics: analytics)
            analytics.storage.hardReset(doYouKnowHowToUseThis: true)

            analytics.identify(userId: "cody", traits: MyTraits(email: "cody@inferise.com"))
            analytics.track(name: "Egress Guard")
            analytics.screen(title: "Guard Screen")

            let flushDone = XCTestExpectation(description: "flush done")
            analytics.flush { flushDone.fulfill() }
            wait(for: [flushDone], timeout: 10)

            // The settings fetch is what would reach a CDN host, so make sure one
            // actually happened — otherwise this test could pass by doing nothing.
            XCTAssertFalse(
                HostRecordingHTTPSession.requestedURLs.isEmpty,
                "No requests were recorded; the guard would pass vacuously."
            )

            let forbidden = HostRecordingHTTPSession.forbiddenURLs
            XCTAssertTrue(
                forbidden.isEmpty,
                "SDK addressed Segment host(s): \(forbidden.map(\.absoluteString).joined(separator: ", "))"
            )

            analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        }
    }

#endif
