//
//  FilePaths.swift
//  HermitFlow
//
//  Phase 1 scaffold for the ongoing runtime refactor.
//

import Foundation

enum FilePaths {
    static let hermitFlowHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hermitflow", isDirectory: true)
    static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("settings.json", isDirectory: false)
    static let codexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
    static let debugLog = URL(fileURLWithPath: "/tmp/hermitflow-debug.log")

    static func expandingTilde(_ path: String) -> URL {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        if path.hasPrefix("~/") {
            let relativePath = String(path.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(relativePath, isDirectory: false)
        }

        return URL(fileURLWithPath: path)
    }
}
