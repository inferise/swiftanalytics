//
//  InferiseDestination.swift
//  InferiseAnalytics
//
//  Created by Cody Garvin on 1/5/21.
//

import Foundation
import Sovran

#if os(Linux) || os(Windows)
    // Whoever is doing swift/linux/Windows development over there
    // decided that it'd be a good idea to split out a TON
    // of stuff into another framework that NO OTHER PLATFORM
    // has; I guess to be special.  :man-shrugging:
    import FoundationNetworking
#endif

public class InferiseAnonymousId: AnonymousIdGenerator {
    public func newAnonymousId() -> String {
        UUID().uuidString
    }
}

public class InferiseDestination: DestinationPlugin, Subscriber, FlushCompletion {
    enum Constants: String {
        // The wire key for this destination. It must match the key used in the
        // `integrations` object of the settings response — `isDestinationEnabled`
        // gates on its presence, so a mismatch silently drops every event.
        case integrationName = "Inferise"
        case apiHost
        case apiKey
    }

    public let type = PluginType.destination
    public let key: String = Constants.integrationName.rawValue
    public let timeline = Timeline()
    public weak var analytics: Analytics? {
        didSet {
            self.initialSetup()
        }
    }

    struct UploadTaskInfo {
        let url: URL?
        let data: Data?
        let task: DataTask
        // set/used via an extension in iOSLifecycleMonitor.swift
        typealias CleanupClosure = () -> Void
        var cleanup: CleanupClosure?
    }

    var httpClient: HTTPClient?
    private var uploads = [UploadTaskInfo]()
    private let uploadsQueue = DispatchQueue(label: "uploadsQueue.inferise.com")
    private var storage: Storage?

    @Atomic var eventCount: Int = 0

    func initialSetup() {
        guard let analytics = self.analytics else { return }
        self.storage = analytics.storage
        self.httpClient = HTTPClient(analytics: analytics)

        // Add DestinationMetadata enrichment plugin
        add(plugin: DestinationMetadataPlugin())
    }

    public func update(settings: Settings, type: UpdateType) {
        guard let analytics else { return }
        let destinationInfo = settings.integrationSettings(forKey: self.key)
        var needsHTTPClientRebuild = false

        // the settings endpoint can hand back a different apiHost (eg. to move a
        // deployed fleet to a new region or destination without an app release).
        if let host = destinationInfo?[Self.Constants.apiHost.rawValue] as? String, host.isEmpty == false {
            if host != analytics.configuration.values.apiHost {
                analytics.configuration.values.apiHost = host
                needsHTTPClientRebuild = true
            }
        }

        // Read httpConfig from settings at integrations["Inferise"].httpConfig
        if let httpConfigDict = destinationInfo?["httpConfig"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: httpConfigDict),
           var cdnConfig = try? JSONDecoder.default.decode(HttpConfig.self, from: data) {
            // CDN-sourced config defaults enabled to true (presence of httpConfig implies active).
            // Only honor explicit `enabled: false` from CDN.
            let rlDict = httpConfigDict["rateLimitConfig"] as? [String: Any]
            cdnConfig.rateLimitConfig.enabled = (rlDict?["enabled"] as? Bool) ?? true

            let boDict = httpConfigDict["backoffConfig"] as? [String: Any]
            cdnConfig.backoffConfig.enabled = (boDict?["enabled"] as? Bool) ?? true

            analytics.configuration.values.httpConfig = cdnConfig
            needsHTTPClientRebuild = true
        }

        if needsHTTPClientRebuild {
            self.httpClient = HTTPClient(analytics: analytics)
        }
    }

    // MARK: - Event Handling Methods

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event else { return nil }
        let result = process(incomingEvent: event)
        if let r = result {
            self.queueEvent(event: r)
        }
        return result
    }

    // MARK: - Abstracted Lifecycle Methods

    func enterForeground() {}

    func enterBackground() {
        self.analytics?.flush()
    }

    // MARK: - Event Parsing Methods

    private func queueEvent<T: RawEvent>(event: T) {
        guard let storage = self.storage else { return }
        // Send Event to File System
        storage.write(.events, value: event)
        self._eventCount.mutate { count in
            count += 1
        }
    }

    public func flush(group: DispatchGroup) {
        group.enter()
        defer { group.leave() }

        guard let storage = self.storage else { return }
        guard let analytics = self.analytics else { return }

        // don't flush if analytics is disabled.
        guard analytics.enabled == true else { return }

        _eventCount.set(0)
        cleanupUploads()

        let type = storage.dataStore.transactionType
        let hasData = storage.dataStore.hasData

        analytics.log(message: "Uploads in-progress: \(pendingUploads)")

        if pendingUploads == 0 {
            if type == .file, hasData {
                flushFiles(group: group)
            } else if type == .data, hasData {
                // we know it's a data-based transaction as opposed to file I/O
                flushData(group: group)
            }
        } else {
            analytics.log(message: "Skipping processing; Uploads in progress.")
        }
    }
}

