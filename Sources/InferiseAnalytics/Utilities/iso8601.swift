//
//  iso8601.swift
//  InferiseAnalytics
//
//  Created by Brandon Sneed on 12/8/20.
//

import Foundation

enum InferiseISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.update(with: .withFractionalSeconds)
        return formatter
    }()
}

extension Date {
    func iso8601() -> String {
        InferiseISO8601DateFormatter.shared.string(from: self)
    }
}

extension String {
    func iso8601() -> Date? {
        InferiseISO8601DateFormatter.shared.date(from: self)
    }
}
