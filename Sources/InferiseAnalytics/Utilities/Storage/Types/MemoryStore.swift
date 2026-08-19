//
//  MemoryStore.swift
//
//
//  Created by Brandon Sneed on 11/27/23.
//

import Foundation

public class MemoryStore: DataStore {
    public typealias StoreConfiguration = Configuration

    public struct Configuration {
        let writeKey: String
        let maxItems: Int
        let maxFetchSize: Int

        public init(writeKey: String, maxItems: Int, maxFetchSize: Int) {
            self.writeKey = writeKey
            self.maxItems = maxItems
            self.maxFetchSize = maxFetchSize
        }
    }

    struct ItemData {
        let id: UUID
        let data: Data

        init(data: Data) {
            self.id = UUID()
            self.data = data
        }
    }

    var items = [ItemData]()

    public var hasData: Bool {
        !self.items.isEmpty
    }

    public var count: Int {
        self.items.count
    }

    public var transactionType: DataTransactionType {
        .data
    }

    let config: Configuration

    public required init(configuration: Configuration) {
        self.config = configuration
    }

    public func reset() {
        self.items.removeAll()
    }

    public func append(data: RawEvent) {
        guard let d = data.toString().data(using: .utf8) else { return }
        self.items.append(ItemData(data: d))
        if self.items.count > self.config.maxItems {
            self.items.removeFirst()
        }
    }

    public func fetch(count: Int?, maxBytes: Int?, offset: Int = 0) -> DataResult? {
        var skipped = 0
        var accumulatedCount = 0
        var accumulatedSize: Int = 0
        var results = [ItemData]()

        let maxBytes = maxBytes ?? self.config.maxFetchSize

        for item in self.items {
            if skipped < offset {
                skipped += 1
                continue
            }
            if accumulatedSize + item.data.count > maxBytes {
                break
            }
            if let count, accumulatedCount >= count {
                break
            }
            accumulatedCount += 1
            accumulatedSize += item.data.count
            results.append(item)
        }
        if !results.isEmpty {
            let removable = results.map { item in
                item.id
            }
            return DataResult(data: fullyFormedJSON(items: results), removable: removable)
        }
        return nil
    }

    public func remove(data: [DataStore.ItemID]) {
        self.items.removeAll { itemData in
            let present = data.contains { id in
                guard let id = id as? UUID else { return false }
                return itemData.id == id
            }
            return present
        }
    }
}

extension MemoryStore {
    func fullyFormedJSON(items: [ItemData]) -> Data? {
        guard !items.isEmpty else { return nil }
        var json = Data()
        let start = "{ \"batch\": [".data(using: .utf8)!
        let end = "],\"sentAt\":\"\(Date().iso8601())\",\"writeKey\":\"\(self.config.writeKey)\"}".data(using: .utf8)!

        json.append(start)
        for index in items.indices {
            if index == 0 {
                json.append(items[index].data)
            } else {
                json.append(",".data(using: .utf8)!)
                json.append(items[index].data)
            }
        }
        json.append(end)

        return json
    }
}
