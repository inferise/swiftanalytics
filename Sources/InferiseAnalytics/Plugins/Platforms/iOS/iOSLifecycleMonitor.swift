//
//  iOSLifecycleMonitor.swift
//  InferiseAnalytics
//
//  Created by Cody Garvin on 12/4/20.
//

#if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)

    import Foundation
    import UIKit

    /// NOTE: These method signatures are marked optional as application extensions may not have
    /// a UIApplication object available.  See `safeShared` below.
    public protocol iOSLifecycle {
        func applicationDidEnterBackground(application: UIApplication?)
        func applicationWillEnterForeground(application: UIApplication?)
        func application(_ application: UIApplication?, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
        func applicationDidBecomeActive(application: UIApplication?)
        func applicationWillResignActive(application: UIApplication?)
        func applicationDidReceiveMemoryWarning(application: UIApplication?)
        func applicationWillTerminate(application: UIApplication?)
        func applicationSignificantTimeChange(application: UIApplication?)
        func applicationBackgroundRefreshDidChange(application: UIApplication?, refreshStatus: UIBackgroundRefreshStatus)
    }

    extension iOSLifecycle {
        public func applicationDidEnterBackground(application: UIApplication?) {}
        public func applicationWillEnterForeground(application: UIApplication?) {}
        public func application(_ application: UIApplication?, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {}
        public func applicationDidBecomeActive(application: UIApplication?) {}
        public func applicationWillResignActive(application: UIApplication?) {}
        public func applicationDidReceiveMemoryWarning(application: UIApplication?) {}
        public func applicationWillTerminate(application: UIApplication?) {}
        public func applicationSignificantTimeChange(application: UIApplication?) {}
        public func applicationBackgroundRefreshDidChange(application: UIApplication?, refreshStatus: UIBackgroundRefreshStatus) {}
    }

    class iOSLifecycleMonitor: PlatformPlugin {
        let type = PluginType.utility
        weak var analytics: Analytics?

        private var application: UIApplication?
        private var appNotifications: [NSNotification.Name] = [UIApplication.didEnterBackgroundNotification,
                                                               UIApplication.willEnterForegroundNotification,
                                                               UIApplication.didFinishLaunchingNotification,
                                                               UIApplication.didBecomeActiveNotification,
                                                               UIApplication.willResignActiveNotification,
                                                               UIApplication.didReceiveMemoryWarningNotification,
                                                               UIApplication.willTerminateNotification,
                                                               UIApplication.significantTimeChangeNotification,
                                                               UIApplication.backgroundRefreshStatusDidChangeNotification]

        required init() {
            // App extensions can't use UIAppication.shared, so
            // funnel it through something to check; Could be nil.
            self.application = UIApplication.safeShared
            self.setupListeners()
        }

        @objc
        func notificationResponse(notification: NSNotification) {
            switch notification.name {
            case UIApplication.didEnterBackgroundNotification:
                self.didEnterBackground(notification: notification)
            case UIApplication.willEnterForegroundNotification:
                self.applicationWillEnterForeground(notification: notification)
            case UIApplication.didFinishLaunchingNotification:
                self.didFinishLaunching(notification: notification)
            case UIApplication.didBecomeActiveNotification:
                self.didBecomeActive(notification: notification)
            case UIApplication.willResignActiveNotification:
                self.willResignActive(notification: notification)
            case UIApplication.didReceiveMemoryWarningNotification:
                self.didReceiveMemoryWarning(notification: notification)
            case UIApplication.significantTimeChangeNotification:
                self.significantTimeChange(notification: notification)
            case UIApplication.backgroundRefreshStatusDidChangeNotification:
                self.backgroundRefreshDidChange(notification: notification)
            case UIApplication.willTerminateNotification:
                self.willTerminate(notification: notification)
            default:
                break
            }
        }

        func setupListeners() {
            // Configure the current life cycle events
            let notificationCenter = NotificationCenter.default
            for notification in self.appNotifications {
                notificationCenter.addObserver(self, selector: #selector(self.notificationResponse(notification:)), name: notification, object: self.application)
            }
        }

        func applicationWillEnterForeground(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationWillEnterForeground(application: self.application)
                }
            }
        }

        func didEnterBackground(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationDidEnterBackground(application: self.application)
                }
            }
        }

        func didFinishLaunching(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    let options = notification.userInfo as? [UIApplication.LaunchOptionsKey: Any]
                    validExt.application(self.application, didFinishLaunchingWithOptions: options)
                }
            }
        }

        func didBecomeActive(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationDidBecomeActive(application: self.application)
                }
            }
        }

        func willResignActive(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationWillResignActive(application: self.application)
                }
            }
        }

        func didReceiveMemoryWarning(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationDidReceiveMemoryWarning(application: self.application)
                }
            }
        }

        func willTerminate(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationWillTerminate(application: self.application)
                }
            }
        }

        func significantTimeChange(notification: NSNotification) {
            self.analytics?.apply { ext in
                if let validExt = ext as? iOSLifecycle {
                    validExt.applicationSignificantTimeChange(application: self.application)
                }
            }
        }

        func backgroundRefreshDidChange(notification: NSNotification) {
            // Not only would we not get this in an App Extension, but it would
            // be useless since we couldn't provide the application object or
            // the refreshStatus value.
            if !isAppExtension, let application = UIApplication.safeShared {
                self.analytics?.apply { ext in
                    if let validExt = ext as? iOSLifecycle {
                        validExt.applicationBackgroundRefreshDidChange(
                            application: application,
                            refreshStatus: application.backgroundRefreshStatus
                        )
                    }
                }
            }
        }
    }

    // MARK: - Inferise Destination Extension

    extension InferiseDestination: iOSLifecycle {
        public func applicationWillEnterForeground(application: UIApplication?) {
            enterForeground()
        }

        public func applicationDidEnterBackground(application: UIApplication?) {
            enterBackground()
        }
    }

    extension InferiseDestination.UploadTaskInfo {
        init(url: URL?, data: Data?, task: any DataTask) {
            self.url = url
            self.data = data
            self.task = task

            if let application = UIApplication.safeShared,
               let urlTask = task as? URLSessionTask {
                var taskIdentifier: UIBackgroundTaskIdentifier = .invalid
                taskIdentifier = application.beginBackgroundTask {
                    urlTask.cancel()
                    application.endBackgroundTask(taskIdentifier)
                }

                self.cleanup = {
                    application.endBackgroundTask(taskIdentifier)
                }
            }
        }
    }

    // MARK: - Interval Based Flush Policy Extension

    extension IntervalBasedFlushPolicy: iOSLifecycle {
        public func applicationWillEnterForeground(application: UIApplication?) {
            enterForeground()
        }

        public func applicationDidEnterBackground(application: UIApplication?) {
            enterBackground()
        }
    }

    extension UIApplication {
        static var safeShared: UIApplication? {
            // UIApplication.shared is not available in app extensions so try to get
            // it in a way that's safe for both.

            // if we are NOT an app extension, we need to get UIApplication.shared
            if !isAppExtension {
                // getting it like this allows us to avoid the compiler error that would
                // be generated even though we're guarding against app extensions.
                // there's no preprocessor macro or @available macro to help us here unfortunately
                // so this is the best i could do.
                return value(forKeyPath: "sharedApplication") as? UIApplication
            }
            // if we ARE an app extension, send back nil since we have no way to get the
            // application instance.
            return nil
        }
    }

#endif
