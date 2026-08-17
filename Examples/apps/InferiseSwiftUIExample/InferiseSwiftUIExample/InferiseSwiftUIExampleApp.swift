//
//  InferiseSwiftUIExampleApp.swift
//  InferiseSwiftUIExample
//
//  Created by Cody Garvin on 5/24/21.
//

import SwiftUI
import InferiseAnalytics

@main
struct InferiseSwiftUIExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension Analytics {
    static var main = Analytics(configuration:
                                    Configuration(writeKey: "ABCD")
                                    .flushAt(3)
                                    .setTrackedApplicationLifecycleEvents(.all))
}
