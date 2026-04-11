//
//  ClaudeUsageLoader.swift
//  HermitFlow
//
//  Local-first Claude usage loader.
//

import Foundation

enum ClaudeUsageLoader {
    private static let usageFileURL = URL(fileURLWithPath: "/tmp/hermitflow-rl.json")

    static func load() throws -> ClaudeUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: usageFileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: usageFileURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let cachedAt = try usageFileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let snapshot = ClaudeUsageSnapshot(
            fiveHour: parseWindow(named: "five_hour", from: jsonObject),
            sevenDay: parseWindow(named: "seven_day", from: jsonObject),
            cachedAt: cachedAt
        )

        return snapshot.isEmpty ? nil : snapshot
    }

    private static func parseWindow(named name: String, from jsonObject: Any) -> ClaudeUsageWindow? {
        guard let container = findDictionaryValue(forKey: name, in: jsonObject) as? [String: Any],
              let usedPercentage = normalizedPercentage(container["used_percentage"] ?? container["utilization"]) else {
            return nil
        }

        return ClaudeUsageWindow(
            usedPercentage: usedPercentage,
            resetsAt: parseDate(container["resets_at"])
        )
    }

    private static func findDictionaryValue(forKey targetKey: String, in jsonObject: Any) -> Any? {
        if let dictionary = jsonObject as? [String: Any] {
            if let value = dictionary[targetKey] {
                return value
            }

            for value in dictionary.values {
                if let nested = findDictionaryValue(forKey: targetKey, in: value) {
                    return nested
                }
            }
        }

        if let array = jsonObject as? [Any] {
            for value in array {
                if let nested = findDictionaryValue(forKey: targetKey, in: value) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func normalizedPercentage(_ value: Any?) -> Double? {
        guard let value else {
            return nil
        }

        let rawValue: Double?
        switch value {
        case let number as NSNumber:
            rawValue = number.doubleValue
        case let string as String:
            rawValue = Double(string)
        default:
            rawValue = nil
        }

        guard let rawValue else {
            return nil
        }

        if rawValue > 1 {
            return min(max(rawValue / 100, 0), 1)
        }

        return min(max(rawValue, 0), 1)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            return Date(timeIntervalSince1970: number.doubleValue)
        case let string as String:
            if let timestamp = Double(string) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return ISO8601DateFormatter().date(from: string)
        default:
            return nil
        }
    }
}

// TODO: Install a HermitFlow-managed Claude usage bridge that writes /tmp/hermitflow-rl.json
// from local Claude CLI artifacts or hook callbacks, so the app no longer depends on any
// external island tool writing a compatible cache file first.