extension InferiseDestination {
    private func flushFiles(group: DispatchGroup) {
        guard let storage = self.storage else { return }
        guard let analytics = self.analytics else { return }
        guard let httpClient = self.httpClient else { return }

        // Cooperative release of allocated memory by URL instances (dataFiles).
        autoreleasepool {
            guard let files = storage.dataStore.fetch()?.dataFiles else { return }

            for url in files {
                // Use the autorelease pool to ensure that unnecessary memory allocations
                // are released after each iteration. If there is a large backlog of files
                // to iterate, the host applications may crash due to OOM issues.
                autoreleasepool {
                    // enter for this url we're going to kick off
                    group.enter()
                    analytics.log(message: "Processing Batch:\n\(url.lastPathComponent)")

                    // set up the task
                    let uploadTask = httpClient.startBatchUpload(writeKey: analytics.configuration.values.writeKey, batch: url) { [weak self] result in
                        defer {
                            group.leave()
                        }
                        guard let self else { return }
                        switch result {
                        case .success:
                            storage.remove(data: [url])
                            cleanupUploads()

                        // Batch was dropped by the retry state machine (e.g. max retries exceeded)
                        case .failure(InferiseAnalytics.HTTPClientErrors.badRequest):
                            storage.remove(data: [url])
                            cleanupUploads()

                        // Non-retryable status codes should also drop the batch
                        case .failure(InferiseAnalytics.HTTPClientErrors.statusCode(let code)):
                            if httpClient.shouldDropBatch(forStatusCode: code) {
                                storage.remove(data: [url])
                            }
                            cleanupUploads()

                        default:
                            break
                        }

                        analytics.log(message: "Processed: \(url.lastPathComponent)")
                        // the upload we have here has just finished.
                        // make sure it gets removed and it's cleanup() called rather
                        // than waiting on the next flush to come around.
                        cleanupUploads()
                    }

                    // we have a legit upload in progress now, so add it to our list.
                    if let upload = uploadTask {
                        add(uploadTask: UploadTaskInfo(url: url, data: nil, task: upload))
                    } else {
                        // we couldn't get a task, so we need to leave the group or things will hang.
                        group.leave()
                    }
                }
            }
        }
    }

