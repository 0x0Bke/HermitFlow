//
//  LogRetentionCleaner.swift
//  HermitFlow
//

import Foundation

struct LogRetentionCleaner {
    private let fileManager: FileManager
    private let now: () -> Date

    private let maxLogBytes: UInt64 = 5 * 1024 * 1024
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    init(fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
    }

    func cleanStartupArtifacts() {
        [
            FilePaths.debugLog,
            FilePaths.approvalDebugLog,
            FilePaths.claudeDebugLog
        ].forEach(rotateLogIfNeeded)

        [
            FilePaths.claudeUsageCache,
            FilePaths.claudeStatusLineDebug
        ].forEach(removeCacheIfExpired)
    }

    private func rotateLogIfNeeded(at url: URL) {
        guard fileManager.fileExists(atPath: url.path),
              let fileSize = fileSize(at: url),
              fileSize > maxLogBytes else {
            return
        }

        let rotatedURL = url.appendingPathExtension("1")
        try? fileManager.removeItem(at: rotatedURL)

        do {
            try fileManager.moveItem(at: url, to: rotatedURL)
        } catch {
            try? fileManager.removeItem(at: url)
        }
    }

    private func removeCacheIfExpired(at url: URL) {
        guard fileManager.fileExists(atPath: url.path),
              let modifiedAt = modificationDate(at: url),
              now().timeIntervalSince(modifiedAt) > maxCacheAge else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    private func fileSize(at url: URL) -> UInt64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        if let fileSize = attributes[.size] as? UInt64 {
            return fileSize
        }

        return (attributes[.size] as? NSNumber)?.uint64Value
    }

    private func modificationDate(at url: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return attributes[.modificationDate] as? Date
    }
}
