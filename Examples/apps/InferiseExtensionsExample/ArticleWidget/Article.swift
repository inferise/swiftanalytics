//
//  Article.swift
//  InferiseExtensionsExample
//
//  Created by Alan Charles on 8/15/21.
//

import Foundation
import InferiseAnalytics

struct Article {
    let title: String
    let source: String
    let imageName: String
}

extension Article {

    // Placeholder content for the widget. The upstream sample linked to the
    // vendor's public docs and used their logo as the thumbnail; both are gone.
    // Point these at your own docs and drop artwork into the ArticleThumbnail
    // image set (currently empty, so no image renders).
    private static let thumbnail = "ArticleThumbnail"

    private static let availableLibDocs = [
        Article(title: "Analytics for iOS", source: "https://example.com/docs/ios", imageName: thumbnail),
        Article(title: "Analytics for Android", source: "https://example.com/docs/android", imageName: thumbnail),
        Article(title: "Analytics for React Native", source: "https://example.com/docs/react-native", imageName: thumbnail),
        Article(title: "Analytics for the web", source: "https://example.com/docs/web", imageName: thumbnail),
        Article(title: "Analytics for Node", source: "https://example.com/docs/node", imageName: thumbnail),
    ]

    private static let availableDestDocs = [
        Article(title: "AppsFlyer Destination", source: "https://example.com/docs/destinations/appsflyer", imageName: thumbnail),
        Article(title: "Firebase Destination", source: "https://example.com/docs/destinations/firebase", imageName: thumbnail),
        Article(title: "Facebook App Events Destination", source: "https://example.com/docs/destinations/facebook-app-events", imageName: thumbnail),
        Article(title: "Mixpanel Destination", source: "https://example.com/docs/destinations/mixpanel", imageName: thumbnail),
        Article(title: "Amplitude Destination", source: "https://example.com/docs/destinations/amplitude", imageName: thumbnail),
    ]

    static var libDocs: [Article] {
        return Array(availableLibDocs.shuffled().prefix(2))
    }

    static var destDocs: [Article] {
        return Array(availableDestDocs.shuffled().prefix(2))
    }
}
