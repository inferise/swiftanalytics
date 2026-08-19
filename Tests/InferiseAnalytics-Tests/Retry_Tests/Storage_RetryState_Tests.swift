import XCTest
@testable import InferiseAnalytics

class Storage_RetryState_Tests: XCTestCase {
    var storage: Storage!

    func uniqueWriteKey() -> String {
        "test-\(UUID().uuidString)"
    }

    override func setUp() {
        super.setUp()
        let analytics = Analytics(configuration: Configuration(writeKey: uniqueWriteKey()))
        self.storage = analytics.storage
    }

    override func tearDown() {
        // Clean up
        self.storage.hardReset(doYouKnowHowToUseThis: true)
        super.tearDown()
    }

    func testSaveAndLoadRetryState() {
        let state = RetryState(
            pipelineState: .rateLimited,
            waitUntilTime: 12345.0,
            globalRetryCount: 3,
            batchMetadata: ["batch1": BatchMetadata(failureCount: 2)]
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.pipelineState, .rateLimited)
        XCTAssertEqual(loaded.waitUntilTime, 12345.0)
        XCTAssertEqual(loaded.globalRetryCount, 3)
        XCTAssertEqual(loaded.batchMetadata.count, 1)
    }

    func testLoadRetryStateReturnsDefaultsWhenMissing() {
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.pipelineState, .ready)
        XCTAssertNil(loaded.waitUntilTime)
        XCTAssertEqual(loaded.globalRetryCount, 0)
        XCTAssertTrue(loaded.batchMetadata.isEmpty)
    }

    func testSaveRetryState_WithEmptyBatchMetadata() {
        let state = RetryState(
            pipelineState: .ready,
            waitUntilTime: nil,
            globalRetryCount: 0,
            batchMetadata: [:]
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.pipelineState, .ready)
        XCTAssertTrue(loaded.batchMetadata.isEmpty)
    }

    func testSaveRetryState_WithMultipleBatchMetadataEntries() {
        let state = RetryState(
            batchMetadata: [
                "batch1": BatchMetadata(failureCount: 1, nextRetryTime: 1000, firstFailureTime: 100),
                "batch2": BatchMetadata(failureCount: 2, nextRetryTime: 2000, firstFailureTime: 200),
                "batch3": BatchMetadata(failureCount: 3, nextRetryTime: 3000, firstFailureTime: 300),
            ]
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.batchMetadata.count, 3)
        XCTAssertEqual(loaded.batchMetadata["batch1"]?.failureCount, 1)
        XCTAssertEqual(loaded.batchMetadata["batch2"]?.failureCount, 2)
        XCTAssertEqual(loaded.batchMetadata["batch3"]?.failureCount, 3)
    }

    func testSaveRetryState_OverwritesPreviousState() {
        // Save initial state
        let state1 = RetryState(globalRetryCount: 5)
        self.storage.saveRetryState(state1)

        // Overwrite with new state
        let state2 = RetryState(globalRetryCount: 10)
        self.storage.saveRetryState(state2)

        // Should load the newer state
        let loaded = self.storage.loadRetryState()
        XCTAssertEqual(loaded.globalRetryCount, 10)
    }

    func testLoadRetryState_HandlesNullWaitUntilTime() {
        let state = RetryState(
            pipelineState: .rateLimited,
            waitUntilTime: nil
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.pipelineState, .rateLimited)
        XCTAssertNil(loaded.waitUntilTime)
    }

    func testLoadRetryState_HandlesNullFieldsInBatchMetadata() {
        let state = RetryState(
            batchMetadata: [
                "batch1": BatchMetadata(
                    failureCount: 1,
                    nextRetryTime: nil,
                    firstFailureTime: nil
                ),
            ]
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        let batch = loaded.batchMetadata["batch1"]
        XCTAssertNotNil(batch)
        XCTAssertEqual(batch?.failureCount, 1)
        XCTAssertNil(batch?.nextRetryTime)
        XCTAssertNil(batch?.firstFailureTime)
    }

    func testLoadRetryState_ReturnsDefaultsForCorruptData() {
        // Write corrupt data directly to storage
        let corruptData = Data([0xFF, 0xFE, 0xFD, 0xFC]) // Invalid plist data
        self.storage.write(.retryState, value: corruptData)

        // Should return default state instead of crashing
        let loaded = self.storage.loadRetryState()

        XCTAssertEqual(loaded.pipelineState, .ready)
        XCTAssertNil(loaded.waitUntilTime)
        XCTAssertEqual(loaded.globalRetryCount, 0)
        XCTAssertTrue(loaded.batchMetadata.isEmpty)
    }

    func testLoadRetryState_HandlesUnreasonablePersistedValues() {
        // Save state with unreasonable values
        let impossiblyFarFuture = Date().timeIntervalSince1970 + TimeInterval(Int.max / 2)
        let state = RetryState(
            pipelineState: .rateLimited,
            waitUntilTime: impossiblyFarFuture,
            globalRetryCount: Int.max,
            batchMetadata: [
                "batch1": BatchMetadata(
                    failureCount: Int.max,
                    nextRetryTime: impossiblyFarFuture,
                    firstFailureTime: Date().timeIntervalSince1970 + 10000
                ),
            ]
        )

        self.storage.saveRetryState(state)
        let loaded = self.storage.loadRetryState()

        // PropertyListEncoder/Decoder should handle these values
        // This test documents that extreme values are persisted/loaded without error
        XCTAssertEqual(loaded.pipelineState, .rateLimited)
        XCTAssertEqual(loaded.waitUntilTime, impossiblyFarFuture)
        XCTAssertEqual(loaded.globalRetryCount, Int.max)
        XCTAssertEqual(loaded.batchMetadata["batch1"]?.failureCount, Int.max)

        // Note: The validation of whether these values are "reasonable"
        // happens at usage time (in RetryStateMachine), not at load time
    }
}
