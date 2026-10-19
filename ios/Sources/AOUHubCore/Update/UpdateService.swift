import Foundation

/// Network boundary, so the update check is tested without a network.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, status: Int)
}

public struct ReleaseInfo: Equatable, Identifiable, Sendable {
    public var id: String { version.description }
    public let version: AppVersion
    public let notes: String
    public let pageURL: URL
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
}

public enum UpdateError: Error, Equatable, Sendable {
    case disabled
    case hostNotAllowed
    case http(Int)
    case malformed
}

public protocol UpdateService: Sendable {
    func check(current: AppVersion) async throws -> UpdateCheckResult
}

/// iOS updates come ONLY from the iOS repository's latest GitHub release
/// (`platforms.ios.update` in shared/config/app.json) — never the Android one.
/// iOS cannot install a package itself, so "update" opens the release page for
/// the sideload/xtool flow.
public struct GitHubReleaseUpdateService: UpdateService {
    private let config: SharedAppConfig.Update
    private let client: HTTPClient
    private static let maxBytes = 256 * 1024

    public init(config: SharedAppConfig.Update, client: HTTPClient) {
        self.config = config
        self.client = client
    }

    public func check(current: AppVersion) async throws -> UpdateCheckResult {
        guard let url = config.latestReleaseUrl else { throw UpdateError.disabled }
        guard isAllowed(url, hosts: config.manifestHosts) else { throw UpdateError.hostNotAllowed }

        let (data, status) = try await client.get(url, headers: [
            "Accept": "application/vnd.github+json",
            "Cache-Control": "no-cache",
        ])
        guard status == 200 else { throw UpdateError.http(status) }
        guard data.count <= Self.maxBytes,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease,
              let latest = AppVersion(release.tagName)
        else { throw UpdateError.malformed }

        guard current < latest else { return .upToDate }
        return .available(ReleaseInfo(version: latest, notes: release.body ?? "", pageURL: pageURL(for: release)))
    }

    /// Only a github.com page of the configured repository is ever opened.
    private func pageURL(for release: GitHubRelease) -> URL {
        let fallback = config.releasesPageUrl ?? URL(string: "https://github.com/\(config.repository)/releases")!
        guard let page = release.htmlUrl,
              page.scheme == "https", page.host == "github.com",
              page.path.hasPrefix("/\(config.repository)/")
        else { return fallback }
        return page
    }

    private func isAllowed(_ url: URL, hosts: [String]) -> Bool {
        url.scheme == "https" && url.user == nil && hosts.contains(url.host ?? "")
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlUrl: URL?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", body, htmlUrl = "html_url", draft, prerelease
        }
    }
}

/// When to check again, and how long "Later" keeps an update quiet.
public struct UpdateSchedule: Sendable {
    public let interval: TimeInterval
    public let snooze: TimeInterval

    public init(intervalHours: Int, snoozeHours: Int = 24) {
        interval = TimeInterval(intervalHours) * 3600
        snooze = TimeInterval(snoozeHours) * 3600
    }

    public func shouldCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public func shouldPrompt(for version: AppVersion, snoozed: (version: String, until: Date)?, now: Date) -> Bool {
        guard let snoozed, snoozed.version == version.description else { return true }
        return now >= snoozed.until
    }
}
