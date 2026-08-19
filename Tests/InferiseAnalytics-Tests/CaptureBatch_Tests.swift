//
//  CaptureBatch_Tests.swift
//  InferiseAnalytics-Tests
//
//  Fixture generator, not an assertion. Writes a real batch file — exactly the
//  bytes this SDK would POST to /v1/b — so the ingest service can test against
//  the genuine payload instead of a hand-written approximation of it.
//
//  The ingest side consumes it at:
//    aws-analytics/internal/app/testdata/swift-batch.json
//
//  Regenerate after any change to the event payload (context fields, envelope,
//  library identity) so the two sides can't drift apart unnoticed:
//
//    CAPTURE_BATCH_TO=../aws-analytics/internal/app/testdata/swift-batch.json \
//      swift test --filter CaptureBatch
//
//  Skips silently when that variable is unset, so normal runs ignore it.
//

#if !os(Linux) && !os(Windows)

    import XCTest
    @testable import InferiseAnalytics

    class CaptureBatch_Tests: XCTestCase {
        func testCaptureRealBatch() throws {
            guard let destination = ProcessInfo.processInfo.environment["CAPTURE_BATCH_TO"] else {
                throw XCTSkip("Set CAPTURE_BATCH_TO to regenerate the ingest fixture.")
            }

            // The write key is baked into the batch trailer, so it has to match the
            // one the ingest contract test registers.
            let analytics = Analytics(
                configuration: Configuration(writeKey: "inf-local-dev-key")
                    .flushAt(9999)
                    .flushInterval(9999)
                    .blockNetworkEgress()
            )

            waitUntilStarted(analytics: analytics)
            analytics.storage.hardReset(doYouKnowHowToUseThis: true)

            // One of each event type the ingest fixture asserts on.
            analytics.track(name: "Signed In", properties: ["plan": "pro", "seats": 3])
            analytics.identify(userId: "u1", traits: ["email": "cody@inferise.com"])
            analytics.screen(title: "Dashboard")

            // Reading the events finalizes the open file — writing its trailer with
            // sentAt and writeKey — which is what makes this a complete batch.
            let result = try XCTUnwrap(analytics.storage.read(.events))
            let batchFile = try XCTUnwrap(result.dataFiles?.first)

            let target = URL(fileURLWithPath: destination)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: batchFile, to: target)
            print("Captured batch fixture -> \(target.path)")

            analytics.storage.hardReset(doYouKnowHowToUseThis: true)
        }
    }

#endif
