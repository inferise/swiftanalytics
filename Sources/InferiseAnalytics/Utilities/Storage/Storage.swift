//
//  Storage.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 1/5/21.
//

import Foundation
import Sovran

class Storage: Subscriber {
    let writeKey: String
    let userDefaults: UserDefaults
    static let MAXFILESIZE = 475_000 // Server accepts max 500k per batch

    weak var analytics: Analytics?

    let dataStore: TransientDB
    let storageMode: StorageMode

    init(store: Store, writeKey: String, storageMode: StorageMode, operatingMode: OperatingMode) {
        self.writeKey = writeKey
        self.storageMode = storageMode
        self.userDefaults = UserDefaults(suiteName: "com.inferise.storage.\(writeKey)")!

        var storageURL = InferiseAnalytics.eventStorageDirectory(writeKey: writeKey)
        let asyncAppend = (operatingMode == .asynchronous)
        switch storageMode {
        case .diskAtURL(let url):
            storageURL = url
            fallthrough
        case .disk:
            let store = DirectoryStore(
                configuration: DirectoryStore.Configuration(
                    writeKey: writeKey,
                    storageLocation: storageURL,
                    baseFilename: "inferise-events",
                    maxFileSize: Self.MAXFILESIZE,
                    indexKey: Self.Constants.events.rawValue
                )
            )
            self.dataStore = TransientDB(store: store, asyncAppend: asyncAppend)
        case .memory(let max):
            let store = MemoryStore(
                configuration: MemoryStore.Configuration(
                    writeKey: writeKey,
                    maxItems: max,
                    maxFetchSize: Self.MAXFILESIZE
                )
            )
            self.dataStore = TransientDB(store: store, asyncAppend: asyncAppend)
        case .custom(let store):
            self.dataStore = TransientDB(store: store, asyncAppend: asyncAppend)
        }

        store.subscribe(self) { [weak self] (state: UserInfo) in
            self?.userInfoUpdate(state: state)
        }
        store.subscribe(self) { [weak self] (state: System) in
            self?.systemUpdate(state: state)
        }
    }

    func write<T: Encodable>(_ key: Storage.Constants, value: T?) {
        switch key {
        case .events:
            if let event = value as? RawEvent {
                self.dataStore.append(data: event)
                if let flushPolicies = analytics?.configuration.values.flushPolicies {
                    for policy in flushPolicies {
                        policy.updateState(event: event)

                        if policy.shouldFlush() == true {
                            policy.reset()
                        }
                    }
                }
            }
        default:
            if self.isBasicType(value: value) {
                // we can write it like normal
                self.userDefaults.set(value, forKey: key.rawValue)
            } else {
                // encode it to a data object to store
                let encoder = PropertyListEncoder()
                if let plistValue = try? encoder.encode(value) {
                    self.userDefaults.set(plistValue, forKey: key.rawValue)
                }
            }
            self.userDefaults.synchronize()
        }
    }

    func read(_ key: Storage.Constants) -> DataResult? {
        switch key {
        case .events:
            return self.dataStore.fetch()
        default:
            break
        }
        return nil
    }

    func read<T: Decodable>(_ key: Storage.Constants) -> T? {
        var result: T?
        switch key {
        case .events:
            // do nothing
            break
        default:
            let decoder = PropertyListDecoder()
            let raw = self.userDefaults.object(forKey: key.rawValue)
            if let r = raw as? Data {
                // it's an encoded object, not a basic type
                result = try? decoder.decode(T.self, from: r)
            } else {
                // it's a basic type
                result = self.userDefaults.object(forKey: key.rawValue) as? T
            }
        }
        return result
    }

    static func hardSettingsReset(writeKey: String) {
        guard let defaults = UserDefaults(suiteName: "com.inferise.storage.\(writeKey)") else { return }
        for key in Constants.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func hardReset(doYouKnowHowToUseThis: Bool) {
        if doYouKnowHowToUseThis != true {
            return
        }
        self.dataStore.reset()
        guard let defaults = UserDefaults(suiteName: "com.inferise.storage.\(writeKey)") else { return }
        for key in Constants.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func isBasicType<T: Encodable>(value: T?) -> Bool {
        var result = false
        if value == nil {
            result = true
        } else {
            switch value {
            // NSNull is not valid for UserDefaults
            // case is NSNull:
            case is Decimal, is NSNumber, is Bool, is String:
                result = true
            default:
                break
            }
        }
        return result
    }

    func remove(data: [DataStore.ItemID]?) {
        guard let data else { return }
        self.dataStore.remove(data: data)
    }
}

// MARK: - String Contants

extension Storage {
    private static let tempExtension = "temp"

    enum Constants: String, CaseIterable {
        case userId = "inferise.userId"
        case traits = "inferise.traits"
        case anonymousId = "inferise.anonymousId"
        // These keys, and the UserDefaults suite that holds them, are namespaced
        // to `inferise` — nothing here reads the upstream `segment` namespace.
        // That is deliberate and it is not a migration: an install carrying data
        // written by a Segment-keyed build starts fresh, with a new anonymousId
        // and no queued events.
        //
        // It also happens to close a trap. `System.defaultState` prefers cached
        // settings over `configuration.defaultSettings`, so reading an old cache
        // would hand back an `integrations` object containing only "Segment.io";
        // `isDestinationEnabled` would find no "Inferise" entry and silently drop
        // every event until a settings fetch succeeded — forever, if the device
        // were offline at launch.
        case settings = "inferise.settings"
        case events = "inferise.events"
        case retryState = "inferise.retryState"
    }
}

// MARK: - State Subscriptions

extension Storage {
    func userInfoUpdate(state: UserInfo) {
        // write new stuff to disk
        self.write(.userId, value: state.userId)
        self.write(.traits, value: state.traits)
        self.write(.anonymousId, value: state.anonymousId)
    }

    func systemUpdate(state: System) {
        // write new stuff to disk
        if let s = state.settings {
            self.write(.settings, value: s)
        }
    }
}

// MARK: - Retry State Persistence

extension Storage {
    func loadRetryState() -> RetryState {
        // Try to read from UserDefaults
        guard let data: Data = read(.retryState) else {
            return RetryState() // Default if not found
        }

        // Try to decode
        do {
            let decoder = PropertyListDecoder()
            return try decoder.decode(RetryState.self, from: data)
        } catch {
            // Corrupt data -> return defaults
            return RetryState()
        }
    }

    func saveRetryState(_ state: RetryState) {
        let encoder = PropertyListEncoder()
        if let data = try? encoder.encode(state) {
            self.write(.retryState, value: data)
        }
    }
}
