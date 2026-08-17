//
//  Logging.swift
//
//
//  Created by Brandon Sneed on 3/9/23.
//

import Foundation

extension Analytics {
    public enum LogKind: CustomStringConvertible, CustomDebugStringConvertible {
        case error
        case warning
        case debug
        case none

        public var description: String {
            self.string
        }

        public var debugDescription: String {
            self.string
        }

        var string: String {
            switch self {
            case .error:
                "SEG_ERROR: "
            case .warning:
                "SEG_WARNING: "
            case .debug:
                "SEG_DEBUG: "
            case .none:
                "SEG_INFO: "
            }
        }
    }

    public func log(message: String) {
        Self.inferiseLog(message: message, kind: .none)
    }

    static public func inferiseLog(message: String, kind: LogKind) {
        #if DEBUG
            if debugLogsEnabled {
                print("\(kind)\(message)")
            }
        #endif
    }
}
