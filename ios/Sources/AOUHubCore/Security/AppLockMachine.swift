import Foundation

public enum BiometricStatus: Sendable, Equatable {
    case available, noHardware, notEnrolled, unavailable
}

public enum BiometricOutcome: Sendable, Equatable {
    case success, failed, cancelled, lockout, notEnrolled, unavailable
}

/// Face ID on iOS (the app target supplies it); a fake in tests/simulator.
public protocol BiometricAuthenticator: Sendable {
    func status() -> BiometricStatus
    func authenticate(reason: String) async -> BiometricOutcome
}

public enum AppLockError: String, Sendable, Equatable {
    case failed, cancelled, lockout, notEnrolled, unavailable

    init(_ outcome: BiometricOutcome) {
        switch outcome {
        case .cancelled: self = .cancelled
        case .lockout: self = .lockout
        case .notEnrolled: self = .notEnrolled
        case .unavailable: self = .unavailable
        case .success, .failed: self = .failed
        }
    }
}

public struct AppLockPolicy: Sendable, Equatable {
    public let relockAfter: TimeInterval
    public let maxFailedAttempts: Int

    public init(relockAfter: TimeInterval, maxFailedAttempts: Int) {
        self.relockAfter = relockAfter
        self.maxFailedAttempts = maxFailedAttempts
    }
}

public struct AppLockState: Sendable, Equatable {
    public var enabled = false
    public var locked = false
    public var authenticating = false
    public var failedAttempts = 0
    public var error: AppLockError?
}

/// The lock's rules with no UI and no LocalAuthentication: same semantics as
/// Android's AppLockController (launch lock, relock after N seconds away,
/// attempts that run out into sign-out, cancel never costs an attempt).
public struct AppLockMachine: Sendable {
    public private(set) var state: AppLockState
    public let policy: AppLockPolicy
    private var backgroundedAt: Date?

    public init(enabled: Bool, policy: AppLockPolicy) {
        self.policy = policy
        state = AppLockState(enabled: enabled, locked: enabled)
    }

    public var attemptsLeft: Int { policy.maxFailedAttempts - state.failedAttempts }

    /// No Face ID tries left: the only way forward is to sign out.
    public var exhausted: Bool { attemptsLeft <= 0 || state.error == .notEnrolled }

    /// A password sign-in already proved who this is: never cover the app right after it.
    public mutating func signedInWithPassword() {
        guard state.enabled else { return }
        state.locked = false
        state.authenticating = false
        state.failedAttempts = 0
        state.error = nil
    }

    public mutating func didEnterBackground(at now: Date) {
        backgroundedAt = now
    }

    public mutating func willEnterForeground(at now: Date) {
        defer { backgroundedAt = nil }
        guard state.enabled, !state.locked, let since = backgroundedAt else { return }
        if now.timeIntervalSince(since) >= policy.relockAfter {
            state.locked = true
            state.error = nil
        }
    }

    /// False when no prompt should be shown (already unlocked, busy, or out of tries).
    public mutating func beginUnlock() -> Bool {
        guard state.locked, !state.authenticating, !exhausted else { return false }
        state.authenticating = true
        state.error = nil
        return true
    }

    public mutating func finishUnlock(_ outcome: BiometricOutcome) {
        state.authenticating = false
        switch outcome {
        case .success:
            state.locked = false
            state.failedAttempts = 0
        case .cancelled:
            state.error = .cancelled
        default:
            state.failedAttempts += 1
            state.error = AppLockError(outcome)
        }
    }

    /// Call only after a successful Face ID check, so nobody enables a lock
    /// their face cannot open.
    public mutating func enableConfirmed() {
        state = AppLockState(enabled: true, locked: false)
    }

    public mutating func disable() {
        state = AppLockState()
    }

    public static func enableError(for outcome: BiometricOutcome) -> AppLockError? {
        outcome == .success ? nil : AppLockError(outcome)
    }
}

/// Persists only the on/off choice.
public protocol LockPreferenceStore: Sendable {
    func isEnabled(default: Bool) -> Bool
    func setEnabled(_ enabled: Bool)
}

public struct UserDefaultsLockPreferenceStore: LockPreferenceStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app_lock_enabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }
}
