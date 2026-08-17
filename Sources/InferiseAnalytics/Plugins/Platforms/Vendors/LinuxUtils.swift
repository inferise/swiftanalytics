//
//  LinuxUtils.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 2/24/21.
//

import Foundation

#if os(Linux)

    class LinuxVendorSystem: VendorSystem {
        override var manufacturer: String {
            "unknown"
        }

        override var type: String {
            "Linux"
        }

        override var model: String {
            "unknown"
        }

        override var name: String {
            "unknown"
        }

        override var identifierForVendor: String? {
            nil
        }

        override var systemName: String {
            "unknown"
        }

        override var systemVersion: String {
            ""
        }

        override var screenSize: ScreenSize {
            ScreenSize(width: 0, height: 0)
        }

        override var userAgent: String? {
            UserAgent.value
        }

        override var connection: ConnectionStatus {
            ConnectionStatus.unknown
        }

        override var requiredPlugins: [PlatformPlugin] {
            []
        }
    }

#endif
