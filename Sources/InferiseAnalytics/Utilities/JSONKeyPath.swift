//
//  JSONKeyPath.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 3/19/21.
//

import Foundation

protocol KeyPathHandler {
    func isHandled(_ keyPath: JSONKeyPath, forInput: Any?) -> Bool
    func value(keyPath: JSONKeyPath, input: Any?, reference: Any?) -> Any?
}

public struct BasicHandler: KeyPathHandler {
    func value(keyPath: JSONKeyPath, input: Any?, reference: Any?) -> Any? {
        guard let input = input as? [String: Any] else { return nil }
        var result: Any? = if keyPath.remaining.isEmpty {
            input[keyPath.current]
        } else {
            if let nestedDict = input[keyPath.current] as? [String: Any] {
                nestedDict[keyPath: JSONKeyPath(keyPath.remainingPath)]
            } else {
                nil
            }
        }
        return result
    }

    func isHandled(_ keyPath: JSONKeyPath, forInput: Any?) -> Bool {
        true
    }
}

public struct JSONKeyPath {
    var current: String
    var remaining: [String]

    var remainingPath: String {
        self.remaining.joined(separator: ".")
    }

    public init(_ string: String) {
        var components = string.components(separatedBy: ".")
        self.current = components.removeFirst()
        self.remaining = components
    }

    static var handlers: [KeyPathHandler] = [PathHandler(), IfHandler(), BasicHandler()]
    static func register(_ handler: KeyPathHandler) {
        self.handlers.insert(handler, at: 0)
    }

    static func handlerFor(keyPath: Self, input: Any?) -> KeyPathHandler? {
        guard let input = input as? [String: Any] else { return nil }
        for item in self.handlers where item.isHandled(keyPath, forInput: input[keyPath.current]) {
            return item
        }
        return nil
    }
}

extension JSONKeyPath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }
}

extension Dictionary where Key: StringProtocol, Value: Any {
    func value(keyPath: JSONKeyPath, reference: Any?) -> Any? {
        let handler = JSONKeyPath.handlerFor(keyPath: keyPath, input: self)
        let result = handler?.value(keyPath: keyPath, input: self, reference: reference)
        return result
    }

    mutating func setValue(_ value: Any?, keyPath: JSONKeyPath) {
        guard let key = keyPath.current as? Key else { return }

        if keyPath.remaining.isEmpty {
            if value.flattened() != nil, let typedValue = value as? Value {
                self[key] = typedValue
            } else {
                self.removeValue(forKey: key)
            }
        } else {
            if var nestedDict = self[key] as? [String: Any] {
                nestedDict[keyPath: JSONKeyPath(keyPath.remainingPath)] = value
                if let typedDict = nestedDict as? Value {
                    self[key] = typedDict
                }
            } else {
                // this nested key doesn't exist but we're not at the end of the chain, need to create it
                var nestedDict = [String: Any]()
                nestedDict[keyPath: JSONKeyPath(keyPath.remainingPath)] = value
                if let typedDict = nestedDict as? Value {
                    self[key] = typedDict
                }
            }
        }
    }

    public subscript(keyPath keyPath: JSONKeyPath) -> Any? {
        get { self.value(keyPath: keyPath, reference: nil) }
        set { self.setValue(newValue as Any, keyPath: keyPath) }
    }

    public subscript(keyPath keyPath: JSONKeyPath, reference reference: Any?) -> Any? {
        get { self.value(keyPath: keyPath, reference: reference) }
        set { self.setValue(newValue as Any, keyPath: keyPath) }
    }

    public func exists(keyPath: JSONKeyPath, reference: Any? = nil) -> Bool {
        self.value(keyPath: keyPath, reference: reference) != nil
    }
}

extension String {
    var strippedReference: String {
        self.replacingOccurrences(of: "$.", with: "")
    }
}

// @if, @path, @template

struct IfHandler: KeyPathHandler {
    func isHandled(_ keyPath: JSONKeyPath, forInput: Any?) -> Bool {
        guard let input = forInput as? [String: Any] else { return false }
        if input["@if"] != nil {
            return true
        }
        return false
    }

    func value(keyPath: JSONKeyPath, input: Any?, reference: Any?) -> Any? {
        guard let input = input as? [String: Any] else { return nil }
        let current = input[keyPath.current] as? [String: Any]
        let conditional = current?["@if"] as? [String: Any]

        let isBlank = conditional?["blank"] != nil
        let isExists = conditional?["exists"] != nil

        let blank = conditional?[keyPath: "blank", reference: reference]
        let exists = conditional?[keyPath: "exists", reference: reference]
        let then = conditional?[keyPath: "then", reference: reference]
        let elseCase = conditional?[keyPath: "else", reference: reference]

        var result: Any?

        if isBlank {
            if blank == nil || (blank as? String)?.isEmpty == true {
                result = then
            } else {
                result = elseCase
            }
        } else if isExists {
            if exists != nil {
                result = then
            } else {
                result = elseCase
            }
        }

        return result
    }
}

struct PathHandler: KeyPathHandler {
    func isHandled(_ keyPath: JSONKeyPath, forInput: Any?) -> Bool {
        guard let input = forInput as? [String: Any] else { return false }
        if input["@path"] != nil {
            return true
        }
        return false
    }

    func value(keyPath: JSONKeyPath, input: Any?, reference: Any?) -> Any? {
        guard let input = input as? [String: Any] else { return nil }
        let current = input[keyPath.current] as? [String: Any]
        let path = (current?["@path"] as? String)?.strippedReference

        var result: Any?
        if let path, let reference = reference as? [String: Any] {
            result = reference[keyPath: JSONKeyPath(path)]
        }
        return result
    }
}
