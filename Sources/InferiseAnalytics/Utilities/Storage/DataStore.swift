//
//  DataStore.swift
//
//
//  Created by Brandon Sneed on 11/27/23.
//

import Foundation

// Not a domain/API model -- this is the shape a storage fetch returns
// (raw data, or file URLs, plus what's removable once uploaded). "DataModel"
// would misdescribe it; the rule's \w+Result regex is aimed at that other
// naming pattern, and this isn't an instance of it.
// swiftlint:disable:next result_suffix_model
public struct DataResult {
    public let data: Data?
    public let dataFiles: [URL]?
    public let removable: [DataStore.ItemID]?

    init(data: Data?, dataFiles: [URL]?, removable: [DataStore.ItemID]?) {
        self.data = data
        self.dataFiles = dataFiles
        self.removable = removable
    }

    public init(data: Data?, removable: [DataStore.ItemID]?) {
        self.init(data: data, dataFiles: nil, removable: removable)
    }

    public init(dataFiles: [URL]?, removable: [DataStore.ItemID]?) {
        self.init(data: nil, dataFiles: dataFiles, removable: removable)
    }
}

public enum DataTransactionType {
    case data
    case file
}

public protocol DataStore {
    typealias ItemID = any Equatable
    associatedtype StoreConfiguration
    var hasData: Bool { get }
    var count: Int { get }
    var transactionType: DataTransactionType { get }
    init(configuration: StoreConfiguration)
    func reset()
    func append(data: RawEvent)
    func fetch(count: Int?, maxBytes: Int?, offset: Int) -> DataResult?
    func remove(data: [ItemID])
}