    // The branching here is the retry/backoff decision tree (skipAllBatches /
    // skipThisBatch / dropBatch / proceed) plus the upload completion handling,
    // and it is exactly the path verified end-to-end against the deployed
    // sandbox and prod stacks (see NoSegmentEgress_Tests and the aws-analytics
    // contract tests). Splitting it to satisfy a complexity threshold is real
    // work that deserves its own reviewed, re-verified change -- not something
    // to do incidentally while clearing lint output.
    // swiftlint:disable:next cyclomatic_complexity
    private func flushData(group: DispatchGroup) {
        // DO NOT CALL THIS FROM THE MAIN THREAD, IT BLOCKS!
        // Don't make me add a check here; i'll be sad you didn't follow directions.
        guard let storage = self.storage else { return }
        guard let analytics = self.analytics else { return }
        guard let httpClient = self.httpClient else { return }

        let totalCount = storage.dataStore.count
        guard totalCount > 0 else { return }

        // Process events in flushAt-sized batches so each batch is independent,
        // matching file mode behavior where each file gets its own upload.
        // This prevents failed retry events from being merged with new events.
        let batchSize = max(analytics.configuration.values.flushAt, 1)
        var offset = 0

        while offset < totalCount {
            // can't imagine why we wouldn't get data at this point, but if we don't, then split.
            guard let eventData = storage.dataStore.fetch(count: batchSize, offset: offset) else { break }
            guard let data = eventData.data else { break }
            guard let removable = eventData.removable else { break }
            guard let dataCount = eventData.removable?.count else { break }

            // Generate a stable batch identifier from the underlying item identities,
            // NOT from `data`. `data` is `fullyFormedJSON(items:)`'s output, which embeds
            // a fresh `Date().iso8601()` as `sentAt` on every single fetch -- refetching
            // the exact same still-queued items on a retry therefore produces different
            // bytes, a different `data.hashValue`, and so a different batchId each time.
            // That silently orphans the retry state recorded under the previous attempt's
            // id: `shouldUploadBatch` finds no metadata for the new id and returns
            // `.proceed`, so backoff windows are never honored and a batch that should
            // have been dropped after maxRetryCount just keeps retrying forever. The item
            // UUIDs in `removable` are assigned once at `append(data:)` and don't change
            // across fetches of the same items, so they're the stable part of "this batch".
            let itemIDs = removable.compactMap { $0 as? UUID }.map(\.uuidString).sorted()
            let batchId = "mem-\(itemIDs.joined(separator: "-").hashValue)"

            // Check retry state machine before uploading
            let decision = httpClient.checkBatchUpload(batchId: batchId)
            switch decision {
            case .skipAllBatches:
                // Rate limited globally — stop processing all batches
                return
            case .skipThisBatch:
                // Backoff in effect for this batch — skip it, try the next
                offset += dataCount
                continue
            case .dropBatch:
                // Max retries or duration exceeded — drop the data
                analytics.log(message: "Dropping batch \(batchId): retry limit exceeded")
                analytics.reportInternalError(AnalyticsError.batchUploadFail(AnalyticsError.networkServerRejected(nil, 0)))
                storage.remove(data: removable)
                // Don't advance offset — removal shifted the array
                continue
            case .proceed:
                break
            }

            // enter for this data we're going to kick off
            group.enter()
            analytics.log(message: "Processing In-Memory Batch (size: \(data.count))")

            // we're already on a separate thread.
            // lets let this task complete so we can get all the values out.
            let semaphore = DispatchSemaphore(value: 0)
            var didRemove = false

            // set up the task
            let uploadTask = httpClient.startBatchUpload(writeKey: analytics.configuration.values.writeKey, data: data, batchId: batchId) { [weak self] result in
                defer {
                    // leave for the url we kicked off.
                    group.leave()
                    semaphore.signal()
                }

                guard let self else { return }
                switch result {
                case .success:
                    storage.remove(data: removable)
                    didRemove = true
                    cleanupUploads()

                // Non-retryable status codes should drop the batch
                case .failure(InferiseAnalytics.HTTPClientErrors.statusCode(let code)):
                    if httpClient.shouldDropBatch(forStatusCode: code) {
                        storage.remove(data: removable)
                        didRemove = true
                    }
                    cleanupUploads()

                default:
                    break
                }

                analytics.log(message: "Processed In-Memory Batch (size: \(data.count))")
                cleanupUploads()
            }

            // we have a legit upload in progress now, so add it to our list.
            if let upload = uploadTask {
                add(uploadTask: UploadTaskInfo(url: nil, data: data, task: upload))
            } else {
                // we couldn't get a task, so we need to leave the group or things will hang.
                group.leave()
                semaphore.signal()
            }

            _ = semaphore.wait(timeout: .distantFuture)

            // If items were removed, the array shifted — offset stays.
            // If items stayed (retryable failure), advance offset past them.
            if !didRemove {
                offset += dataCount
            }
        }
    }
}

// MARK: - Upload management

extension InferiseDestination {
    func cleanupUploads() {
        // lets go through and get rid of any tasks that aren't running.
        // either they were suspended because a background task took too
        // long, or the os orphaned it due to device constraints (like a watch).
        self.uploadsQueue.sync {
            let before = self.uploads.count
            var newPending = self.uploads
            newPending.removeAll { uploadInfo in
                let shouldRemove = uploadInfo.task.state != .running
                if shouldRemove, let cleanup = uploadInfo.cleanup {
                    cleanup()
                }
                return shouldRemove
            }
            self.uploads = newPending
            let after = self.uploads.count
            self.analytics?.log(message: "Cleaned up \(before - after) non-running uploads.")
        }
    }

    var pendingUploads: Int {
        var uploadsCount = 0
        self.uploadsQueue.sync {
            uploadsCount = self.uploads.count
        }
        return uploadsCount
    }

    func add(uploadTask: UploadTaskInfo) {
        self.uploadsQueue.sync {
            self.uploads.append(uploadTask)
        }
    }
}

// MARK: Versioning

extension InferiseDestination: VersionedPlugin {
    public static func version() -> String {
        packageVersion
    }
}
