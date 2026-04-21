import XCTest
@testable import HermitFlow

final class ClaudeProviderConfigStoreTests: XCTestCase {
    func testSettingsJSONFallsBackAndWritesNormalizedText() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }

        let settingsURL = root.appendingPathComponent("claude-settings-paths.json")
        let store = ClaudeProviderConfigStore(
            hermitFlowHome: root,
            claudeSettingsPathsURL: settingsURL,
            claudeProviderUsageConfigURL: root.appendingPathComponent("claude-provider-usage.json")
        )

        XCTAssertEqual(store.loadClaudeSettingsJSONText(), ClaudeProviderConfigStore.defaultClaudeSettingsJSONText)

        try store.updateClaudeSettingsJSON(from: "  { \"paths\": [\"/tmp/project\"] }  ")

        let writtenText = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertEqual(writtenText, "{ \"paths\": [\"/tmp/project\"] }\n")
    }

    func testUsageCommandAndProviderAuthKeyRoundTripThroughJSON() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }

        let usageURL = root.appendingPathComponent("claude-provider-usage.json")
        let store = ClaudeProviderConfigStore(
            hermitFlowHome: root,
            claudeSettingsPathsURL: root.appendingPathComponent("claude-settings-paths.json"),
            claudeProviderUsageConfigURL: usageURL
        )

        try store.updateClaudeUsageCommandJSON(from: """
        {
          "command": "ccusage --json",
          "window": "day",
          "valueKind": "remainingPercentage",
          "displayLabel": "quota",
          "timeoutSeconds": 7
        }
        """)
        try store.updateClaudeProviderUsageAuthEnvKey(providerID: "kimi", value: " KIMI_AUTH_TOKEN ")

        let reloadedConfig = store.loadClaudeProviderUsageConfig()
        XCTAssertEqual(reloadedConfig.usageCommand?.command, "ccusage --json")
        XCTAssertEqual(reloadedConfig.usageCommand?.valueKind, .remainingPercentage)
        XCTAssertEqual(reloadedConfig.usageCommand?.displayLabel, "quota")
        XCTAssertEqual(reloadedConfig.usageCommand?.timeoutSeconds, 7)
        XCTAssertEqual(
            reloadedConfig.providers.first(where: { $0.id == "kimi" })?.usageRequest.authEnvKey,
            "KIMI_AUTH_TOKEN"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: usageURL.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermitFlowTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
