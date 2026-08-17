//
//  Analytics.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 11/17/20.
//

import Foundation
import Sovran

// MARK: - Base Setup

public class Analytics {
    var configuration: Configuration {
        // we're absolutely certain we will have a config
        let system: System = self.store.currentState()!
        return system.configuration
    }

    var store: Store
    var storage: Storage

    /// Enabled/disables debug logging to trace your data going through the SDK.
    public static var debugLogsEnabled = false

    public var timeline: Timeline

    static let deadInstance = "DEADINSTANCE"
    static weak var firstInstance: Analytics?

    @Atomic static var activeWriteKeys = [String]()

    @Atomic var lastSettingsCheck: Date = .distantPast
    @Atomic var isCheckingSettings: Bool = false

    func recordSettingsCheckTimestamp(_ date: Date = Date()) {
        _lastSettingsCheck.set(date)
    }

    func tryBeginCheckingSettings() -> Bool {
        var didBegin = false
        _isCheckingSettings.mutate { flag in
            if !flag {
                flag = true
                didBegin = true
            }
        }
        return didBegin
    }

    func endCheckingSettings() {
        _isCheckingSettings.set(false)
    }

    /// Used for WaitingPlugin's, see waiting.swift
    var processingTimer: DispatchWorkItem?

    /**
     This method isn't a traditional singleton implementation.  It's provided here
     to ease migration from analytics-ios to analytics-swift.  Rather than return a
     singleton, it returns the first instance of Analytics created, OR an instance
     who's writekey is "DEADINSTANCE".

     In the case of a dead instance, an assert will be thrown when in DEBUG builds to
     assist developers in knowning that `shared()` is being called too soon.
     */
    public static func shared() -> Analytics {
        if let a = firstInstance {
            if a.isDead == false {
                return a
            }
        }

        #if DEBUG
            if isUnitTesting == false {
                assert(true == false, "An instance of Analytice does not exist!")
            }
        #endif

        return Analytics(configuration: Configuration(writeKey: self.deadInstance))
    }

    /// Initialize this instance of Analytics with a given configuration setup.
    /// - Parameters:
    ///    - configuration: The configuration to use
    public init(configuration: Configuration) {
        if Self.isActiveWriteKey(configuration.values.writeKey) {
            // If you're hitting this in testing, it could be a memory leak, or something async is still running
            // and holding a reference.  You can use XCTest.waitUntilFinished(...) to wait for things to complete.
            fatalError("Cannot initialize multiple instances of Analytics with the same write key")
        } else {
            Self.addActiveWriteKey(configuration.values.writeKey)
        }

        self.store = Store()
        self.storage = Storage(
            store: self.store,
            writeKey: configuration.values.writeKey,
            storageMode: configuration.values.storageMode,
            operatingMode: configuration.values.operatingMode
        )
        self.timeline = Timeline()

        // provide our default state
        self.store.provide(state: System.defaultState(configuration: configuration, from: self.storage))
        self.store.provide(
            state: UserInfo.defaultState(
                from: self.storage, anonIdGenerator: configuration.values.anonymousIdGenerator
            )
        )

        self.storage.analytics = self

        checkSharedInstance()

        // Get everything running
        platformStartup()
    }

    deinit {
        Self.removeActiveWriteKey(configuration.values.writeKey)
    }

    func process<E: RawEvent>(incomingEvent: E, enrichments: [EnrichmentClosure]? = nil) {
        guard enabled == true else { return }
        let event = incomingEvent.applyRawEventData(store: self.store, enrichments: enrichments)

        _ = self.timeline.process(incomingEvent: event)

        /* let flushPolicies = configuration.values.flushPolicies
         for policy in flushPolicies {
             policy.updateState(event: event)

             if (policy.shouldFlush() == true) {
                 flush()
                 policy.reset()
             }
         } */

        let flushPolicies = self.configuration.values.flushPolicies

        var shouldFlush = false
        // if any policy says to flush, make note of that
        for policy in flushPolicies {
            policy.updateState(event: event)
            if policy.shouldFlush() {
                shouldFlush = true
                // we don't need to updateState on any others since we're gonna reset it below.
                break
            }
        }
        // if we were told to flush do it.
        if shouldFlush {
            // reset all the policies if one decided to flush.
            for flushPolicy in flushPolicies {
                flushPolicy.reset()
            }
            flush()
        }
    }

