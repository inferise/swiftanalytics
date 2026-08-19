//
//  TransientDB.swift
//
//
//  Created by Brandon Sneed on 11/27/23.
//
import Foundation

public class TransientDB {
    /// our data store
    let store: any DataStore
    // keeps items added in the order given.
    let syncQueue = DispatchQueue(label: "transientDB.sync")
    private let asyncAppend: Bool

    public var hasData: Bool {
        var result: Bool = false
        self.syncQueue.sync {
            result = self.store.hasData
        }
        return result
    }

    public var count: Int {
        var result: Int = 0
        self.syncQueue.sync {
            result = self.store.count
        }
        return result
    }

    public var transactionType: DataTransactionType {
        self.store.transactionType
    }

    public init(store: any DataStore, asyncAppend: Bool = true) {
        self.store = store
        self.asyncAppend = asyncAppend
    }

    public func reset() {
        self.syncQueue.sync {
            self.store.reset()
        }
    }

    public func append(data: RawEvent) {
        if self.asyncAppend {
            self.syncQueue.async { [weak self] in
                guard let self else { return }
                self.store.append(data: data)
            }
        } else {
            self.syncQueue.sync { [weak self] in
                guard let self else { return }
                self.store.append(data: data)
            }
        }
    }

    public func fetch(count: Int? = nil, maxBytes: Int? = nil, offset: Int = 0) -> DataResult? {
        var result: DataResult?
        self.syncQueue.sync {
            result = self.store.fetch(count: count, maxBytes: maxBytes, offset: offset)
        }
        return result
    }

    public func remove(data: [DataStore.ItemID]) {
        self.syncQueue.sync {
            self.store.remove(data: data)
        }
    }
}
