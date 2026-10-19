import Foundation

/// Typed view of shared/config/app.json. iOS only ever reads `platforms.ios`;
/// the Android block is decoded so a broken file fails loudly on both sides.
public struct SharedAppConfig: Decodable, Sendable {
    public struct AppLock: Decodable, Sendable {
        public let defaultEnabled: Bool
        public let relockAfterSeconds: Int
        public let maxFailedAttempts: Int
    }

    public struct Update: Decodable, Sendable {
        public let provider: String
        public let repository: String
        public let manifestUrl: URL?
        public let latestReleaseUrl: URL?
        public let releasesPageUrl: URL?
        public let manifestHosts: [String]
        public let checkIntervalHours: Int
    }

    public struct Platform: Decodable, Sendable {
        public let biometric: String
        public let update: Update
    }

    public struct Platforms: Decodable, Sendable {
        public let android: Platform
        public let ios: Platform
    }

    /// University endpoints (same values as android/lib/core/env.dart; checked by sync-shared.mjs).
    public struct University: Decodable, Sendable {
        public let sisBase: URL
        public let lmsBase: URL
        public let lmsService: String
    }

    public let appLock: AppLock
    public let platforms: Platforms
    public let university: University

    public var ios: Platform { platforms.ios }

    public var lockPolicy: AppLockPolicy {
        AppLockPolicy(
            relockAfter: TimeInterval(appLock.relockAfterSeconds),
            maxFailedAttempts: appLock.maxFailedAttempts
        )
    }
}