    /// Process a raw event through the system.  Useful when one needs to queue and replay events at a later time.
    /// - Parameters:
    ///   - event: An event conforming to RawEvent that will be processed.
    public func process(event: RawEvent) {
        guard enabled == true else { return }
        switch event {
        case let e as TrackEvent:
            self.timeline.process(incomingEvent: e)
        case let e as IdentifyEvent:
            self.timeline.process(incomingEvent: e)
        case let e as ScreenEvent:
            self.timeline.process(incomingEvent: e)
        case let e as GroupEvent:
            self.timeline.process(incomingEvent: e)
        case let e as AliasEvent:
            self.timeline.process(incomingEvent: e)
        default:
            break
        }
    }
}

// MARK: - System Modifiers

extension Analytics {
    /// Enable/Disable analytics capture
    public var enabled: Bool {
        get {
            if let system: System = store.currentState() {
                return system.enabled
            }
            // we don't have state if we get here, so assume we're not enabled.
            return false
        }
        set(value) {
            self.store.dispatch(action: System.ToggleEnabledAction(enabled: value))
        }
    }

    /// Returns the writekey in use for this instance.
    public var writeKey: String {
        self.configuration.values.writeKey
    }

    /// Returns the anonymousId currently in use.
    public var anonymousId: String {
        if let userInfo: UserInfo = store.currentState() {
            return userInfo.anonymousId
        }
        return ""
    }

    /// Returns the userId that was specified in the last identify call.
    public var userId: String? {
        if let userInfo: UserInfo = store.currentState() {
            return userInfo.userId
        }
        return nil
    }

    /// Returns the current operating mode this instance was given.
    public var operatingMode: OperatingMode {
        self.configuration.values.operatingMode
    }

    /// Adjusts the flush interval post configuration.
    public var flushInterval: TimeInterval {
        get {
            self.configuration.values.flushInterval
        }
        set(value) {
            if let state: System = store.currentState() {
                let config = state.configuration.flushInterval(value)
                self.store.dispatch(action: System.UpdateConfigurationAction(configuration: config))
            }
        }
    }

    /// Adjusts the flush-at count post configuration.
    public var flushAt: Int {
        get {
            self.configuration.values.flushAt
        }
        set(value) {
            if let state: System = store.currentState() {
                let config = state.configuration.flushAt(value)
                self.store.dispatch(action: System.UpdateConfigurationAction(configuration: config))
            }
        }
    }

    /// Returns a list of currently active flush policies.
    public var flushPolicies: [FlushPolicy] {
        self.configuration.values.flushPolicies
    }

    /// Returns the traits that were specified in the last identify call.
    public func traits<T: Decodable>() -> T? {
        if let userInfo: UserInfo = store.currentState() {
            return userInfo.traits.codableValue()
        }
        return nil
    }

    /// Returns the traits that were specified in the last identify call, as a dictionary.
    public func traits() -> [String: Any]? {
        if let userInfo: UserInfo = store.currentState() {
            return userInfo.traits.dictionaryValue
        }
        return nil
    }

    /// Tells this instance of Analytics to flush any queued events to the ingest API.  This command will also
    /// be sent to each plugin present in the system.  A completion handler can be optionally given and will be
    /// called when flush has completed.
    public func flush(completion: (() -> Void)? = nil) {
        // only flush if we're enabled.
        guard self.enabled == true else {
            completion?()
            return
        }

        let completionGroup = CompletionGroup(queue: configuration.values.flushQueue)
        apply { plugin in
            completionGroup.add { group in
                if let p = plugin as? FlushCompletion {
                    p.flush(group: group)
                } else if let p = plugin as? EventPlugin {
                    group.enter()
                    p.flush()
                    group.leave()
                }
            }
        }

        completionGroup.run(mode: self.operatingMode) {
            completion?()
        }
    }

