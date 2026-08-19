//
//  VendorSystem.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 2/26/21.
//

import Foundation

struct ScreenSize {
    let width: Double
    let height: Double
}

enum ConnectionType {
    case cellular
    case wifi
    case bluetooth
}

enum ConnectionStatus {
    case offline
    case online(ConnectionType)
    case unknown
}

class VendorSystem {
    var manufacturer: String {
        "unknown"
    }

    var type: String {
        "unknown"
    }

    var model: String {
        "unknown"
    }

    var name: String {
        "unknown"
    }

    var identifierForVendor: String? {
        nil
    }

    var systemName: String {
        "unknown"
    }

    var systemVersion: String {
        ""
    }

    var screenSize: ScreenSize {
        ScreenSize(width: 0, height: 0)
    }

    var userAgent: String? {
        "unknown"
    }

    var connection: ConnectionStatus {
        ConnectionStatus.unknown
    }

    var requiredPlugins: [PlatformPlugin] {
        []
    }

    static var current: VendorSystem = {
        #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
            return iOSVendorSystem()
        #elseif os(macOS)
            return MacOSVendorSystem()
        #elseif os(watchOS)
            return watchOSVendorSystem()
        #elseif os(Linux)
            return LinuxVendorSystem()
        #else
            return VendorSystem()
        #endif
    }()
}
