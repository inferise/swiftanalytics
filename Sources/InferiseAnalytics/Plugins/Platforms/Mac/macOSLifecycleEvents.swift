//
//  macOSLifecycleEvents.swift
//  InferiseAnalytics
//
//  Created by Cody on 4/20/22.
//

import Foundation

#if os(macOS)

    import Cocoa

    class macOSLifecycleEvents: PlatformPlugin, macOSLifecycle {
        static var versionKey = "INFVersionKey"
        static var buildKey = "INFBuildKeyV2"

        let type = PluginType.before
        weak var analytics: Analytics?

        /// Since application:didFinishLaunchingWithOptions is not automatically called with Scenes / SwiftUI,
        /// this gets around by using a flag in user defaults to check for big events like application updating,
        /// being installed or even opening.
        @Atomic
        private var didFinishLaunching = false

        func application(didFinishLaunchingWithOptions launchOptions: [String: Any]?) {
            // Make sure we aren't double calling application:didFinishLaunchingWithOptions
            // by resetting the check at the start
            _didFinishLaunching.set(true)

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

        func applicationDidUnhide() {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationUnhidden) == true {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

                self.analytics?.track(name: "Application Unhidden", properties: [
                    "from_background": true,
                    "version": currentVersion ?? "",
                    "build": currentBuild ?? "",
                ])
            }
        }

        func applicationDidHide() {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationHidden) == true {
                self.analytics?.track(name: "Application Hidden")
            }
        }

        func applicationDidResignActive() {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationBackgrounded) == true {
                self.analytics?.track(name: "Application Backgrounded")
            }
        }

        func applicationDidBecomeActive() {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationForegrounded) == false {
                return
            }
            self.analytics?.track(name: "Application Foregrounded")

            // Lets check if we skipped application:didFinishLaunchingWithOptions,
            // if so, lets call it.
            if self.didFinishLaunching == false {
                // Call application did finish launching
                self.application(didFinishLaunchingWithOptions: nil)
            }
        }

        func applicationWillTerminate() {
            if self.analytics?.configuration.values.trackedApplicationLifecycleEvents.contains(.applicationTerminated) == true {
                self.analytics?.track(name: "Application Terminated")
            }
        }
    }

#endif