    /// Resets this instance of Analytics to a clean slate.  Traits, UserID's, anonymousId, etc are all cleared or reset.  This
    /// command will also be sent to each plugin present in the system.
    public func reset() {
        self.store.dispatch(action: UserInfo.ResetAction())
        apply { plugin in
            if let p = plugin as? EventPlugin {
                p.reset()
            }
        }
    }

    /// Subscribes to UserInfo state changes.
    ///
    /// The handler is called immediately with the current UserInfo, then again whenever
    /// the user's identity, traits, or referrer changes. The subscription remains active
    /// for the lifetime of the Analytics instance unless explicitly unsubscribed.
    ///
    /// - Parameter handler: A closure called on the main queue with updated UserInfo.
    ///
    /// - Returns: A subscription ID that can be passed to `unsubscribe(_:)` to stop
    ///   receiving updates. If you don't need to unsubscribe, you can ignore the return value.
    ///
    /// - Note: Multiple calls create multiple independent subscriptions.
    ///
    /// ## Example
    /// ```swift
    /// // Subscribe for the lifetime of Analytics
    /// analytics.subscribeToUserInfo { userInfo in
    ///     print("User: \(userInfo.userId ?? userInfo.anonymousId)")
    ///     if let referrer = userInfo.referrer {
    ///         print("Referred from: \(referrer)")
    ///     }
    /// }
    ///
    /// // Subscribe with manual cleanup
    /// let subscriptionId = analytics.subscribeToUserInfo { userInfo in
    ///     // ... handle update
    /// }
    /// // Later, when you're done...
    /// analytics.unsubscribe(subscriptionId)
    /// ```
    @discardableResult
    public func subscribeToUserInfo(handler: @escaping (UserInfo) -> Void) -> Int {
        self.store.subscribe(self, initialState: true, queue: .main) { (state: UserInfo) in
            handler(state)
        }
    }

    /// Unsubscribes from state updates.
    ///
    /// Stops receiving updates for the subscription associated with the given ID.
    /// After calling this, the handler will no longer be invoked for state changes.
    ///
    /// - Parameter id: The subscription ID returned from a previous subscribe call.
    ///
    /// - Note: Unsubscribing an already-unsubscribed or invalid ID is a no-op.
    ///
    /// ## Example
    /// ```swift
    /// let id = analytics.subscribeToUserInfo { userInfo in
    ///     print("User changed: \(userInfo.userId ?? "anonymous")")
    /// }
    ///
    /// // Later, stop listening
    /// analytics.unsubscribe(id)
    /// ```
    public func unsubscribe(_ id: Int) {
        self.store.unsubscribe(identifier: id)
    }

    /// Retrieve the version of this library in use.
    /// - Returns: A string representing the version in "BREAKING.FEATURE.FIX" format.
    public func version() -> String {
        Self.version()
    }

    /// Retrieve the version of this library in use.
    /// - Returns: A string representing the version in "BREAKING.FEATURE.FIX" format.
    public static func version() -> String {
        packageVersion
    }
}

extension Analytics {
    /// Manually retrieve the settings that were supplied by the settings endpoint.
    /// - Returns: A Settings object containing integration settings, tracking plan, etc.
    public func settings() -> Settings? {
        var settings: Settings?
        if let system: System = store.currentState() {
            settings = system.settings
        }
        return settings
    }

    /// Manually enable a destination plugin.  This is useful when a given DestinationPlugin isn't
    /// represented in the settings payload at all.
    /// This will allow the destination to be processed in the same way within this library.
    /// - Parameters:
    ///   - plugin: The destination plugin to enable.
    public func manuallyEnableDestination(plugin: DestinationPlugin) {
        self.store.dispatch(action: System.AddDestinationToSettingsAction(key: plugin.key))
    }
}

extension Analytics {
    /// Determine if there are any events that have yet to be uploaded
    public var hasUnsentEvents: Bool {
        if let inferiseDest = self.find(pluginType: InferiseDestination.self) {
            if inferiseDest.pendingUploads > 0 {
                return true
            }
            if inferiseDest.eventCount > 0 {
                return true
            }
        }

        return self.storage.dataStore.hasData
    }

