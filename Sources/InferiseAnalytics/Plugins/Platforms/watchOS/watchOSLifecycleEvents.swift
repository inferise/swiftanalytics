//
//  watchOSLifecycleEvents.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 3/29/21.
//

#if os(watchOS)

    import Foundation
    import WatchKit

    class watchOSLifecycleEvents: PlatformPlugin, watchOSLifecycle {
        static var versionKey = "INFVersionKey"
        static var buildKey = "INFBuildKeyV2"

        let type = PluginType.before
        weak var analytics: Analytics?

        func applicationDidFinishLaunching(watchExtension: WKExtension) {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents == TrackedLifecycleEvent.none {
                return
            }

            let previousVersion = UserDefaults.standard.string(forKey: Self.versionKey)
            let previousBuild = UserDefaults.standard.string(forKey: Self.buildKey)

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

            if previousBuild == nil {
                if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationInstalled) == true {
                    self.analytics?.track(name: "Application Installed", properties: [
                        "version": currentVersion ?? "",
                        "build": currentBuild ?? "",
                    ])
                }
            } else if currentBuild != previousBuild {
                if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationUpdated) == true {
                    self.analytics?.track(name: "Application Updated", properties: [
                        "previous_version": previousVersion ?? "",
                        "previous_build": previousBuild ?? "",
                        "version": currentVersion ?? "",
                        "build": currentBuild ?? "",
                    ])
                }
            }

            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationOpened) == true {
                self.analytics?.track(name: "Application Opened", properties: [
                    "from_background": false,
                    "version": currentVersion ?? "",
                    "build": currentBuild ?? "",
                ])
            }

            UserDefaults.standard.setValue(currentVersion, forKey: Self.versionKey)
            UserDefaults.standard.setValue(currentBuild, forKey: Self.buildKey)
        }

        func applicationWillEnterForeground(watchExtension: WKExtension) {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationOpened) == true {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

                self.analytics?.track(name: "Application Opened", properties: [
                    "from_background": true,
                    "version": currentVersion ?? "",
                    "build": currentBuild ?? "",
                ])
            }
        }

        func applicationDidEnterBackground(watchExtension: WKExtension) {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationBackgrounded) == true {
                self.analytics?.track(name: "Application Backgrounded")
            }
        }
    }

#endif
