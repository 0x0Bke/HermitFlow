//
//  GitHubReleaseUpdateChecker.swift
//  HermitFlow
//
//  Minimal GitHub Releases-based update checker for manual update discovery.
//

import Foundation

struct GitHubReleaseUpdateChecker {
    struct Result {
        let currentVersion: String
        let latestVersion: String
        let isUpdateAvailable: Bool
        let releasePageURL: URL
        let preferredAssetURL: URL?
        let publishedAt: Date?
    }

    enum UpdateCheckError: LocalizedError {
        case invalidRepository
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidRepository:
                return "The GitHub repository configuration is invalid."
            case .invalidResponse:
                return "GitHub returned an unexpected release response."
            case let .httpError(statusCode):
                return "GitHub returned HTTP \(statusCode) while checking updates."
            }
        }
    }

    private let owner: String
    private let repository: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        owner: String = "0x0Bke",
        repository: String = "HermitFlow",
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repository = repository
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func checkForUpdates() async throws -> Result {
        guard
            let encodedOwner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedRepository = repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepository)/releases/latest")
        else {
            throw UpdateCheckError.invalidRepository
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HermitFlow", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.httpError(httpResponse.statusCode)
        }

        let release = try decoder.decode(GitHubLatestRelease.self, from: data)
        let currentVersion = Self.currentAppVersion
        let latestVersion = Self.normalizedVersion(from: release.tagName)
        let preferredAssetURL = preferredAssetURL(in: release.assets)
        let isUpdateAvailable = Self.compareVersions(latestVersion, currentVersion) == .orderedDescending

        return Result(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            isUpdateAvailable: isUpdateAvailable,
            releasePageURL: release.htmlURL,
            preferredAssetURL: preferredAssetURL,
            publishedAt: release.publishedAt
        )
    }

    private func preferredAssetURL(in assets: [GitHubReleaseAsset]) -> URL? {
        let preferredNames = Self.preferredAssetNamesForCurrentArchitecture

        for preferredName in preferredNames {
            if let asset = assets.first(where: { $0.name == preferredName }) {
                return asset.browserDownloadURL
            }
        }

        return nil
    }

    private static var currentAppVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, !shortVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortVersion
        }

        if let buildVersion, !buildVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return buildVersion
        }

        return "0"
    }

    private static var preferredAssetNamesForCurrentArchitecture: [String] {
        #if arch(arm64)
        return ["HermitFlow-arm64.pkg", "HermitFlow-arm64.dmg"]
        #elseif arch(x86_64)
        return ["HermitFlow-intel.pkg", "HermitFlow-intel.dmg", "HermitFlow-x86_64.pkg", "HermitFlow-x86_64.dmg"]
        #else
        return ["HermitFlow.pkg", "HermitFlow.dmg"]
        #endif
    }

    private static func normalizedVersion(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = parseVersionComponents(lhs)
        let rhsComponents = parseVersionComponents(rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0 ..< maxCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func parseVersionComponents(_ version: String) -> [Int] {
        let cleaned = normalizedVersion(from: version)
        let numberPortion = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""

        return numberPortion
            .split(separator: ".")
            .map { component in
                Int(component.filter(\.isNumber)) ?? 0
            }
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