    /// Provides a list of finished, but unsent events.
    public var pendingUploads: [URL]? {
        self.storage.read(Storage.Constants.events)?.dataFiles
    }

    /// Purge all pending event upload files.
    public func purgeStorage() {
        self.storage.dataStore.reset()
    }

    /// Purge a single event upload file.
    public func purgeStorage(fileURL: URL) {
        guard let dataFiles = storage.read(Storage.Constants.events)?.dataFiles else { return }
        if dataFiles.contains(fileURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Wait until the Analytics object has completed startup.
    /// This method is primarily useful for command line utilities where
    /// it's desirable to wait until the system is up and running
    /// before executing commands.  GUI apps could potentially use this via
    /// a background thread if needed.
    public func waitUntilStarted() {
        if let startupQueue = find(pluginType: StartupQueue.self) {
            while startupQueue.running != true {
                RunLoop.main.run(until: Date.distantPast)
            }
        }
    }
}

extension Analytics {
    /**
     Call openURL as needed or when instructed to by either UIApplicationDelegate or UISceneDelegate.
     This is necessary to track URL referrers across events.  This method will also iterate
     any plugins that are watching for openURL events.

     Example:
     ```
     func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
         let myStruct = MyStruct(options)
         analytics?.openURL(url, options: options)
         return true
     }
     ```
     */
    public func openURL<T: Encodable>(_ url: URL, options: T? = nil) {
        guard let jsonProperties = try? JSON(with: options) else { return }
        guard let dict = jsonProperties.dictionaryValue else { return }
        self.openURL(url, options: dict)
    }

    /**
     Call openURL as needed or when instructed to by either UIApplicationDelegate or UISceneDelegate.
     This is necessary to track URL referrers across events.  This method will also iterate
     any plugins that are watching for openURL events.

     Example:
     ```
     func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
         analytics?.openURL(url, options: options)
         return true
     }
     ```
     */
    public func openURL(_ url: URL, options: [String: Any] = [:]) {
        self.store.dispatch(action: UserInfo.SetReferrerAction(url: url))

        // let any conforming plugins know
        apply { plugin in
            if let p = plugin as? OpeningURLs {
                p.openURL(url, options: options)
            }
        }

        var jsonProperties: JSON?
        if let json = try? JSON(options) {
            do {
                jsonProperties = try json.add(value: url.absoluteString, forKey: "url")
            } catch {
                jsonProperties = json
            }
        } else {
            if let json = try? JSON(["url": url.absoluteString]) {
                jsonProperties = json
            }
        }
        track(name: "Deep Link Opened", properties: jsonProperties)
    }
}

// MARK: Private Stuff

extension Analytics {
    private func checkSharedInstance() {
        // is firstInstance a dead one?  If so, override it.
        if let firstInstance = Self.firstInstance {
            if firstInstance.isDead {
                Self.firstInstance = self
            }
        }
        // is firstInstance nil?  If so, set it.
        if Self.firstInstance == nil {
            Self.firstInstance = self
        }
    }

    /// Determines if an instance is dead.
    var isDead: Bool {
        self.configuration.values.writeKey == Self.deadInstance
    }

    /// Manage active writekeys.  It's wrapped in @atomic
    static func isActiveWriteKey(_ writeKey: String) -> Bool {
        self.activeWriteKeys.contains(writeKey)
    }

    static func addActiveWriteKey(_ writeKey: String) {
        _activeWriteKeys.mutate { keys in
            keys.append(writeKey)
        }
    }

    static func removeActiveWriteKey(_ writeKey: String) {
        _activeWriteKeys.mutate { keys in
            keys.removeAll { key in
                writeKey == key
            }
        }
    }
}

// MARK: Operating mode based scheduling

extension OperatingMode {
    func run(queue: DispatchQueue, task: @escaping () -> Void) {
        //
        switch self {
        case .asynchronous:
            queue.async {
                task()
            }
        case .synchronous:
            // in synchronous mode, always use our own queue to
            // prevent deadlocks.
            let workItem = DispatchWorkItem(block: task)
            Self.defaultQueue.asyncAndWait(execute: workItem)
        }
    }
}
