import Foundation

struct ClaudeProviderConfigStore {
    private let fileManager: FileManager
    private let hermitFlowHome: URL
    private let claudeSettingsPathsURL: URL
    private let claudeProviderUsageConfigURL: URL

    init(
        fileManager: FileManager = .default,
        hermitFlowHome: URL = FilePaths.hermitFlowHome,
        claudeSettingsPathsURL: URL = FilePaths.claudeSettingsPaths,
        claudeProviderUsageConfigURL: URL = FilePaths.claudeProviderUsageConfig
    ) {
        self.fileManager = fileManager
        self.hermitFlowHome = hermitFlowHome
        self.claudeSettingsPathsURL = claudeSettingsPathsURL
        self.claudeProviderUsageConfigURL = claudeProviderUsageConfigURL
    }

    func loadClaudeSettingsJSONText() -> String {
        guard fileManager.fileExists(atPath: claudeSettingsPathsURL.path) else {
            return Self.defaultClaudeSettingsJSONText
        }

        do {
            let data = try Data(contentsOf: claudeSettingsPathsURL)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return Self.defaultClaudeSettingsJSONText
        }
    }

    func loadClaudeUsageCommandJSONText() -> String {
        let config = loadClaudeProviderUsageConfig()
        let usageCommand = config.usageCommand ?? ClaudeProviderUsageConfig.defaultConfig.usageCommand

        guard let usageCommand else {
            return Self.defaultClaudeUsageCommandJSONText
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(usageCommand)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return Self.defaultClaudeUsageCommandJSONText
        }
    }

    func providerAuthRows() -> [ProviderAuthEnvKeyRow] {
        loadClaudeProviderUsageConfig().providers.map { provider in
            ProviderAuthEnvKeyRow(
                id: provider.id,
                authEnvKey: provider.usageRequest.authEnvKey ?? ""
            )
        }
    }

    func updateClaudeSettingsJSON(from rawInput: String) throws {
        try fileManager.createDirectory(at: hermitFlowHome, withIntermediateDirectories: true)
        let normalizedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalizedInput.isEmpty ? Self.defaultClaudeSettingsJSONText + "\n" : normalizedInput + "\n"
        try Data(text.utf8).write(to: claudeSettingsPathsURL, options: .atomic)
    }

    func updateClaudeUsageCommandJSON(from rawInput: String) throws {
        try fileManager.createDirectory(at: hermitFlowHome, withIntermediateDirectories: true)
        var config = loadClaudeProviderUsageConfig()
        let command = try decodeClaudeUsageCommand(from: rawInput.trimmingCharacters(in: .whitespacesAndNewlines))
        config.usageCommand = command
        try writeClaudeProviderUsageConfig(config)
    }

    func updateClaudeProviderUsageAuthEnvKey(providerID: String, value: String) throws {
        try fileManager.createDirectory(at: hermitFlowHome, withIntermediateDirectories: true)
        var config = loadClaudeProviderUsageConfig()
        guard let index = config.providers.firstIndex(where: { $0.id == providerID }) else {
            return
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        config.providers[index].usageRequest.authEnvKey = normalizedValue.isEmpty ? nil : normalizedValue
        try writeClaudeProviderUsageConfig(config)
    }

    func loadClaudeProviderUsageConfig() -> ClaudeProviderUsageConfig {
        guard fileManager.fileExists(atPath: claudeProviderUsageConfigURL.path) else {
            return ClaudeProviderUsageConfig.defaultConfig
        }

        do {
            let data = try Data(contentsOf: claudeProviderUsageConfigURL)
            return try JSONDecoder().decode(ClaudeProviderUsageConfig.self, from: data)
        } catch {
            return ClaudeProviderUsageConfig.defaultConfig
        }
    }

    private func writeClaudeProviderUsageConfig(_ config: ClaudeProviderUsageConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: claudeProviderUsageConfigURL, options: .atomic)
    }

    private func decodeClaudeUsageCommand(from rawInput: String) throws -> ClaudeProviderUsageCommand {
        let normalizedInput = rawInput.isEmpty ? Self.defaultClaudeUsageCommandJSONText : rawInput
        return try JSONDecoder().decode(ClaudeProviderUsageCommand.self, from: Data(normalizedInput.utf8))
    }

    static let defaultClaudeSettingsJSONText = "{\n  \"paths\": []\n}"
    static let defaultClaudeUsageCommandJSONText = "{\n  \"command\": null,\n  \"window\": \"day\",\n  \"valueKind\": \"usedPercentage\",\n  \"displayLabel\": \"day\",\n  \"timeoutSeconds\": 5\n}"
}
