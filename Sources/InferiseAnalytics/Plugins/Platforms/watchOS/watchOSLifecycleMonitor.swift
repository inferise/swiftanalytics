//
//  watchOSLifecycleMonitor.swift
//
//
//  Created by Brandon Sneed on 6/24/21.
//

#if os(watchOS)

    import Foundation
    import WatchKit

    public protocol watchOSLifecycle {
        func applicationDidFinishLaunching(watchExtension: WKExtension)
        func applicationWillEnterForeground(watchExtension: WKExtension)
        func applicationDidEnterBackground(watchExtension: WKExtension)
        func applicationDidBecomeActive(watchExtension: WKExtension)
        func applicationWillResignActive(watchExtension: WKExtension)
    }

    extension watchOSLifecycle {
        public func applicationDidFinishLaunching(watchExtension: WKExtension) {}
        public func applicationWillEnterForeground(watchExtension: WKExtension) {}
        public func applicationDidEnterBackground(watchExtension: WKExtension) {}
        public func applicationDidBecomeActive(watchExtension: WKExtension) {}
        public func applicationWillResignActive(watchExtension: WKExtension) {}
    }

    class watchOSLifecycleMonitor: PlatformPlugin {
        let type = PluginType.utility
        weak var analytics: Analytics?
        var wasBackgrounded: Bool = false

        private var watchExtension = WKExtension.shared()
        private var appNotifications: [NSNotification.Name] = [WKExtension.applicationDidFinishLaunchingNotification,
                                                               WKExtension.applicationWillEnterForegroundNotification,
                                                               WKExtension.applicationDidEnterBackgroundNotification,
                                                               WKExtension.applicationDidBecomeActiveNotification,
                                                               WKExtension.applicationWillResignActiveNotification]

        required init() {
            self.watchExtension = WKExtension.shared()
            self.setupListeners()
        }

        @objc
        func notificationResponse(notification: NSNotification) {
            switch notification.name {
            case WKExtension.applicationDidFinishLaunchingNotification:
                self.applicationDidFinishLaunching(notification: notification)
            case WKExtension.applicationWillEnterForegroundNotification:
                self.applicationWillEnterForeground(notification: notification)
            case WKExtension.applicationDidEnterBackgroundNotification:
                self.applicationDidEnterBackground(notification: notification)
            case WKExtension.applicationDidBecomeActiveNotification:
                self.applicationDidBecomeActive(notification: notification)
            case WKExtension.applicationWillResignActiveNotification:
                self.applicationWillResignActive(notification: notification)
            default:
                break
            }
        }

        func setupListeners() {
            // Configure the current life cycle events
            let notificationCenter = NotificationCenter.default
            for notification in self.appNotifications {
                notificationCenter.addObserver(self, selector: #selector(self.notificationResponse(notification:)), name: notification, object: nil)
            }
        }

        func applicationDidFinishLaunching(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? watchOSLifecycle {
                    validExt.applicationDidFinishLaunching(watchExtension: self.watchExtension)
                }
            }
        }

        func applicationWillEnterForeground(notification: NSNotification) {
            // watchOS will receive this after didFinishLaunching, which is different
            // from iOS, so ignore until we've been backgrounded at least once.
            if self.wasBackgrounded == false {
                return
            }

            self.analytics?.apply { ext in
                if let validExt = ext as? watchOSLifecycle {
                    validExt.applicationWillEnterForeground(watchExtension: self.watchExtension)
                }
            }
        }

        func applicationDidEnterBackground(notification: NSNotification) {
            // make sure to denote that we were backgrounded.
            self.wasBackgrounded = true

            self.analytics?.apply { ext in
                if let validExt = ext as? watchOSLifecycle {
                    validExt.applicationDidEnterBackground(watchExtension: self.watchExtension)
                }
            }
        }

        func applicationDidBecomeActive(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? watchOSLifecycle {
                    validExt.applicationDidBecomeActive(watchExtension: self.watchExtension)
                }
            }
        }

        func applicationWillResignActive(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? watchOSLifecycle {
                    validExt.applicationWillResignActive(watchExtension: self.watchExtension)
                }
            }
        }
    }

    // MARK: - Inferise Destination Extension

    extension InferiseDestination: watchOSLifecycle {
        public func applicationWillEnterForeground(watchExtension: WKExtension) {
            enterForeground()
        }

        public func applicationDidEnterBackground(watchExtension: WKExtension) {
            enterBackground()
        }
    }

    // MARK: - Interval Based Flush Policy Extension

    extension IntervalBasedFlushPolicy: watchOSLifecycle {
        public func applicationWillEnterForeground(watchExtension: WKExtension) {
            enterForeground()
        }

        public func applicationDidEnterBackground(watchExtension: WKExtension) {
            enterBackground()
        }
    }
#endif
