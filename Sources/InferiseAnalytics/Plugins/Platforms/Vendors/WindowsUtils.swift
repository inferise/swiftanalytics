import Foundation

#if os(Windows)

    import WinSDK

    class WindowsVendorSystem: VendorSystem {
        override var manufacturer: String {
            "unknown"
        }

        override var type: String {
            "Windows"
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
            // If the name is larger than 256 characters, we might get an error.
            var size: DWORD = 256
            var buffer = [CHAR](repeating: 0, count: Int(size))
            guard GetComputerNameA(&buffer, &size) else {
                return "unknown"
            }

            return String(cString: buffer)
        }

        override var systemVersion: String {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }

        override var screenSize: ScreenSize {
            var rect: RECT = .init(left: 0, top: 0, right: 0, bottom: 0)
            guard SystemParametersInfoA(UInt32(SPI_GETWORKAREA), 0, &rect, 0) else {
                return ScreenSize(width: 0, height: 0)
            }

            return ScreenSize(width: rect.width, height: rect.height)
        }

        override var userAgent: String? {
            "unknown"
        }

        override var connection: ConnectionStatus {
            .unknown
        }

        override var requiredPlugins: [any PlatformPlugin] {
            []
        }
    }

    extension RECT {
        var width: Double {
            Double(right - left)
        }

        var height: Double {
            Double(bottom - top)
        }
    }
#endif
